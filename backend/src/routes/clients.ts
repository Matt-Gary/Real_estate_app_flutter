import { Router, Request, Response } from 'express';
import { supabase } from '../services/supabase';
import { requireAuth } from '../middleware/auth';
import { nudgeScheduler } from '../services/scheduler';

const router = Router();
router.use(requireAuth);

// GET /api/clients — all clients for the logged-in agent with message counts
router.get('/', async (req: Request, res: Response) => {
  const { data: clients, error: clientsError } = await supabase
    .from('clients')
    .select('*')
    .eq('agent_id', req.agentId!)
    .order('created_at', { ascending: false });

  if (clientsError) { res.status(500).json({ error: clientsError.message }); return; }

  // Fetch counts for all clients in one go
  const clientIds = (clients ?? []).map(c => c.id);
  const { data: counts, error: countsError } = await supabase
    .from('follow_up_messages')
    .select('client_id, status')
    .in('client_id', clientIds);

  if (countsError) { res.status(500).json({ error: countsError.message }); return; }

  // Merge counts into client objects
  const clientsWithCounts = (clients ?? []).map(client => {
    const clientMessages = (counts ?? []).filter(m => m.client_id === client.id);
    return {
      ...client,
      total_count: clientMessages.length,
      sent_count: clientMessages.filter(m => m.status === 'sent').length,
    };
  });

  res.json(clientsWithCounts);
});

// GET /api/clients/:id
router.get('/:id', async (req: Request, res: Response) => {
  const { data, error } = await supabase
    .from('clients')
    .select('*')
    .eq('id', req.params.id)
    .eq('agent_id', req.agentId!)
    .single();

  if (error || !data) { res.status(404).json({ error: 'Client not found' }); return; }
  res.json(data);
});

// POST /api/clients
router.post('/', async (req: Request, res: Response) => {
  const { name, phone_number, email, property_link_id, notes } = req.body;

  if (!name || !phone_number) {
    res.status(400).json({ error: 'name and phone_number are required' });
    return;
  }

  const { data, error } = await supabase
    .from('clients')
    .insert({
      agent_id: req.agentId!,
      name,
      phone_number,
      email:            email            ?? null,
      property_link_id: property_link_id ?? null,
      notes:            notes            ?? null,
    })
    .select()
    .single();

  if (error) { res.status(500).json({ error: error.message }); return; }
  res.status(201).json(data);
  nudgeScheduler();
});

// PATCH /api/clients/:id
router.patch('/:id', async (req: Request, res: Response) => {
  const allowed = ['name', 'phone_number', 'email', 'property_link_id', 'notes'];
  const updates: Record<string, any> = {};
  for (const key of allowed) {
    if (key in req.body) updates[key] = req.body[key];
  }

  const { data, error } = await supabase
    .from('clients')
    .update(updates)
    .eq('id', req.params.id)
    .eq('agent_id', req.agentId!)
    .select()
    .single();

  if (error || !data) { res.status(404).json({ error: 'Client not found' }); return; }
  res.json(data);
});

// PATCH /api/clients/:id/replied — mirrors Python mark_client_replied()
router.patch('/:id/replied', async (req: Request, res: Response) => {
  const clientId = req.params.id;

  // Verify ownership
  const { data: client } = await supabase
    .from('clients')
    .select('id')
    .eq('id', clientId)
    .eq('agent_id', req.agentId!)
    .maybeSingle();

  if (!client) { res.status(404).json({ error: 'Client not found' }); return; }

  await supabase
    .from('clients')
    .update({ is_active: false, replied_at: new Date().toISOString() })
    .eq('id', clientId);

  await supabase
    .from('follow_up_messages')
    .update({ status: 'cancelled' })
    .eq('client_id', clientId)
    .eq('status', 'pending');

  res.json({ ok: true });
});

// DELETE /api/clients/:id — mirrors Python delete_client_record()
router.delete('/:id', async (req: Request, res: Response) => {
  const clientId = req.params.id;

  // Verify ownership
  const { data: client } = await supabase
    .from('clients')
    .select('id')
    .eq('id', clientId)
    .eq('agent_id', req.agentId!)
    .maybeSingle();

  if (!client) { res.status(404).json({ error: 'Client not found' }); return; }

  // Delete in reverse FK order: send_log -> follow_up_messages -> cold_clients -> clients
  const { data: msgs } = await supabase
    .from('follow_up_messages')
    .select('id')
    .eq('client_id', clientId);

  const msgIds = (msgs ?? []).map((m: any) => m.id);
  if (msgIds.length > 0) {
    await supabase.from('send_log').delete().in('message_id', msgIds);
  }
  await supabase.from('follow_up_messages').delete().eq('client_id', clientId);
  await supabase.from('cold_clients').delete().eq('client_id', clientId);
  await supabase.from('clients').delete().eq('id', clientId);

  res.json({ ok: true });
});

export default router;
