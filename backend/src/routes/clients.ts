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
    .select('*, client_property_links(position, property_link_id, property_links(id, link, description))')
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
    .select('*, client_property_links(position, property_link_id, property_links(id, link, description))')
    .eq('id', req.params.id)
    .eq('agent_id', req.agentId!)
    .single();

  if (error || !data) { res.status(404).json({ error: 'Client not found' }); return; }
  res.json(data);
});

// POST /api/clients
router.post('/', async (req: Request, res: Response) => {
  const { name, phone_number, email, property_links, notes } = req.body;

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
      email: email ?? null,
      notes: notes ?? null,
    })
    .select()
    .single();

  if (error) { res.status(500).json({ error: error.message }); return; }

  if (Array.isArray(property_links) && property_links.length > 0) {
    const linkRows = property_links.map((pl: any) => ({
      client_id:        data.id,
      property_link_id: pl.property_link_id,
      position:         pl.position,
    }));
    const { error: linkError } = await supabase.from('client_property_links').insert(linkRows);
    if (linkError) {
      console.error('[POST /clients] property_links insert failed', linkError);
      // Client was created; report partial success so caller can retry links
    }
  }

  res.status(201).json(data);
  nudgeScheduler();
});

// PATCH /api/clients/:id
router.patch('/:id', async (req: Request, res: Response) => {
  const allowed = ['name', 'phone_number', 'email', 'notes'];
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

  if ('property_links' in req.body) {
    const { error: delLinkError } = await supabase
      .from('client_property_links').delete().eq('client_id', req.params.id);
    if (delLinkError) {
      console.error('[PATCH /clients] property_links delete failed', delLinkError);
      res.status(500).json({ error: 'Failed to update property links' }); return;
    }
    const property_links = req.body.property_links;
    if (Array.isArray(property_links) && property_links.length > 0) {
      const linkRows = property_links.map((pl: any) => ({
        client_id:        req.params.id,
        property_link_id: pl.property_link_id,
        position:         pl.position,
      }));
      const { error: insLinkError } = await supabase.from('client_property_links').insert(linkRows);
      if (insLinkError) {
        console.error('[PATCH /clients] property_links insert failed', insLinkError);
        res.status(500).json({ error: 'Failed to save property links' }); return;
      }
    }
  }

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

// PATCH /api/clients/:id/archive — move client into "Não Ativos"
router.patch('/:id/archive', async (req: Request, res: Response) => {
  const clientId = req.params.id;

  const { data: client } = await supabase
    .from('clients')
    .select('id')
    .eq('id', clientId)
    .eq('agent_id', req.agentId!)
    .maybeSingle();

  if (!client) { res.status(404).json({ error: 'Client not found' }); return; }

  const { error: updErr } = await supabase
    .from('clients')
    .update({ archived_at: new Date().toISOString() })
    .eq('id', clientId);
  if (updErr) { res.status(500).json({ error: updErr.message }); return; }

  await supabase
    .from('follow_up_messages')
    .update({ status: 'cancelled' })
    .eq('client_id', clientId)
    .eq('status', 'pending');

  await supabase
    .from('cold_clients')
    .delete()
    .eq('client_id', clientId);

  res.json({ ok: true });
});

// PATCH /api/clients/:id/unarchive — restore client to Pendentes
router.patch('/:id/unarchive', async (req: Request, res: Response) => {
  const clientId = req.params.id;

  const { data: client } = await supabase
    .from('clients')
    .select('id')
    .eq('id', clientId)
    .eq('agent_id', req.agentId!)
    .maybeSingle();

  if (!client) { res.status(404).json({ error: 'Client not found' }); return; }

  const { error: updErr } = await supabase
    .from('clients')
    .update({ archived_at: null })
    .eq('id', clientId);
  if (updErr) { res.status(500).json({ error: updErr.message }); return; }

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
    const { error: slErr } = await supabase.from('send_log').delete().in('message_id', msgIds);
    if (slErr) { console.error('[DELETE /clients] send_log delete failed', slErr); res.status(500).json({ error: 'Failed to delete client data' }); return; }
  }

  const { error: fupErr } = await supabase.from('follow_up_messages').delete().eq('client_id', clientId);
  if (fupErr) { console.error('[DELETE /clients] follow_up_messages delete failed', fupErr); res.status(500).json({ error: 'Failed to delete client data' }); return; }

  const { error: ccErr } = await supabase.from('cold_clients').delete().eq('client_id', clientId);
  if (ccErr) { console.error('[DELETE /clients] cold_clients delete failed', ccErr); res.status(500).json({ error: 'Failed to delete client data' }); return; }

  const { error: cErr } = await supabase.from('clients').delete().eq('id', clientId);
  if (cErr) { console.error('[DELETE /clients] clients delete failed', cErr); res.status(500).json({ error: 'Failed to delete client' }); return; }

  res.json({ ok: true });
});

export default router;
