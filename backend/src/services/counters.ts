import { supabase } from './supabase';
import { localYmd } from './rateLimits';

// Applies per-day scheduled_count deltas to daily_send_counters for one agent.
// Positive delta = new scheduled messages; negative = released/cancelled/rescheduled-away.
// Uses fetch-then-upsert; concurrent writes for the same (agent, day) are rare
// since upserts happen during user-driven form saves.
export async function applyScheduledDelta(
  agentId: string,
  dayDelta: Record<string, number>,
): Promise<void> {
  const days = Object.keys(dayDelta).filter(d => dayDelta[d] !== 0);
  if (days.length === 0) return;

  const { data: rows } = await supabase
    .from('daily_send_counters')
    .select('day, sent_count, scheduled_count')
    .eq('agent_id', agentId)
    .in('day', days);

  const byDay: Record<string, { sent_count: number; scheduled_count: number }> = {};
  for (const r of (rows ?? [])) byDay[r.day as string] = r as any;

  const upserts = days.map(day => {
    const cur = byDay[day] ?? { sent_count: 0, scheduled_count: 0 };
    return {
      agent_id: agentId,
      day,
      sent_count: cur.sent_count,
      scheduled_count: Math.max(0, cur.scheduled_count + dayDelta[day]),
    };
  });

  const { error } = await supabase
    .from('daily_send_counters')
    .upsert(upserts, { onConflict: 'agent_id,day' });
  if (error) console.error('[counters] applyScheduledDelta failed:', error);
}

// Called by the scheduler after a successful send. Bumps sent_count for the
// day on which the send actually occurred (APP_TZ) and decrements scheduled_count.
export async function recordSent(agentId: string, sentAtIso: string): Promise<void> {
  const day = localYmd(sentAtIso);
  const { data: row } = await supabase
    .from('daily_send_counters')
    .select('sent_count, scheduled_count')
    .eq('agent_id', agentId)
    .eq('day', day)
    .maybeSingle();

  const cur = row ?? { sent_count: 0, scheduled_count: 0 };
  const { error } = await supabase
    .from('daily_send_counters')
    .upsert(
      {
        agent_id: agentId,
        day,
        sent_count: cur.sent_count + 1,
        scheduled_count: Math.max(0, cur.scheduled_count - 1),
      },
      { onConflict: 'agent_id,day' },
    );
  if (error) console.error('[counters] recordSent failed:', error);
}

// Returns today's (APP_TZ) sent + scheduled count for the given agent.
export async function getTodayQuota(
  agentId: string,
): Promise<{ used: number; day: string }> {
  const day = localYmd(new Date());
  const { data: row } = await supabase
    .from('daily_send_counters')
    .select('sent_count, scheduled_count')
    .eq('agent_id', agentId)
    .eq('day', day)
    .maybeSingle();
  const used = (row?.sent_count ?? 0) + (row?.scheduled_count ?? 0);
  return { used, day };
}
