import { supabase } from './supabase';
import { localYmd } from './rateLimits';

// Applies per-day scheduled_count deltas to daily_send_counters for one agent.
// Positive delta = new scheduled messages; negative = released/cancelled/rescheduled-away.
//
// Uses the `apply_scheduled_delta` Postgres RPC (see migration
// 2026-05-03_messaging_hardening.sql) so concurrent campaign launches and the
// scheduler's release-on-failure path can't lose updates.
export async function applyScheduledDelta(
  agentId: string,
  dayDelta: Record<string, number>,
): Promise<void> {
  const days = Object.keys(dayDelta).filter(d => dayDelta[d] !== 0);
  if (days.length === 0) return;

  // The RPC is per-day; loop here. Each call is its own atomic UPSERT in Postgres,
  // so two callers updating the same (agent, day) cannot lose increments.
  for (const day of days) {
    const { error } = await supabase.rpc('apply_scheduled_delta', {
      p_agent_id: agentId,
      p_day: day,
      p_delta: dayDelta[day],
    });
    if (error) console.error(`[counters] apply_scheduled_delta(${agentId}, ${day}, ${dayDelta[day]}) failed:`, error);
  }
}

// Called by the scheduler after a successful send. Bumps sent_count for the
// day on which the send actually occurred (APP_TZ) and decrements scheduled_count.
// Uses the `record_sent_delta` RPC for atomic increment/decrement.
export async function recordSent(agentId: string, sentAtIso: string): Promise<void> {
  const day = localYmd(sentAtIso);
  const { error } = await supabase.rpc('record_sent_delta', {
    p_agent_id: agentId,
    p_day: day,
  });
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
