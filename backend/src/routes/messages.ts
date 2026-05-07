import { Router, Request, Response } from 'express';
import { supabase } from '../services/supabase';
import { requireAuth } from '../middleware/auth';
import { nudgeScheduler } from '../services/scheduler';
import {
  isWithinSendWindow,
  localYmd,
  DAILY_LIMIT,
  MIN_GAP_HOURS_SAME_CLIENT,
} from '../services/rateLimits';
import { applyScheduledDelta } from '../services/counters';

const router = Router();
router.use(requireAuth);

// GET /api/clients/:clientId/messages
router.get('/clients/:clientId/messages', async (req: Request, res: Response) => {
  // Verify client belongs to this agent
  const { data: client } = await supabase
    .from('clients')
    .select('id')
    .eq('id', req.params.clientId)
    .eq('agent_id', req.agentId!)
    .maybeSingle();

  if (!client) { res.status(404).json({ error: 'Client not found' }); return; }

  const { data, error } = await supabase
    .from('follow_up_messages')
    .select('*')
    .eq('client_id', req.params.clientId)
    .order('seq');

  if (error) { res.status(500).json({ error: error.message }); return; }
  res.json(data);
});

// PUT /api/clients/:clientId/messages — upsert all 5 messages at once
// mirrors Python upsert_followup_messages()
router.put('/clients/:clientId/messages', async (req: Request, res: Response) => {
  const { messages } = req.body as {
    messages: Array<{ seq: number; body: string; send_at: string }>
  };

  if (!Array.isArray(messages) || messages.length === 0) {
    res.status(400).json({ error: 'messages array is required' });
    return;
  }

  // Validate each message has a non-empty body
  for (const m of messages) {
    if (!m.body || typeof m.body !== 'string' || m.body.trim() === '') {
      res.status(400).json({ error: `Message ${m.seq} has an empty body` });
      return;
    }
    if (!m.send_at || !m.seq) {
      res.status(400).json({ error: 'Each message must have seq and send_at' });
      return;
    }
  }

  // Verify ownership
  const { data: client } = await supabase
    .from('clients')
    .select('id')
    .eq('id', req.params.clientId)
    .eq('agent_id', req.agentId!)
    .maybeSingle();

  if (!client) { res.status(404).json({ error: 'Client not found' }); return; }

  // ── Anti-ban validation: send window (8–20h in APP_TZ) ────────────────────
  for (const m of messages) {
    if (!isWithinSendWindow(m.send_at)) {
      res.status(422).json({
        code: 'OUTSIDE_SEND_WINDOW',
        seq: m.seq,
        error: `Message ${m.seq} is outside the 08:00–20:00 send window`,
      });
      return;
    }
  }

  // Fetch existing messages to preserve status AND support gap/cap validation
  const { data: existing } = await supabase
    .from('follow_up_messages')
    .select('seq, send_at, status')
    .eq('client_id', req.params.clientId);

  const existingStatus: Record<number, string> = {};
  for (const m of (existing ?? [])) {
    existingStatus[m.seq] = m.status;
  }

  // ── Anti-ban validation: 48h gap between messages to the SAME client ──────
  // Final set = kept existing (not being replaced, not cancelled) + incoming
  const incomingSeqs = new Set(messages.map(m => m.seq));
  const keptExisting = (existing ?? []).filter(
    e => !incomingSeqs.has(e.seq) && e.status !== 'cancelled'
  );
  const finalSet = [
    ...keptExisting.map(e => ({ seq: e.seq, send_at: e.send_at as string })),
    ...messages.map(m => ({ seq: m.seq, send_at: m.send_at })),
  ];
  const minGapMs = MIN_GAP_HOURS_SAME_CLIENT * 3_600_000;
  for (let i = 0; i < finalSet.length; i++) {
    for (let j = i + 1; j < finalSet.length; j++) {
      const diff = Math.abs(
        new Date(finalSet[i].send_at).getTime() - new Date(finalSet[j].send_at).getTime()
      );
      if (diff < minGapMs) {
        const offending = incomingSeqs.has(finalSet[j].seq) ? finalSet[j].seq : finalSet[i].seq;
        res.status(422).json({
          code: 'MIN_GAP_VIOLATION',
          seq: offending,
          error: `Messages to the same client must be at least ${MIN_GAP_HOURS_SAME_CLIENT}h apart`,
        });
        return;
      }
    }
  }

  // ── Anti-ban validation: DAILY_LIMIT sends / agent / day (APP_TZ) ─────────
  // Delta per day = (+1 for each incoming) - (1 for each replaced pending/sent)
  const dayDelta: Record<string, number> = {};
  for (const m of messages) {
    const d = localYmd(m.send_at);
    dayDelta[d] = (dayDelta[d] ?? 0) + 1;
  }
  for (const e of (existing ?? [])) {
    if (incomingSeqs.has(e.seq) && (e.status === 'pending' || e.status === 'sent')) {
      const d = localYmd(e.send_at as string);
      dayDelta[d] = (dayDelta[d] ?? 0) - 1;
    }
  }
  const addDays = Object.keys(dayDelta).filter(d => dayDelta[d] > 0);
  if (addDays.length > 0) {
    const { data: counters } = await supabase
      .from('daily_send_counters')
      .select('day, sent_count, scheduled_count')
      .eq('agent_id', req.agentId!)
      .in('day', addDays);
    const byDay: Record<string, { sent_count: number; scheduled_count: number }> = {};
    for (const c of (counters ?? [])) byDay[c.day as string] = c as any;
    for (const day of addDays) {
      const c = byDay[day] ?? { sent_count: 0, scheduled_count: 0 };
      const projected = c.sent_count + c.scheduled_count + dayDelta[day];
      if (projected > DAILY_LIMIT) {
        res.status(422).json({
          code: 'DAILY_LIMIT_EXCEEDED',
          day,
          current: c.sent_count + c.scheduled_count,
          limit: DAILY_LIMIT,
          error: `Daily limit of ${DAILY_LIMIT} messages/agent would be exceeded on ${day}`,
        });
        return;
      }
    }
  }

  const rows = messages.map(m => {
    const currentStatus = existingStatus[m.seq];
    // If already sent or cancelled, preserve that status
    // Only set pending if it's a new message or was previously pending/failed
    const status = (currentStatus === 'sent' || currentStatus === 'cancelled')
      ? currentStatus
      : 'pending';

    return {
      client_id: req.params.clientId,
      seq: m.seq,
      body: m.body,
      send_at: m.send_at,
      status,
    };
  });

  const { data, error } = await supabase
    .from('follow_up_messages')
    .upsert(rows, { onConflict: 'client_id,seq' })
    .select();

  if (error) { res.status(500).json({ error: error.message }); return; }

  // Delete any pending messages that are not in the incoming payload
  const pendingDeleteRows = (existing ?? [])
    .filter(m => !incomingSeqs.has(m.seq) && m.status === 'pending');
  const toDelete = pendingDeleteRows.map(m => m.seq);

  if (toDelete.length > 0) {
    await supabase
      .from('follow_up_messages')
      .delete()
      .eq('client_id', req.params.clientId)
      .in('seq', toDelete);
    // Release their scheduled_count slots
    for (const d of pendingDeleteRows) {
      const day = localYmd(d.send_at as string);
      dayDelta[day] = (dayDelta[day] ?? 0) - 1;
    }
  }

  // Persist the day-level deltas in daily_send_counters
  await applyScheduledDelta(req.agentId!, dayDelta);

  nudgeScheduler();
  res.json(data);
});

// DELETE /api/clients/:clientId/messages — reset all messages for a new cycle
router.delete('/clients/:clientId/messages', async (req: Request, res: Response) => {
  const { data: client } = await supabase
    .from('clients')
    .select('id')
    .eq('id', req.params.clientId)
    .eq('agent_id', req.agentId!)
    .maybeSingle();

  if (!client) { res.status(404).json({ error: 'Client not found' }); return; }

  // Collect pending messages so we can release their scheduled_count slots
  const { data: pendingForRelease } = await supabase
    .from('follow_up_messages')
    .select('send_at, status')
    .eq('client_id', req.params.clientId)
    .eq('status', 'pending');

  // Remove send_log entries first (FK constraint)
  const { data: msgs } = await supabase
    .from('follow_up_messages')
    .select('id')
    .eq('client_id', req.params.clientId);

  const msgIds = (msgs ?? []).map((m: any) => m.id);
  if (msgIds.length > 0) {
    const { error: slErr } = await supabase.from('send_log').delete().in('message_id', msgIds);
    if (slErr) { console.error('[DELETE messages] send_log delete failed', slErr); res.status(500).json({ error: 'Failed to reset messages' }); return; }
  }

  const { error: fupErr } = await supabase
    .from('follow_up_messages')
    .delete()
    .eq('client_id', req.params.clientId);
  if (fupErr) { console.error('[DELETE messages] follow_up_messages delete failed', fupErr); res.status(500).json({ error: 'Failed to reset messages' }); return; }

  if (pendingForRelease && pendingForRelease.length > 0) {
    const dayDelta: Record<string, number> = {};
    for (const m of pendingForRelease) {
      const d = localYmd(m.send_at as string);
      dayDelta[d] = (dayDelta[d] ?? 0) - 1;
    }
    await applyScheduledDelta(req.agentId!, dayDelta);
  }

  // Ensure client is active so scheduler can pick up new messages
  const { error: activateErr } = await supabase
    .from('clients')
    .update({ is_active: true, replied_at: null, opted_out_at: null, opt_out_reason: null })
    .eq('id', req.params.clientId);
  if (activateErr) { console.error('[DELETE messages] client reactivation failed', activateErr); }

  res.json({ ok: true });
});

export default router;
