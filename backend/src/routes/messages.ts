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

  // Delete any pending messages that are not in the incoming payload
  const incomingSeqs = rows.map((r: any) => r.seq);
  const toDelete = (existing ?? [])
    .filter(m => !incomingSeqs.includes(m.seq) && m.status === 'pending')
    .map(m => m.seq);

  if (toDelete.length > 0) {
    await supabase
      .from('follow_up_messages')
      .delete()
      .eq('client_id', req.params.clientId)
      .in('seq', toDelete);
  }

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

  // Ensure client is active so scheduler can pick up new messages
  const { error: activateErr } = await supabase
    .from('clients')
    .update({ is_active: true, replied_at: null })
    .eq('id', req.params.clientId);
  if (activateErr) { console.error('[DELETE messages] client reactivation failed', activateErr); }

  res.json({ ok: true });
});

export default router;
