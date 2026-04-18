import { supabase } from './supabase';
import { sendTextMessage, formatMessage } from './evolution';
import { applyJitter, sleep } from './rateLimits';
import { recordSent } from './counters';

let _timer: NodeJS.Timeout | null = null;
let _running = false;

// Consecutive-failure streak per agent. 3 in a row → pause queue + alert.
const _failStreak = new Map<string, number>();
const FAIL_STREAK_THRESHOLD = 3;

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
      clients!inner(name, phone_number, is_active, email, client_property_links(position, property_links(link))),
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
        if (isTransientFailure(statusCode)) {
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
          .update({ status: 'failed', error_detail: 'Agent has no WhatsApp instance configured' })
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
        const { error: updateErr } = await supabase
          .from('follow_up_messages')
          .update({ status: 'failed', error_detail: error ?? 'Unknown error' })
          .eq('id', msg.id);
        if (updateErr) console.error(`[Scheduler] Failed to mark message ${msg.id} as failed:`, updateErr);

        if (isTransientFailure(statusCode)) {
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

  const candidates: Date[] = [];
  if (nextFup)  candidates.push(new Date(nextFup.send_at));
  if (nextCold) candidates.push(new Date(nextCold.next_send_at));

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

    // 3. Find when the next message is due
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
