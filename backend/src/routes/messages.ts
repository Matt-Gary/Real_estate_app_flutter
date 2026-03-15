import { Router, Request, Response } from 'express';
import { supabase } from '../services/supabase';
import { requireAuth } from '../middleware/auth';
import { nudgeScheduler } from '../services/scheduler';

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

  // Verify ownership
  const { data: client } = await supabase
    .from('clients')
    .select('id')
    .eq('id', req.params.clientId)
    .eq('agent_id', req.agentId!)
    .maybeSingle();

  if (!client) { res.status(404).json({ error: 'Client not found' }); return; }

  // Fetch existing messages to preserve their current status
  const { data: existing } = await supabase
    .from('follow_up_messages')
    .select('seq, status')
    .eq('client_id', req.params.clientId);

  const existingStatus: Record<number, string> = {};
  for (const m of (existing ?? [])) {
    existingStatus[m.seq] = m.status;
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
  nudgeScheduler();
  res.json(data);
});

export default router;
