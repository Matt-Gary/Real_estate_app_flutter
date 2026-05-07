import { supabase } from './supabase';
import { sendTextMessage, formatMessage } from './evolution';
import { applyJitter, sleep, localYmd } from './rateLimits';
import { recordSent, applyScheduledDelta } from './counters';

let _timer: NodeJS.Timeout | null = null;
let _running = false;

// Consecutive-failure streak per agent. 3 in a row → pause queue + alert.
const _failStreak = new Map<string, number>();
const FAIL_STREAK_THRESHOLD = 3;

// Per-message retry budget for transient failures (network / 5xx). 4xx and any
// failure beyond MAX_RETRIES are marked permanently failed.
const MAX_RETRIES = 3;
// Backoff in seconds: 1m, 5m, 15m. Index = retry attempt about to be made.
const RETRY_BACKOFF_SECS = [60, 300, 900];

function nextRetryAt(retriesSoFar: number): string {
  const seconds = RETRY_BACKOFF_SECS[Math.min(retriesSoFar, RETRY_BACKOFF_SECS.length - 1)];
  return new Date(Date.now() + seconds * 1000).toISOString();
}

async function pauseAgentQueue(agentId: string, reason: string, severity: 'warning' | 'critical' = 'critical') {
  try {
    await supabase
      .from('agents')
      .update({ queue_paused_at: new Date().toISOString(), queue_paused_reason: reason })
      .eq('id', agentId)
      .is('queue_paused_at', null);    // only pause if not already paused

    await supabase.from('agent_alerts').insert({
      agent_id: agentId,
      kind: 'pending_stuck',
      severity,
      message: `Fila pausada automaticamente: ${reason}`,
    });
    console.warn(`[Scheduler] Paused agent ${agentId}: ${reason}`);
  } catch (err) {
    console.error('[Scheduler] pauseAgentQueue failed:', err);
  }
}

function isTransientFailure(statusCode: number | null): boolean {
  if (statusCode === null) return true;          // network / timeout
  if (statusCode >= 500 && statusCode < 600) return true;
  return false;
}

// ── Cold clients ──────────────────────────────────────────────────────────────

async function fetchDueColdClients() {
  const now = new Date().toISOString();
  const { data, error } = await supabase
    .from('cold_clients')
    .select(`
      *,
      clients!inner(name, phone_number, is_active, email, opted_out_at, client_property_links(position, property_links(link))),
      agents(id, whatsapp_instance_name, queue_paused_at)
    `)
    .eq('is_active', true)
    .lte('next_send_at', now);

  if (error) throw new Error(`fetchDueColdClients: ${error.message}`);
  const seenCold = new Set<string>();
  return (data ?? []).filter((row: any) => {
    if (!row.clients?.is_active) return false;
    if (row.agents?.queue_paused_at) return false;   // skip paused agents
    if (seenCold.has(row.id)) return false;
    seenCold.add(row.id);
    return true;
  });
}

async function sendColdBatch(rows: any[]) {
  for (const row of rows) {
    try {
      const client = row.clients ?? {};
      const agentId: string | null = row.agents?.id ?? null;
      const instanceName: string | null = row.agents?.whatsapp_instance_name ?? null;
      if (!instanceName || !agentId) {
        console.warn(`[ColdScheduler] cold_client ${row.id} — agent missing, skipping.`);
        await supabase.from('cold_clients').update({ is_active: false }).eq('id', row.id);
        continue;
      }

      // Skip and deactivate cold sequence if the client opted out after launch.
      if (client.opted_out_at) {
        console.log(`[ColdScheduler] cold_client ${row.id} — client opted out, deactivating sequence.`);
        await supabase.from('cold_clients').update({ is_active: false }).eq('id', row.id);
        continue;
      }

      // Resolve template body
      let body = '';
      if (row.template_id) {
        const { data: tpl } = await supabase
          .from('agent_templates')
          .select('body')
          .eq('id', row.template_id)
          .maybeSingle();
        body = tpl?.body ?? '';
      }

      if (!body) {
        console.warn(`[ColdScheduler] cold_client ${row.id} has no template body — deactivating.`);
        await supabase.from('cold_clients').update({ is_active: false }).eq('id', row.id);
        continue;
      }

      const rawLinks = (client.client_property_links ?? [])
        .sort((a: any, b: any) => a.position - b.position)
        .map((cpl: any) => cpl.property_links?.link ?? '');
      const formatted = formatMessage(body, client, rawLinks);

      // Randomized jitter before each send — never exactly on the scheduled minute
      await sleep(applyJitter());

      const { success, statusCode, error } = await sendTextMessage(client.phone_number ?? '', formatted, instanceName);

      if (success) {
        _failStreak.set(agentId, 0);
        const sentAtIso = new Date().toISOString();
        const newSent = (row.messages_sent ?? 0) + 1;
        const hitLimit = row.max_messages != null && newSent >= row.max_messages;
        const nextSendAt = new Date(Date.now() + row.interval_days * 86_400_000).toISOString();

        const { error: updateErr } = await supabase
          .from('cold_clients')
          .update({
            messages_sent: newSent,
            next_send_at:  hitLimit ? null : nextSendAt,
            is_active:     !hitLimit,
          })
          .eq('id', row.id);

        if (updateErr) console.error(`[ColdScheduler] Failed to update cold_client ${row.id}:`, updateErr);
        else if (hitLimit) console.log(`[ColdScheduler] cold_client ${row.id} reached max_messages.`);

        await recordSent(agentId, sentAtIso);
      } else {
        console.error(`[ColdScheduler] Failed to send cold message for ${row.id}: ${error}`);
        const isTransient = isTransientFailure(statusCode);

        // Always push next_send_at forward — without this, the same row gets
        // retried every ~10s (the scheduler MIN_SLEEP) until the agent's queue
        // is forcibly paused, causing collateral damage to follow-ups and
        // campaigns. cold_clients has no per-row retry counter so we rely on
        // the cross-source failure-streak for escalation.
        let backoffSec: number;
        if (isTransient) {
          const streakSoFar = _failStreak.get(agentId) ?? 0;
          backoffSec = RETRY_BACKOFF_SECS[Math.min(streakSoFar, RETRY_BACKOFF_SECS.length - 1)];
        } else {
          // Permanent failure (4xx) — likely bad phone number or template.
          // Push out by an hour so the agent has time to notice/fix without
          // the row deactivating itself permanently.
          backoffSec = 3600;
        }
        const nextAttempt = new Date(Date.now() + backoffSec * 1000).toISOString();
        await supabase
          .from('cold_clients')
          .update({ next_send_at: nextAttempt })
          .eq('id', row.id);

        if (isTransient) {
          const n = (_failStreak.get(agentId) ?? 0) + 1;
          _failStreak.set(agentId, n);
          if (n >= FAIL_STREAK_THRESHOLD) {
            await pauseAgentQueue(agentId, `${n} consecutive send failures`);
            _failStreak.set(agentId, 0);
          }
        }
      }
    } catch (err) {
      console.error(`[ColdScheduler] Unexpected error processing cold_client ${row.id}:`, err);
    }
  }
}

// ── Campaigns ─────────────────────────────────────────────────────────────────

interface CampaignRecipientRow {
  id: string;
  campaign_id: string;
  client_id: string;
  scheduled_for: string;
  retry_count: number | null;
  campaigns: {
    id: string;
    agent_id: string;
    template_body: string;
    status: string;
    sent_count: number;
    failed_count: number;
    skipped_count: number;
    total_recipients: number;
  } | null;
  clients: {
    id: string;
    name: string;
    phone_number: string;
    email: string | null;
    archived_at: string | null;
    opted_out_at: string | null;
    is_active: boolean;
    client_property_links: any[];
    agents: {
      id: string;
      whatsapp_instance_name: string | null;
      queue_paused_at: string | null;
    } | null;
  } | null;
}

async function fetchDueCampaignRecipients(): Promise<CampaignRecipientRow[]> {
  const now = new Date().toISOString();
  const { data, error } = await supabase
    .from('campaign_recipients')
    .select(`
      id, campaign_id, client_id, scheduled_for, retry_count,
      campaigns!inner(id, agent_id, template_body, status, sent_count, failed_count, skipped_count, total_recipients),
      clients!inner(
        id, name, phone_number, email, archived_at, opted_out_at, is_active,
        client_property_links(position, property_links(link)),
        agents(id, whatsapp_instance_name, queue_paused_at)
      )
    `)
    .eq('status', 'pending')
    .lte('scheduled_for', now)
    .order('scheduled_for');

  if (error) throw new Error(`fetchDueCampaignRecipients: ${error.message}`);

  return (data ?? []).filter((r: any) => {
    if (!r.campaigns || r.campaigns.status !== 'running') return false;
    if (!r.clients) return false;
    if (r.clients.agents?.queue_paused_at) return false;
    return true;
  }) as unknown as CampaignRecipientRow[];
}

async function markRecipientSkipped(
  recipientId: string,
  campaignId: string,
  scheduledFor: string,
  agentId: string,
  reason: string,
) {
  await supabase
    .from('campaign_recipients')
    .update({ status: 'skipped', error_detail: reason })
    .eq('id', recipientId);

  // Read-then-write counter bump. Safe under the single-process scheduler.
  const { data: c } = await supabase
    .from('campaigns')
    .select('skipped_count')
    .eq('id', campaignId)
    .maybeSingle();
  await supabase
    .from('campaigns')
    .update({ skipped_count: (c?.skipped_count ?? 0) + 1 })
    .eq('id', campaignId);

  // Release the scheduled-count slot for that day.
  const day = localYmd(scheduledFor);
  await applyScheduledDelta(agentId, { [day]: -1 });
}

async function maybeCompleteCampaign(campaignId: string) {
  const { count } = await supabase
    .from('campaign_recipients')
    .select('*', { count: 'exact', head: true })
    .eq('campaign_id', campaignId)
    .eq('status', 'pending');
  if ((count ?? 0) === 0) {
    await supabase
      .from('campaigns')
      .update({ status: 'completed', completed_at: new Date().toISOString() })
      .eq('id', campaignId)
      .eq('status', 'running');
  }
}

async function sendCampaignBatch(rows: CampaignRecipientRow[]) {
  // Per product decision: campaigns only skip opted-out clients. Archived
  // clients, missing phones, and 48h-gap violations are all allowed through.
  // (No-phone sends will fail at the Evolution API and be marked failed.)
  for (const row of rows) {
    try {
      const client = row.clients!;
      const campaign = row.campaigns!;
      const agentId = client.agents?.id ?? null;
      const instanceName = client.agents?.whatsapp_instance_name ?? null;

      if (!agentId || !instanceName) {
        await markRecipientSkipped(row.id, campaign.id, row.scheduled_for, campaign.agent_id, 'Agente sem instância WhatsApp configurada');
        continue;
      }
      if (client.opted_out_at) {
        await markRecipientSkipped(row.id, campaign.id, row.scheduled_for, agentId, 'Cliente removeu o consentimento');
        continue;
      }

      // Re-check: skip if a pending follow-up now shares the same SP calendar day.
      {
        const day = localYmd(row.scheduled_for);
        const dayStartUtc = new Date(`${day}T03:00:00Z`).toISOString();
        const [y, m, d2] = day.split('-').map(Number);
        const nextDate = new Date(Date.UTC(y, m - 1, d2 + 1));
        const dayEndUtc = new Date(nextDate.getTime() + 3 * 60 * 60 * 1000).toISOString();
        const { data: sameDay } = await supabase
          .from('follow_up_messages')
          .select('id')
          .eq('client_id', client.id)
          .eq('status', 'pending')
          .gte('send_at', dayStartUtc)
          .lt('send_at', dayEndUtc)
          .limit(1);
        if (sameDay && sameDay.length > 0) {
          await markRecipientSkipped(row.id, campaign.id, row.scheduled_for, agentId, 'Follow-up pendente no mesmo dia');
          continue;
        }
      }

      // Render and jitter
      const rawLinks = (client.client_property_links ?? [])
        .sort((a: any, b: any) => a.position - b.position)
        .map((cpl: any) => cpl.property_links?.link ?? '');
      const body = formatMessage(campaign.template_body, client as any, rawLinks);

      await sleep(applyJitter());

      const { success, statusCode, error } = await sendTextMessage(client.phone_number, body, instanceName);

      if (success) {
        _failStreak.set(agentId, 0);
        const sentAtIso = new Date().toISOString();

        // 1. Persist a `follow_up_messages` row (source='campaign') so audit/log
        //    pipelines treat it like every other send. Retry once on failure
        //    since the message has already been delivered — we must keep audit
        //    gaps visible rather than silently dropping them.
        let msgId: string | null = null;
        let auditError: string | null = null;
        for (let attempt = 0; attempt < 2; attempt++) {
          const { data: msg, error: msgErr } = await supabase
            .from('follow_up_messages')
            .insert({
              client_id: client.id,
              seq: null,
              body,
              send_at: row.scheduled_for,
              status: 'sent',
              sent_at: sentAtIso,
              source: 'campaign',
              campaign_id: campaign.id,
            })
            .select('id')
            .single();
          if (!msgErr && msg?.id) { msgId = msg.id; auditError = null; break; }
          auditError = msgErr?.message ?? 'unknown audit insert error';
          console.error(`[CampaignScheduler] follow_up_messages insert attempt ${attempt + 1} failed for recipient ${row.id}:`, msgErr);
        }

        // Mark recipient sent regardless — the message physically went out.
        // If audit row is missing, surface it via error_detail and an alert.
        await supabase
          .from('campaign_recipients')
          .update({
            status: 'sent',
            sent_at: sentAtIso,
            message_id: msgId,
            error_detail: auditError ? `audit_gap: ${auditError}` : null,
          })
          .eq('id', row.id);

        if (auditError) {
          await supabase.from('agent_alerts').insert({
            agent_id: agentId,
            kind: 'audit_gap',
            severity: 'warning',
            message: `Mensagem de campanha enviada mas linha de auditoria não foi gravada (recipient ${row.id}).`,
          });
        }

        await supabase
          .from('campaigns')
          .update({ sent_count: (campaign.sent_count ?? 0) + 1 })
          .eq('id', campaign.id);

        await recordSent(agentId, sentAtIso);

        // Best-effort send_log
        await supabase.from('send_log').insert({
          message_id: msgId,
          success: true,
          response_status: statusCode,
          error_detail: null,
        });
      } else {
        const isTransient = isTransientFailure(statusCode);
        const retriesSoFar = row.retry_count ?? 0;
        const willRetry = isTransient && retriesSoFar < MAX_RETRIES;
        const nowIso = new Date().toISOString();

        if (willRetry) {
          // Push the slot out by a backoff window and leave status='pending'.
          // The quota slot stays reserved — we still intend to send.
          await supabase
            .from('campaign_recipients')
            .update({
              retry_count: retriesSoFar + 1,
              last_error_at: nowIso,
              scheduled_for: nextRetryAt(retriesSoFar),
              error_detail: `transient: ${error ?? statusCode ?? 'unknown'}`,
            })
            .eq('id', row.id);
        } else {
          // Permanent failure (4xx, or transient retries exhausted).
          await supabase
            .from('campaign_recipients')
            .update({
              status: 'failed',
              error_detail: error ?? 'Erro desconhecido',
              last_error_at: nowIso,
            })
            .eq('id', row.id);

          await supabase
            .from('campaigns')
            .update({ failed_count: (campaign.failed_count ?? 0) + 1 })
            .eq('id', campaign.id);

          // Release the scheduled-count slot — failed isn't a "sent" for daily-cap purposes.
          const day = localYmd(row.scheduled_for);
          await applyScheduledDelta(agentId, { [day]: -1 });
        }

        if (isTransient) {
          const n = (_failStreak.get(agentId) ?? 0) + 1;
          _failStreak.set(agentId, n);
          if (n >= FAIL_STREAK_THRESHOLD) {
            await pauseAgentQueue(agentId, `${n} consecutive send failures`);
            _failStreak.set(agentId, 0);
          }
        }
      }

      await maybeCompleteCampaign(campaign.id);
    } catch (err) {
      console.error(`[CampaignScheduler] Unexpected error processing recipient ${row.id}:`, err);
    }
  }
}

// ── Core logic ────────────────────────────────────────────────────────────────

async function fetchPendingDueMessages() {
  const now = new Date().toISOString();
  const { data, error } = await supabase
    .from('follow_up_messages')
    .select(`
      *,
      clients!inner(
        name, phone_number, is_active, email,
        client_property_links(position, property_links(link)),
        agents(id, whatsapp_instance_name, queue_paused_at)
      )
    `)
    .eq('status', 'pending')
    .lte('send_at', now)
    .order('send_at');

  if (error) throw new Error(`fetchPendingDueMessages: ${error.message}`);
  const seen = new Set<string>();
  return (data ?? []).filter((m: any) => {
    if (!m.clients?.is_active) return false;
    if (m.clients?.agents?.queue_paused_at) return false;  // skip paused agents
    if (seen.has(m.id)) return false;
    seen.add(m.id);
    return true;
  });
}

async function fetchNextPendingPerClient() {
  const { data, error } = await supabase
    .from('follow_up_messages')
    .select(`
      *,
      clients!inner(
        name, phone_number, is_active, email,
        client_property_links(position, property_links(link)),
        agents(id, whatsapp_instance_name, queue_paused_at)
      )
    `)
    .eq('status', 'pending')
    .order('client_id')
    .order('seq');

  if (error) throw new Error(`fetchNextPendingPerClient: ${error.message}`);

  const seen = new Set<string>();
  const result: any[] = [];
  for (const m of (data ?? [])) {
    if (!m.clients?.is_active) continue;
    if (m.clients?.agents?.queue_paused_at) continue;
    if (!seen.has(m.client_id)) {
      seen.add(m.client_id);
      result.push(m);
    }
  }
  return result;
}

async function sendBatch(messages: any[]) {
  for (const msg of messages) {
    try {
      const client = msg.clients ?? {};
      const agentId: string | null = client.agents?.id ?? null;
      const instanceName: string | null = client.agents?.whatsapp_instance_name ?? null;

      if (!instanceName || !agentId) {
        console.warn(`[Scheduler] Message ${msg.id} — agent missing, marking failed.`);
        await supabase
          .from('follow_up_messages')
          .update({ status: 'failed', error_detail: 'Agente sem instância WhatsApp configurada' })
          .eq('id', msg.id);
        continue;
      }

      const rawLinks = (client.client_property_links ?? [])
        .sort((a: any, b: any) => a.position - b.position)
        .map((cpl: any) => cpl.property_links?.link ?? '');
      const body  = formatMessage(msg.body, client, rawLinks);
      const phone = client.phone_number ?? '';

      // Randomized jitter — spreads bursts across 5–30s so we never fire the
      // whole batch at the exact cron tick.
      await sleep(applyJitter());

      const { success, statusCode, error } = await sendTextMessage(phone, body, instanceName);

      if (success) {
        _failStreak.set(agentId, 0);
        const sentAtIso = new Date().toISOString();
        const { error: updateErr } = await supabase
          .from('follow_up_messages')
          .update({ status: 'sent', sent_at: sentAtIso })
          .eq('id', msg.id);
        if (updateErr) console.error(`[Scheduler] Failed to mark message ${msg.id} as sent:`, updateErr);
        await recordSent(agentId, sentAtIso);
      } else {
        const isTransient = isTransientFailure(statusCode);
        const retriesSoFar = msg.retry_count ?? 0;
        const willRetry = isTransient && retriesSoFar < MAX_RETRIES;
        const nowIso = new Date().toISOString();

        if (willRetry) {
          // Push send_at out by a backoff window. Status stays 'pending' so the
          // scheduler picks it up again. Quota slot stays reserved.
          const { error: updateErr } = await supabase
            .from('follow_up_messages')
            .update({
              retry_count: retriesSoFar + 1,
              last_error_at: nowIso,
              send_at: nextRetryAt(retriesSoFar),
              error_detail: `transient: ${error ?? statusCode ?? 'unknown'}`,
            })
            .eq('id', msg.id);
          if (updateErr) console.error(`[Scheduler] Failed to bump retry on message ${msg.id}:`, updateErr);
        } else {
          // Permanent failure (4xx, or transient retries exhausted).
          const { error: updateErr } = await supabase
            .from('follow_up_messages')
            .update({
              status: 'failed',
              error_detail: error ?? 'Erro desconhecido',
              last_error_at: nowIso,
            })
            .eq('id', msg.id);
          if (updateErr) console.error(`[Scheduler] Failed to mark message ${msg.id} as failed:`, updateErr);

          // Release the scheduled-count slot — failed isn't a "sent" for daily-cap purposes.
          try {
            const day = localYmd(msg.send_at);
            await applyScheduledDelta(agentId, { [day]: -1 });
          } catch (relErr) {
            console.error(`[Scheduler] Failed to release quota for message ${msg.id}:`, relErr);
          }
        }

        if (isTransient) {
          const n = (_failStreak.get(agentId) ?? 0) + 1;
          _failStreak.set(agentId, n);
          if (n >= FAIL_STREAK_THRESHOLD) {
            await pauseAgentQueue(agentId, `${n} consecutive send failures`);
            _failStreak.set(agentId, 0);
          }
        }
      }

      const { error: logErr } = await supabase.from('send_log').insert({
        message_id:      msg.id,
        success,
        response_status: statusCode,
        error_detail:    error,
      });
      if (logErr) console.error(`[Scheduler] Failed to write send_log for message ${msg.id}:`, logErr);
    } catch (err) {
      console.error(`[Scheduler] Unexpected error processing message ${msg.id}:`, err);
    }
  }
}

// ── Smart sleep: find the next send_at in the DB ──────────────────────────────

async function fetchNextSendAt(): Promise<Date | null> {
  const now = new Date().toISOString();

  // Next regular follow-up message (ignore paused agents)
  const { data: fupData } = await supabase
    .from('follow_up_messages')
    .select('send_at, clients!inner(is_active, agents(queue_paused_at))')
    .eq('status', 'pending')
    .gt('send_at', now)
    .order('send_at')
    .limit(10);

  const nextFup = (fupData ?? []).find(
    (m: any) => m.clients?.is_active === true && !m.clients?.agents?.queue_paused_at,
  );

  // Next cold client send
  const { data: coldData } = await supabase
    .from('cold_clients')
    .select('next_send_at, agents(queue_paused_at)')
    .eq('is_active', true)
    .not('next_send_at', 'is', null)
    .gt('next_send_at', now)
    .order('next_send_at')
    .limit(10);

  const nextCold = (coldData ?? []).find((c: any) => !c.agents?.queue_paused_at) ?? null;

  // Next campaign recipient (only running campaigns, only non-paused agents)
  const { data: campData } = await supabase
    .from('campaign_recipients')
    .select('scheduled_for, campaigns!inner(status, agents(queue_paused_at))')
    .eq('status', 'pending')
    .gt('scheduled_for', now)
    .order('scheduled_for')
    .limit(10);

  const nextCampaign = (campData ?? []).find((r: any) =>
    r.campaigns?.status === 'running' && !r.campaigns?.agents?.queue_paused_at,
  ) ?? null;

  const candidates: Date[] = [];
  if (nextFup)      candidates.push(new Date(nextFup.send_at));
  if (nextCold)     candidates.push(new Date(nextCold.next_send_at));
  if (nextCampaign) candidates.push(new Date(nextCampaign.scheduled_for));

  if (candidates.length === 0) return null;
  return candidates.reduce((a, b) => (a < b ? a : b));
}

// ── Main loop ─────────────────────────────────────────────────────────────────

const MIN_SLEEP_MS  = 10_000;        // never sleep less than 10 seconds
const MAX_SLEEP_MS  = 60 * 60_000;   // never sleep more than 1 hour (safety cap)
const OVERDUE_GRACE = 5_000;         // wait 5s after wake-up before sending

async function tick() {
  if (!_running) return;

  try {
    // 1. Send regular follow-up messages due right now
    const messages = await fetchPendingDueMessages();
    if (messages.length > 0) {
      console.log(`[Scheduler] Sending ${messages.length} message(s).`);
      await sendBatch(messages);
    }

    // 2. Send cold client messages due right now
    const coldRows = await fetchDueColdClients();
    if (coldRows.length > 0) {
      console.log(`[ColdScheduler] Sending ${coldRows.length} cold message(s).`);
      await sendColdBatch(coldRows);
    }

    // 3. Send campaign recipients due right now
    const campaignRows = await fetchDueCampaignRecipients();
    if (campaignRows.length > 0) {
      console.log(`[CampaignScheduler] Sending ${campaignRows.length} campaign message(s).`);
      await sendCampaignBatch(campaignRows);
    }

    // 4. Find when the next message is due
    const nextAt = await fetchNextSendAt();

    let sleepMs: number;

    if (!nextAt) {
      sleepMs = MAX_SLEEP_MS;
      console.log('[Scheduler] No upcoming messages. Sleeping 1 hour.');
    } else {
      const msUntilNext = nextAt.getTime() - Date.now();
      sleepMs = Math.max(MIN_SLEEP_MS, msUntilNext + OVERDUE_GRACE);
      console.log(`[Scheduler] Next message at ${nextAt.toISOString()} — sleeping ${Math.round(sleepMs / 1000)}s.`);
    }

    sleepMs = Math.min(sleepMs, MAX_SLEEP_MS);
    _timer = setTimeout(tick, sleepMs);

  } catch (err) {
    console.error('[Scheduler] Error:', err);
    _timer = setTimeout(tick, 60_000);
  }
}

// ── Public API ────────────────────────────────────────────────────────────────

export function startScheduler() {
  if (_running) return;
  _running = true;
  console.log('[Scheduler] Started — smart sleep mode.');
  tick(); // kick off immediately
}

export function stopScheduler() {
  _running = false;
  if (_timer) { clearTimeout(_timer); _timer = null; }
  console.log('[Scheduler] Stopped.');
}

export async function sendNow(): Promise<{ sent: number }> {
  const messages = await fetchNextPendingPerClient();
  if (messages.length === 0) {
    console.log('[SendNow] No pending messages.');
    return { sent: 0 };
  }
  console.log(`[SendNow] Sending ${messages.length} message(s).`);
  await sendBatch(messages);
  return { sent: messages.length };
}

// ── Called whenever a new message is scheduled ────────────────────────────────
// Import and call this from your clients route after inserting messages,
// so the scheduler wakes up immediately instead of waiting out its current sleep.

export function nudgeScheduler() {
  if (!_running) return;
  if (_timer) { clearTimeout(_timer); _timer = null; }
  console.log('[Scheduler] Nudged — re-evaluating schedule.');
  tick();
}
