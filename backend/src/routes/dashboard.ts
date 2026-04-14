import { Router, Request, Response } from 'express';
import { supabase } from '../services/supabase';
import { requireAuth } from '../middleware/auth';
import { checkInstanceStatus } from '../services/evolution';
import { sendNow } from '../services/scheduler';

const router = Router();
router.use(requireAuth);

// GET /api/dashboard/stats
router.get('/stats', async (req: Request, res: Response) => {
  const agentId = req.agentId!;

  const { data: clients } = await supabase
    .from('clients')
    .select('id, is_active')
    .eq('agent_id', agentId);

  const total   = (clients ?? []).length;
  const active  = (clients ?? []).filter((c: any) => c.is_active).length;
  const replied = total - active;

  const clientIds = (clients ?? []).map((c: any) => c.id);
  let sent = 0, pending = 0, failed = 0, cancelled = 0;

  if (clientIds.length > 0) {
    const { data: msgs } = await supabase
      .from('follow_up_messages')
      .select('status')
      .in('client_id', clientIds);

    for (const m of (msgs ?? [])) {
      if (m.status === 'sent')      sent++;
      if (m.status === 'pending')   pending++;
      if (m.status === 'failed')    failed++;
      if (m.status === 'cancelled') cancelled++;
    }
  }

  // Fetch the agent's own WhatsApp instance — each agent has their own number
  const { data: agentRow } = await supabase
    .from('agents')
    .select('whatsapp_instance_name')
    .eq('id', agentId)
    .single();

  const instanceName = agentRow?.whatsapp_instance_name ?? null;
  const waStatus = instanceName
    ? await checkInstanceStatus(instanceName)
    : { state: 'not_configured' };

  res.json({ total, active, replied, sent, pending, failed, cancelled, waStatus });
});

// POST /api/dashboard/send-now
router.post('/send-now', async (_req: Request, res: Response) => {
  const result = await sendNow();
  res.json(result);
});

export default router;
