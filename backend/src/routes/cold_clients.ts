import { Router, Request, Response } from 'express';
import { supabase } from '../services/supabase';
import { requireAuth } from '../middleware/auth';
import { nudgeScheduler } from '../services/scheduler';

const router = Router();
router.use(requireAuth);

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
      next_send_at:  first_send_at ?? new Date().toISOString(),
    })
    .select()
    .single();

  if (error) { res.status(500).json({ error: error.message }); return; }
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

  const { data, error } = await supabase
    .from('cold_clients')
    .update(updates)
    .eq('id', req.params.id)
    .eq('agent_id', req.agentId!)
    .select()
    .single();

  if (error || !data) { res.status(404).json({ error: 'Cold client not found' }); return; }

  if ('is_active' in updates && updates.is_active === true) nudgeScheduler();
  res.json(data);
});

// DELETE /api/cold-clients/:id
router.delete('/:id', async (req: Request, res: Response) => {
  const { error } = await supabase
    .from('cold_clients')
    .delete()
    .eq('id', req.params.id)
    .eq('agent_id', req.agentId!);

  if (error) { res.status(500).json({ error: error.message }); return; }
  res.json({ ok: true });
});

export default router;
