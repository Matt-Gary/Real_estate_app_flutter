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

// Validate a proposed cold-client send_at against anti-ban rules.
// Returns null if OK, or an error object with status code and body.
async function validateColdSendAt(
  agentId: string,
  clientId: string,
  sendAtIso: string,
): Promise<{ status: number; body: Record<string, any> } | null> {
  // 1. Send window
  if (!isWithinSendWindow(sendAtIso)) {
    return {
      status: 422,
      body: {
        code: 'OUTSIDE_SEND_WINDOW',
        error: 'First send is outside the 08:00–20:00 send window',
      },
    };
  }

  // 2. 48h gap vs the same client's pending/sent follow-up messages
  const { data: clientMsgs } = await supabase
    .from('follow_up_messages')
    .select('send_at, status')
    .eq('client_id', clientId)
    .in('status', ['pending', 'sent']);

  const minGapMs = MIN_GAP_HOURS_SAME_CLIENT * 3_600_000;
  const target = new Date(sendAtIso).getTime();
  for (const m of (clientMsgs ?? [])) {
    const diff = Math.abs(new Date(m.send_at as string).getTime() - target);
    if (diff < minGapMs) {
      return {
        status: 422,
        body: {
          code: 'MIN_GAP_VIOLATION',
          error: `Cold send must be at least ${MIN_GAP_HOURS_SAME_CLIENT}h from any other message to this client`,
        },
      };
    }
  }

  // 3. Daily cap on the first-send day
  const day = localYmd(sendAtIso);
  const { data: counter } = await supabase
    .from('daily_send_counters')
    .select('sent_count, scheduled_count')
    .eq('agent_id', agentId)
    .eq('day', day)
    .maybeSingle();
  const cur = counter ?? { sent_count: 0, scheduled_count: 0 };
  if (cur.sent_count + cur.scheduled_count + 1 > DAILY_LIMIT) {
    return {
      status: 422,
      body: {
        code: 'DAILY_LIMIT_EXCEEDED',
        day,
        current: cur.sent_count + cur.scheduled_count,
        limit: DAILY_LIMIT,
        error: `Daily limit of ${DAILY_LIMIT} messages/agent would be exceeded on ${day}`,
      },
    };
  }

  return null;
}

// GET /api/cold-clients — list agent's cold clients with client and template info
router.get('/', async (req: Request, res: Response) => {
  const { data, error } = await supabase
    .from('cold_clients')
    .select(`
      *,
      clients!inner(name, phone_number),
      agent_templates(name)
    `)
    .eq('agent_id', req.agentId!)
    .order('created_at', { ascending: false });

  if (error) { res.status(500).json({ error: error.message }); return; }

  // Pull labels for the underlying clients in one round-trip and merge.
  const clientIds = (data ?? []).map((r: any) => r.client_id);
  const labelsByClient: Record<string, any[]> = {};
  if (clientIds.length > 0) {
    const { data: assignments } = await supabase
      .from('client_label_assignments')
      .select('client_id, client_labels(id, name, color)')
      .in('client_id', clientIds);
    for (const a of (assignments ?? [])) {
      const cid = a.client_id as string;
      const label = (a as any).client_labels;
      if (!label) continue;
      (labelsByClient[cid] ??= []).push(label);
    }
  }

  const result = (data ?? []).map((row: any) => ({
    id:            row.id,
    client_id:     row.client_id,
    client_name:   row.clients?.name ?? '',
    phone_number:  row.clients?.phone_number ?? '',
    template_id:   row.template_id,
    template_name: row.agent_templates?.name ?? null,
    interval_days: row.interval_days,
    messages_sent: row.messages_sent,
    max_messages:  row.max_messages,
    is_active:     row.is_active,
    next_send_at:  row.next_send_at,
    created_at:    row.created_at,
    labels:        labelsByClient[row.client_id] ?? [],
  }));

  res.json(result);
});

// POST /api/cold-clients — enroll a client in the cold campaign
router.post('/', async (req: Request, res: Response) => {
  const { client_id, template_id, interval_days, max_messages, first_send_at } = req.body;

  if (!client_id) {
    res.status(400).json({ error: 'client_id is required' }); return;
  }

  // Verify the client belongs to this agent
  const { data: client } = await supabase
    .from('clients')
    .select('id')
    .eq('id', client_id)
    .eq('agent_id', req.agentId!)
    .maybeSingle();

  if (!client) { res.status(404).json({ error: 'Client not found' }); return; }

  // Prevent duplicate active cold client entries
  const { data: existing } = await supabase
    .from('cold_clients')
    .select('id')
    .eq('client_id', client_id)
    .eq('agent_id', req.agentId!)
    .eq('is_active', true)
    .maybeSingle();

  if (existing) {
    res.status(409).json({ error: 'Client is already in an active cold campaign' }); return;
  }

  const sendAt = first_send_at ?? new Date().toISOString();
  const problem = await validateColdSendAt(req.agentId!, client_id, sendAt);
  if (problem) { res.status(problem.status).json(problem.body); return; }

  const { data, error } = await supabase
    .from('cold_clients')
    .insert({
      client_id,
      agent_id:      req.agentId!,
      template_id:   template_id   ?? null,
      interval_days: interval_days ?? 14,
      max_messages:  max_messages  ?? null,
      messages_sent: 0,
      is_active:     true,
      next_send_at:  sendAt,
    })
    .select()
    .single();

  if (error) { res.status(500).json({ error: error.message }); return; }

  // Reserve the first-send slot in the day counter
  await applyScheduledDelta(req.agentId!, { [localYmd(sendAt)]: 1 });

  res.status(201).json(data);
  nudgeScheduler();
});

// PATCH /api/cold-clients/:id — update settings or toggle active
router.patch('/:id', async (req: Request, res: Response) => {
  const allowed = ['template_id', 'interval_days', 'max_messages', 'is_active', 'next_send_at'];
  const updates: Record<string, any> = {};
  for (const key of allowed) {
    if (key in req.body) updates[key] = req.body[key];
  }

  if (Object.keys(updates).length === 0) {
    res.status(400).json({ error: 'Nothing to update' }); return;
  }

  // Fetch current row to validate transitions and compute counter deltas
  const { data: current } = await supabase
    .from('cold_clients')
    .select('client_id, next_send_at, is_active')
    .eq('id', req.params.id)
    .eq('agent_id', req.agentId!)
    .maybeSingle();
  if (!current) { res.status(404).json({ error: 'Cold client not found' }); return; }

  // If next_send_at or is_active is changing, re-validate the new send time
  const willBeActive = 'is_active' in updates ? !!updates.is_active : current.is_active;
  const newSendAt = updates.next_send_at ?? current.next_send_at;
  if (willBeActive && newSendAt && newSendAt !== current.next_send_at) {
    const problem = await validateColdSendAt(req.agentId!, current.client_id as string, newSendAt);
    if (problem) { res.status(problem.status).json(problem.body); return; }
  }

  const { data, error } = await supabase
    .from('cold_clients')
    .update(updates)
    .eq('id', req.params.id)
    .eq('agent_id', req.agentId!)
    .select()
    .single();

  if (error || !data) { res.status(404).json({ error: 'Cold client not found' }); return; }

  // Counter delta: release old day if we moved away or went inactive; reserve new day if now active
  const dayDelta: Record<string, number> = {};
  if (current.is_active && current.next_send_at) {
    dayDelta[localYmd(current.next_send_at as string)] =
      (dayDelta[localYmd(current.next_send_at as string)] ?? 0) - 1;
  }
  if (willBeActive && newSendAt) {
    dayDelta[localYmd(newSendAt as string)] =
      (dayDelta[localYmd(newSendAt as string)] ?? 0) + 1;
  }
  if (Object.keys(dayDelta).length > 0) {
    await applyScheduledDelta(req.agentId!, dayDelta);
  }

  if ('is_active' in updates && updates.is_active === true) nudgeScheduler();
  res.json(data);
});

// DELETE /api/cold-clients/:id
router.delete('/:id', async (req: Request, res: Response) => {
  // Fetch to know whether to release a counter slot
  const { data: current } = await supabase
    .from('cold_clients')
    .select('next_send_at, is_active')
    .eq('id', req.params.id)
    .eq('agent_id', req.agentId!)
    .maybeSingle();

  const { error } = await supabase
    .from('cold_clients')
    .delete()
    .eq('id', req.params.id)
    .eq('agent_id', req.agentId!);

  if (error) { res.status(500).json({ error: error.message }); return; }

  if (current?.is_active && current.next_send_at) {
    await applyScheduledDelta(req.agentId!, {
      [localYmd(current.next_send_at as string)]: -1,
    });
  }

  res.json({ ok: true });
});

export default router;
