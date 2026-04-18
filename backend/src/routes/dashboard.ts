import { Router, Request, Response } from 'express';
import { supabase } from '../services/supabase';
import { requireAuth } from '../middleware/auth';
import { checkInstanceStatus } from '../services/evolution';
import { sendNow } from '../services/scheduler';
import { getTodayQuota } from '../services/counters';
import { DAILY_LIMIT } from '../services/rateLimits';

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
    .select('whatsapp_instance_name, queue_paused_at, queue_paused_reason')
    .eq('id', agentId)
    .single();

  const instanceName = agentRow?.whatsapp_instance_name ?? null;
  const waStatus = instanceName
    ? await checkInstanceStatus(instanceName)
    : { state: 'not_configured' };

  const { used, day } = await getTodayQuota(agentId);

  const { data: alerts } = await supabase
    .from('agent_alerts')
    .select('id, kind, severity, message, created_at')
    .eq('agent_id', agentId)
    .is('dismissed_at', null)
    .order('created_at', { ascending: false })
    .limit(20);

  res.json({
    total, active, replied, sent, pending, failed, cancelled, waStatus,
    dailyQuota: { used, limit: DAILY_LIMIT, day },
    queuePaused: !!agentRow?.queue_paused_at,
    queuePausedReason: agentRow?.queue_paused_reason ?? null,
    alerts: alerts ?? [],
  });
});

// POST /api/dashboard/send-now
router.post('/send-now', async (_req: Request, res: Response) => {
  const result = await sendNow();
  res.json(result);
});

// POST /api/dashboard/alerts/:id/dismiss
router.post('/alerts/:id/dismiss', async (req: Request, res: Response) => {
  const { error } = await supabase
    .from('agent_alerts')
    .update({ dismissed_at: new Date().toISOString() })
    .eq('id', req.params.id)
    .eq('agent_id', req.agentId!);
  if (error) { res.status(500).json({ error: error.message }); return; }
  res.json({ ok: true });
});

// POST /api/dashboard/queue/resume
router.post('/queue/resume', async (req: Request, res: Response) => {
  const { error } = await supabase
    .from('agents')
    .update({ queue_paused_at: null, queue_paused_reason: null })
    .eq('id', req.agentId!);
  if (error) { res.status(500).json({ error: error.message }); return; }
  res.json({ ok: true });
});

export default router;
