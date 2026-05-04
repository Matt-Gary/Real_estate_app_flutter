import { Router, Request, Response } from 'express';
import { supabase } from '../services/supabase';
import { requireAuth } from '../middleware/auth';
import { checkInstanceStatus } from '../services/evolution';
import { sendNow } from '../services/scheduler';
import { getTodayQuota } from '../services/counters';
import { DAILY_LIMIT, localYmd } from '../services/rateLimits';

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

  // Break today's quota usage down by source so the dashboard can show
  // "Follow-ups X / Campanhas Y / Total Z / Limit N".
  const todayYmd = localYmd(new Date());
  const todayStart = `${todayYmd}T00:00:00-03:00`;
  const tomorrowYmd = (() => {
    const [y, m, d] = todayYmd.split('-').map(Number);
    const dt = new Date(Date.UTC(y, m - 1, d, 12, 0, 0));
    dt.setUTCDate(dt.getUTCDate() + 1);
    return `${dt.getUTCFullYear()}-${String(dt.getUTCMonth() + 1).padStart(2, '0')}-${String(dt.getUTCDate()).padStart(2, '0')}`;
  })();
  const todayEnd = `${tomorrowYmd}T00:00:00-03:00`;

  const breakdown = { followup: 0, cold: 0, campaign: 0 };
  if (clientIds.length > 0) {
    // Sent today
    const { data: sentToday } = await supabase
      .from('follow_up_messages')
      .select('source')
      .in('client_id', clientIds)
      .gte('sent_at', todayStart)
      .lt('sent_at', todayEnd);
    for (const m of (sentToday ?? [])) {
      const src = (m.source as string) ?? 'followup';
      if (src in breakdown) (breakdown as any)[src]++;
    }
    // Still-pending but scheduled today (counts toward today's reservation)
    const { data: pendingToday } = await supabase
      .from('follow_up_messages')
      .select('source')
      .in('client_id', clientIds)
      .eq('status', 'pending')
      .gte('send_at', todayStart)
      .lt('send_at', todayEnd);
    for (const m of (pendingToday ?? [])) {
      const src = (m.source as string) ?? 'followup';
      if (src in breakdown) (breakdown as any)[src]++;
    }
  }

  const { data: alerts } = await supabase
    .from('agent_alerts')
    .select('id, kind, severity, message, created_at')
    .eq('agent_id', agentId)
    .is('dismissed_at', null)
    .order('created_at', { ascending: false })
    .limit(20);

  res.json({
    total, active, replied, sent, pending, failed, cancelled, waStatus,
    dailyQuota: { used, limit: DAILY_LIMIT, day, breakdown },
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
