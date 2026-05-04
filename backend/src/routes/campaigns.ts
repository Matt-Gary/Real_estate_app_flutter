import { Router, Request, Response } from 'express';
import { supabase } from '../services/supabase';
import { requireAuth } from '../middleware/auth';
import { nudgeScheduler } from '../services/scheduler';
import { formatMessage } from '../services/evolution';
import { localYmd } from '../services/rateLimits';
import { applyScheduledDelta } from '../services/counters';
import { spreadCampaign, deriveBatchPlan, ClientLite, SpreadRecipient } from '../services/campaignSpreader';
import {
  validateName,
  validateTemplateBody,
  validateDailyQuota,
  validateStartAt,
  ValidationError,
} from '../services/campaignValidation';
import { sendDbError } from '../utils/errors';

const router = Router();
router.use(requireAuth);

// ────────────────────────────────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────────────────────────────────

function bail(res: Response, err: ValidationError, status = 400) {
  res.status(status).json({ error: err.message, code: err.code, field: err.field });
}

async function fetchCampaign(agentId: string, id: string) {
  const { data } = await supabase
    .from('campaigns')
    .select('*')
    .eq('id', id)
    .eq('agent_id', agentId)
    .maybeSingle();
  return data;
}

async function fetchLabelOwned(agentId: string, labelId: string) {
  const { data } = await supabase
    .from('client_labels')
    .select('id, name')
    .eq('id', labelId)
    .eq('agent_id', agentId)
    .maybeSingle();
  return data;
}

// Resolves the eligibility set for a campaign (agent + label scope).
// Per product decision: only opted-out clients are excluded. Archived,
// no-phone, and 48h-gap clients all pass through. The 48h gap is still
// enforced for follow-up/cold sends — campaigns explicitly override it.
async function resolveEligibleClients(agentId: string, labelId: string): Promise<{
  matched: number;
  eligible: { id: string; name: string; phone_number: string; email: string | null }[];
  skipped: {
    optedOut: number;
    optedOutClients: { id: string; name: string }[];
    total: number;
  };
}> {
  const { data: rows, error } = await supabase
    .from('client_label_assignments')
    .select('clients(id, name, phone_number, email, agent_id, archived_at, opted_out_at, client_property_links(position, property_links(link)))')
    .eq('label_id', labelId);

  if (error) throw new Error(`resolveEligibleClients: ${error.message}`);

  const labeled = (rows ?? [])
    .map((r: any) => r.clients)
    .filter((c: any) => c && c.agent_id === agentId);

  const matched = labeled.length;
  const skipped = { optedOut: 0, optedOutClients: [] as { id: string; name: string }[], total: 0 };
  const survivors: any[] = [];

  for (const c of labeled) {
    if (c.opted_out_at) {
      skipped.optedOut++;
      skipped.optedOutClients.push({ id: c.id, name: c.name });
      skipped.total++;
      continue;
    }
    survivors.push(c);
  }

  return {
    matched,
    eligible: survivors.map(c => ({
      id: c.id,
      name: c.name,
      phone_number: c.phone_number,
      email: c.email,
    })),
    skipped,
  };
}

// Returns Map<clientId, Set<YYYY-MM-DD>> of all pending message days (SP TZ)
// for the given clients within the given agent's scope. Merges:
//   1. follow_up_messages with status='pending'
//   2. campaign_recipients with status='pending' on active campaigns
//   3. cold_clients with is_active=true (each has one scheduled next_send_at)
// All queries are explicitly agent-scoped via an inner-join filter.
async function fetchAgentPendingDays(
  agentId: string,
  clientIds: string[],
): Promise<Map<string, Set<string>>> {
  const result = new Map<string, Set<string>>();
  if (clientIds.length === 0) return result;

  const add = (clientId: string, day: string) => {
    if (!result.has(clientId)) result.set(clientId, new Set());
    result.get(clientId)!.add(day);
  };

  // 1. Pending follow-up messages, agent-scoped via clients!inner.
  const fu = await supabase
    .from('follow_up_messages')
    .select('client_id, send_at, clients!inner(agent_id)')
    .in('client_id', clientIds)
    .eq('status', 'pending')
    .eq('clients.agent_id', agentId);

  if (fu.error) throw new Error(`fetchAgentPendingDays(follow_up_messages): ${fu.error.message}`);
  for (const row of (fu.data ?? [])) {
    add(row.client_id as string, localYmd(row.send_at as string));
  }

  // 2. Pending campaign recipients on still-active campaigns of this agent.
  // 'draft' is excluded (no rows yet). 'completed'/'cancelled' are excluded
  // (rows already terminal). 'running'/'paused'/'scheduled' all hold live slots.
  const cr = await supabase
    .from('campaign_recipients')
    .select('client_id, scheduled_for, campaigns!inner(agent_id, status)')
    .in('client_id', clientIds)
    .eq('status', 'pending')
    .eq('campaigns.agent_id', agentId)
    .in('campaigns.status', ['running', 'paused', 'scheduled']);

  if (cr.error) throw new Error(`fetchAgentPendingDays(campaign_recipients): ${cr.error.message}`);
  for (const row of (cr.data ?? [])) {
    add(row.client_id as string, localYmd(row.scheduled_for as string));
  }

  // 3. Active cold-client sequences — each active row carries a next_send_at.
  // cold_clients has its own agent_id column so no join needed.
  const cc = await supabase
    .from('cold_clients')
    .select('client_id, next_send_at')
    .in('client_id', clientIds)
    .eq('agent_id', agentId)
    .eq('is_active', true);

  if (cc.error) throw new Error(`fetchAgentPendingDays(cold_clients): ${cc.error.message}`);
  for (const row of (cc.data ?? [])) {
    add(row.client_id as string, localYmd(row.next_send_at as string));
  }

  return result;
}

// Filters spread.recipients removing any whose scheduled day coincides with a
// pending message (follow-up or active campaign). Returns survivors, count, and names.
function filterSameDayConflicts(
  recipients: SpreadRecipient[],
  pendingDays: Map<string, Set<string>>,
): { survivors: SpreadRecipient[]; sameDayCount: number; sameDayClients: { id: string; name: string }[] } {
  let sameDayCount = 0;
  const sameDayClients: { id: string; name: string }[] = [];
  const survivors = recipients.filter(r => {
    const day = localYmd(r.scheduledFor);
    if (pendingDays.get(r.clientId)?.has(day)) {
      sameDayCount++;
      sameDayClients.push({ id: r.clientId, name: r.name });
      return false;
    }
    return true;
  });
  return { survivors, sameDayCount, sameDayClients };
}

// Per-day usage (sent + scheduled) for an agent, keyed by YYYY-MM-DD APP_TZ.
async function fetchAgentDailyUsage(agentId: string): Promise<Record<string, number>> {
  const today = localYmd(new Date());
  const { data } = await supabase
    .from('daily_send_counters')
    .select('day, sent_count, scheduled_count')
    .eq('agent_id', agentId)
    .gte('day', today);

  const usage: Record<string, number> = {};
  for (const row of (data ?? [])) {
    usage[row.day as string] = (row.sent_count ?? 0) + (row.scheduled_count ?? 0);
  }
  return usage;
}

// ────────────────────────────────────────────────────────────────────────────
// GET /api/campaigns — list with progress
// ────────────────────────────────────────────────────────────────────────────
router.get('/', async (req: Request, res: Response) => {
  const { data, error } = await supabase
    .from('campaigns')
    .select('*, client_labels(name, color)')
    .eq('agent_id', req.agentId!)
    .order('created_at', { ascending: false });

  if (error) { sendDbError(res, error, '[GET /campaigns]'); return; }
  res.json(data ?? []);
});

// ────────────────────────────────────────────────────────────────────────────
// GET /api/campaigns/:id — single, with label info
// ────────────────────────────────────────────────────────────────────────────
router.get('/:id', async (req: Request, res: Response) => {
  const { data, error } = await supabase
    .from('campaigns')
    .select('*, client_labels(name, color)')
    .eq('id', req.params.id)
    .eq('agent_id', req.agentId!)
    .maybeSingle();

  if (error) { sendDbError(res, error, '[GET /campaigns/:id]'); return; }
  if (!data) { res.status(404).json({ error: 'Campanha não encontrada' }); return; }
  res.json(data);
});

// ────────────────────────────────────────────────────────────────────────────
// POST /api/campaigns — create draft
// Body: { name, labelId, templateBody, dailyQuota, startAt }
// ────────────────────────────────────────────────────────────────────────────
router.post('/', async (req: Request, res: Response) => {
  const errors: ValidationError[] = [];
  const ev = (e: ValidationError | null) => { if (e) errors.push(e); };

  ev(validateName(req.body?.name));
  ev(validateTemplateBody(req.body?.templateBody));
  ev(validateDailyQuota(req.body?.dailyQuota));
  ev(validateStartAt(req.body?.startAt));

  if (typeof req.body?.labelId !== 'string') {
    errors.push({ field: 'labelId', code: 'INVALID', message: 'Etiqueta é obrigatória' });
  }
  if (errors.length > 0) {
    res.status(400).json({ error: 'Falha na validação', errors });
    return;
  }

  const label = await fetchLabelOwned(req.agentId!, req.body.labelId);
  if (!label) { res.status(404).json({ error: 'Etiqueta não encontrada' }); return; }

  const { data, error } = await supabase
    .from('campaigns')
    .insert({
      agent_id: req.agentId!,
      label_id: req.body.labelId,
      name: req.body.name.trim(),
      template_body: req.body.templateBody,
      daily_quota: req.body.dailyQuota,
      start_at: req.body.startAt,
      status: 'draft',
    })
    .select()
    .single();

  if (error) { sendDbError(res, error, '[POST /campaigns]'); return; }
  res.status(201).json(data);
});

// ────────────────────────────────────────────────────────────────────────────
// PATCH /api/campaigns/:id — edit a draft (only)
// ────────────────────────────────────────────────────────────────────────────
router.patch('/:id', async (req: Request, res: Response) => {
  const campaign = await fetchCampaign(req.agentId!, req.params.id);
  if (!campaign) { res.status(404).json({ error: 'Campanha não encontrada' }); return; }
  if (campaign.status !== 'draft') {
    res.status(409).json({ error: 'Apenas rascunhos podem ser editados', code: 'NOT_DRAFT' });
    return;
  }

  const updates: Record<string, unknown> = {};
  const errors: ValidationError[] = [];
  const ev = (e: ValidationError | null) => { if (e) errors.push(e); };

  if (req.body?.name !== undefined)         { ev(validateName(req.body.name)); updates.name = req.body.name?.trim(); }
  if (req.body?.templateBody !== undefined) { ev(validateTemplateBody(req.body.templateBody)); updates.template_body = req.body.templateBody; }
  if (req.body?.dailyQuota !== undefined)   { ev(validateDailyQuota(req.body.dailyQuota)); updates.daily_quota = req.body.dailyQuota; }
  if (req.body?.startAt !== undefined)      { ev(validateStartAt(req.body.startAt)); updates.start_at = req.body.startAt; }

  if (req.body?.labelId !== undefined) {
    if (typeof req.body.labelId !== 'string') {
      errors.push({ field: 'labelId', code: 'INVALID', message: 'Etiqueta inválida' });
    } else {
      const label = await fetchLabelOwned(req.agentId!, req.body.labelId);
      if (!label) { errors.push({ field: 'labelId', code: 'NOT_FOUND', message: 'Etiqueta não encontrada' }); }
      else updates.label_id = req.body.labelId;
    }
  }

  if (errors.length > 0) { res.status(400).json({ error: 'Falha na validação', errors }); return; }
  if (Object.keys(updates).length === 0) { res.status(400).json({ error: 'Nenhuma alteração para salvar' }); return; }

  const { data, error } = await supabase
    .from('campaigns')
    .update(updates)
    .eq('id', req.params.id)
    .eq('agent_id', req.agentId!)
    .select()
    .single();

  if (error) { sendDbError(res, error, '[PATCH /campaigns/:id]'); return; }
  res.json(data);
});

// ────────────────────────────────────────────────────────────────────────────
// DELETE /api/campaigns/:id — only drafts and cancelled
// ────────────────────────────────────────────────────────────────────────────
router.delete('/:id', async (req: Request, res: Response) => {
  const campaign = await fetchCampaign(req.agentId!, req.params.id);
  if (!campaign) { res.status(404).json({ error: 'Campanha não encontrada' }); return; }
  if (!['draft', 'cancelled', 'completed'].includes(campaign.status)) {
    res.status(409).json({ error: 'Cancele a campanha primeiro', code: 'ACTIVE' });
    return;
  }
  const { error } = await supabase
    .from('campaigns')
    .delete()
    .eq('id', req.params.id)
    .eq('agent_id', req.agentId!);
  if (error) { sendDbError(res, error, '[DELETE /campaigns/:id]'); return; }
  res.json({ ok: true });
});

// ────────────────────────────────────────────────────────────────────────────
// GET /api/campaigns/:id/preview — dry-run plan, no commits
// ────────────────────────────────────────────────────────────────────────────
router.get('/:id/preview', async (req: Request, res: Response) => {
  const campaign = await fetchCampaign(req.agentId!, req.params.id);
  if (!campaign) { res.status(404).json({ error: 'Campanha não encontrada' }); return; }

  const { matched, eligible, skipped } = await resolveEligibleClients(req.agentId!, campaign.label_id);
  const usage = await fetchAgentDailyUsage(req.agentId!);

  const startAt = new Date(campaign.start_at);
  const startMs = Math.max(startAt.getTime(), Date.now());
  const effectiveStart = new Date(startMs);

  const spread = spreadCampaign(
    eligible.map<ClientLite>(c => ({ id: c.id, name: c.name })),
    {
      dailyQuota: campaign.daily_quota,
      startAt: effectiveStart,
      existingUsage: usage,
    },
  );

  // Same-day conflict filter — covers pending follow-ups AND pending recipients
  // of other active campaigns belonging to the same agent.
  const pendingDays = await fetchAgentPendingDays(req.agentId!, spread.recipients.map(r => r.clientId));
  const { survivors, sameDayCount, sameDayClients } = filterSameDayConflicts(spread.recipients, pendingDays);

  // Re-derive batchPlan from survivors so per-day counts and recipientPreview
  // reflect the actual sends, not the pre-filter spread.
  const filteredBatchPlan = deriveBatchPlan(survivors);

  const sampleClient = eligible[0];
  const sampleMessage = sampleClient
    ? formatMessage(campaign.template_body, sampleClient as any, [])
    : campaign.template_body;

  res.json({
    matchedClients: matched,
    eligibleClients: survivors.length,
    skipped: { ...skipped, sameDayFollowUp: sameDayCount, sameDayFollowUpClients: sameDayClients, total: skipped.total + sameDayCount },
    estimatedDays: filteredBatchPlan.length,
    unscheduledCount: spread.unscheduledCount,
    sampleMessage,
    batchPlan: filteredBatchPlan,
  });
});

// ────────────────────────────────────────────────────────────────────────────
// POST /api/campaigns/:id/launch — locks the campaign and enqueues recipients
// ────────────────────────────────────────────────────────────────────────────
// Helper: clears launch_lock_at on the campaign, swallowing errors. Used on
// every exit path of the launch route except the success path (where the
// status flip to 'running' implicitly invalidates the lock anyway).
async function releaseLaunchLock(campaignId: string) {
  const { error } = await supabase
    .from('campaigns')
    .update({ launch_lock_at: null })
    .eq('id', campaignId);
  if (error) console.error('[releaseLaunchLock]', error);
}

router.post('/:id/launch', async (req: Request, res: Response) => {
  const campaign = await fetchCampaign(req.agentId!, req.params.id);
  if (!campaign) { res.status(404).json({ error: 'Campanha não encontrada' }); return; }
  if (campaign.status !== 'draft') {
    res.status(409).json({ error: 'Apenas rascunhos podem ser lançados', code: 'NOT_DRAFT' });
    return;
  }

  // ─── Acquire launch lock ───────────────────────────────────────────────────
  // Conditional UPDATE: only succeeds if the campaign is still a draft AND
  // either unlocked or the lock is older than 5 minutes (stale-lock recovery
  // in case a previous launch crashed before releasing). Returning rows lets us
  // detect lost races — if zero rows came back, another launch beat us to it.
  const STALE_LOCK_CUTOFF = new Date(Date.now() - 5 * 60_000).toISOString();
  const { data: lockRows, error: lockErr } = await supabase
    .from('campaigns')
    .update({ launch_lock_at: new Date().toISOString() })
    .eq('id', campaign.id)
    .eq('agent_id', req.agentId!)
    .eq('status', 'draft')
    .or(`launch_lock_at.is.null,launch_lock_at.lt.${STALE_LOCK_CUTOFF}`)
    .select('id');
  if (lockErr) { sendDbError(res, lockErr, '[POST /campaigns/:id/launch] acquire lock'); return; }
  if (!lockRows || lockRows.length === 0) {
    res.status(409).json({
      error: 'Esta campanha já está sendo lançada. Aguarde alguns segundos e tente novamente.',
      code: 'LAUNCH_IN_PROGRESS',
    });
    return;
  }

  // Re-validate template/quota at launch — agent could have edited the row
  // through PATCH and the earlier checks live there.
  const tplErr = validateTemplateBody(campaign.template_body);
  if (tplErr) { await releaseLaunchLock(campaign.id); bail(res, tplErr); return; }
  const qErr = validateDailyQuota(campaign.daily_quota);
  if (qErr) { await releaseLaunchLock(campaign.id); bail(res, qErr); return; }

  const { eligible } = await resolveEligibleClients(req.agentId!, campaign.label_id);
  if (eligible.length === 0) {
    await releaseLaunchLock(campaign.id);
    res.status(409).json({ error: 'Nenhum destinatário elegível para esta etiqueta', code: 'NO_RECIPIENTS' });
    return;
  }

  const usage = await fetchAgentDailyUsage(req.agentId!);
  const startAt = new Date(campaign.start_at);
  const effectiveStart = new Date(Math.max(startAt.getTime(), Date.now()));

  const spread = spreadCampaign(
    eligible.map<ClientLite>(c => ({ id: c.id, name: c.name })),
    {
      dailyQuota: campaign.daily_quota,
      startAt: effectiveStart,
      existingUsage: usage,
    },
  );

  if (spread.recipients.length === 0) {
    await releaseLaunchLock(campaign.id);
    res.status(409).json({
      error: 'Nenhum horário disponível — limites diários impedem o agendamento',
      code: 'NO_SLOTS',
    });
    return;
  }

  // Same-day conflict filter — covers pending follow-ups AND pending recipients
  // of other active campaigns belonging to the same agent.
  const pendingDays = await fetchAgentPendingDays(req.agentId!, spread.recipients.map(r => r.clientId));
  const { survivors: filteredRecipients } = filterSameDayConflicts(spread.recipients, pendingDays);

  if (filteredRecipients.length === 0) {
    await releaseLaunchLock(campaign.id);
    res.status(409).json({
      error: 'Todos os destinatários já têm uma mensagem pendente no dia agendado — sem horários disponíveis',
      code: 'NO_SLOTS',
    });
    return;
  }

  // Re-derive batchPlan from survivors so the response matches what was inserted.
  const filteredBatchPlan = deriveBatchPlan(filteredRecipients);

  // Insert recipients — chunked to keep payload size sane on big campaigns.
  // The `(campaign_id, client_id)` unique index (migration 2026-05-03) blocks
  // duplicate rows from a concurrent launch that managed to race past the lock.
  const rows = filteredRecipients.map(r => ({
    campaign_id: campaign.id,
    client_id: r.clientId,
    scheduled_for: r.scheduledFor.toISOString(),
    status: 'pending',
  }));
  const CHUNK = 500;
  for (let i = 0; i < rows.length; i += CHUNK) {
    const { error } = await supabase
      .from('campaign_recipients')
      .insert(rows.slice(i, i + CHUNK));
    if (error) {
      // Best-effort rollback: delete any rows we already inserted.
      await supabase.from('campaign_recipients').delete().eq('campaign_id', campaign.id);
      await releaseLaunchLock(campaign.id);
      console.error('[POST /campaigns/:id/launch] insert recipients', error);
      res.status(500).json({ error: 'Falha ao criar destinatários da campanha. Tente novamente.' });
      return;
    }
  }

  // Per-day scheduled_count delta — keeps the agent quota planner accurate.
  // Only count survivors (same-day conflicts were never inserted).
  const dayDelta: Record<string, number> = {};
  for (const r of filteredRecipients) {
    const day = localYmd(r.scheduledFor);
    dayDelta[day] = (dayDelta[day] ?? 0) + 1;
  }
  await applyScheduledDelta(req.agentId!, dayDelta);

  // Flip campaign to running with frozen totals. Clear the lock here too —
  // status='running' would already block another launch via the WHERE clause,
  // but null-ing it keeps the column clean for the next draft cycle (cancel→clone).
  const { data: updated, error: upErr } = await supabase
    .from('campaigns')
    .update({
      status: 'running',
      total_recipients: filteredRecipients.length,
      launch_lock_at: null,
    })
    .eq('id', campaign.id)
    .select()
    .single();
  if (upErr) {
    await releaseLaunchLock(campaign.id);
    sendDbError(res, upErr, '[POST /campaigns/:id/launch] flip running');
    return;
  }

  nudgeScheduler();
  res.json({
    campaign: updated,
    enqueued: filteredRecipients.length,
    estimatedDays: filteredBatchPlan.length,
    batchPlan: filteredBatchPlan,
  });
});

// ────────────────────────────────────────────────────────────────────────────
// POST /api/campaigns/:id/pause / /resume / /cancel
// ────────────────────────────────────────────────────────────────────────────
router.post('/:id/pause', async (req: Request, res: Response) => {
  const campaign = await fetchCampaign(req.agentId!, req.params.id);
  if (!campaign) { res.status(404).json({ error: 'Campanha não encontrada' }); return; }
  if (campaign.status !== 'running') {
    res.status(409).json({ error: 'Apenas campanhas em execução podem ser pausadas', code: 'NOT_RUNNING' });
    return;
  }
  const { data, error } = await supabase
    .from('campaigns')
    .update({ status: 'paused' })
    .eq('id', campaign.id)
    .select()
    .single();
  if (error) { sendDbError(res, error, '[POST /campaigns/:id/pause]'); return; }
  res.json(data);
});

router.post('/:id/resume', async (req: Request, res: Response) => {
  const campaign = await fetchCampaign(req.agentId!, req.params.id);
  if (!campaign) { res.status(404).json({ error: 'Campanha não encontrada' }); return; }
  if (campaign.status !== 'paused') {
    res.status(409).json({ error: 'Apenas campanhas pausadas podem ser retomadas', code: 'NOT_PAUSED' });
    return;
  }
  const { data, error } = await supabase
    .from('campaigns')
    .update({ status: 'running' })
    .eq('id', campaign.id)
    .select()
    .single();
  if (error) { sendDbError(res, error, '[POST /campaigns/:id/resume]'); return; }
  nudgeScheduler();
  res.json(data);
});

router.post('/:id/cancel', async (req: Request, res: Response) => {
  const campaign = await fetchCampaign(req.agentId!, req.params.id);
  if (!campaign) { res.status(404).json({ error: 'Campanha não encontrada' }); return; }
  if (!['draft', 'running', 'paused'].includes(campaign.status)) {
    res.status(409).json({ error: 'A campanha não pode ser cancelada no estado atual', code: 'TERMINAL' });
    return;
  }

  // Mark all pending recipients as skipped and release their scheduled-count delta.
  const { data: pending } = await supabase
    .from('campaign_recipients')
    .select('id, scheduled_for')
    .eq('campaign_id', campaign.id)
    .eq('status', 'pending');

  if (pending && pending.length > 0) {
    const ids = pending.map((r: any) => r.id);
    await supabase
      .from('campaign_recipients')
      .update({ status: 'skipped', error_detail: 'Campanha cancelada' })
      .in('id', ids);

    const delta: Record<string, number> = {};
    for (const r of pending) {
      const day = localYmd(r.scheduled_for as string);
      delta[day] = (delta[day] ?? 0) - 1;
    }
    await applyScheduledDelta(req.agentId!, delta);
  }

  const { data, error } = await supabase
    .from('campaigns')
    .update({
      status: 'cancelled',
      skipped_count: (campaign.skipped_count ?? 0) + (pending?.length ?? 0),
      completed_at: new Date().toISOString(),
    })
    .eq('id', campaign.id)
    .select()
    .single();
  if (error) { sendDbError(res, error, '[POST /campaigns/:id/cancel]'); return; }
  res.json(data);
});

// ────────────────────────────────────────────────────────────────────────────
// GET /api/campaigns/:id/schedule — live batch plan from actual recipients
// ────────────────────────────────────────────────────────────────────────────
router.get('/:id/schedule', async (req: Request, res: Response) => {
  const campaign = await fetchCampaign(req.agentId!, req.params.id);
  if (!campaign) { res.status(404).json({ error: 'Campanha não encontrada' }); return; }

  const { data: recipients, error } = await supabase
    .from('campaign_recipients')
    .select('id, client_id, scheduled_for, status, sent_at, error_detail, clients(name)')
    .eq('campaign_id', campaign.id)
    .order('scheduled_for');

  if (error) { sendDbError(res, error, '[GET /campaigns/:id/schedule]'); return; }

  const byDay = new Map<string, any[]>();
  for (const r of (recipients ?? [])) {
    const day = localYmd(r.scheduled_for as string);
    if (!byDay.has(day)) byDay.set(day, []);
    byDay.get(day)!.push(r);
  }

  const plan = Array.from(byDay.entries()).map(([date, items]) => {
    items.sort((a, b) => new Date(a.scheduled_for).getTime() - new Date(b.scheduled_for).getTime());
    const pending = items.filter(i => i.status === 'pending');
    return {
      date,
      count: items.length,
      pendingCount: pending.length,
      sentCount:    items.filter(i => i.status === 'sent').length,
      failedCount:  items.filter(i => i.status === 'failed').length,
      skippedCount: items.filter(i => i.status === 'skipped').length,
      firstSendAt: items[0].scheduled_for,
      lastSendAt:  items[items.length - 1].scheduled_for,
      recipientPreview: items.slice(0, 5).map((i: any) => ({
        id: i.client_id,
        name: i.clients?.name ?? '(unknown)',
        status: i.status,
        scheduledFor: i.scheduled_for,
      })),
    };
  });

  res.json({
    campaign: {
      id: campaign.id,
      name: campaign.name,
      status: campaign.status,
      total_recipients: campaign.total_recipients,
      sent_count: campaign.sent_count,
      failed_count: campaign.failed_count,
      skipped_count: campaign.skipped_count,
    },
    batchPlan: plan,
  });
});

export default router;
