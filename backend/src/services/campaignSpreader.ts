import {
  DAILY_LIMIT,
  SEND_WINDOW_START_HOUR,
  SEND_WINDOW_END_HOUR,
  localYmd,
} from './rateLimits';

// São Paulo is UTC-3 year-round (DST abolished in 2019). Construct send
// instants with an explicit offset so the spreader is independent of the
// Node process's local TZ.
const APP_TZ_OFFSET = '-03:00';

export interface ClientLite {
  id: string;
  name: string;
}

export interface BatchPlanDay {
  date: string;          // YYYY-MM-DD in APP_TZ
  count: number;
  firstSendAt: string;   // ISO with offset
  lastSendAt: string;    // ISO with offset
  recipientPreview: { id: string; name: string }[]; // first 5
}

export interface SpreadRecipient {
  clientId: string;
  name: string;
  scheduledFor: Date;
}

export interface SpreadResult {
  recipients: SpreadRecipient[];
  batchPlan: BatchPlanDay[];
  unscheduledCount: number;   // > 0 only if we hit the safety cap
}

export interface SpreadOptions {
  dailyQuota: number;
  startAt: Date;
  /** Per-day count of (sent + scheduled) for this agent across all sources. */
  existingUsage: Record<string, number>;
  /** Defaults to the global DAILY_LIMIT. Exposed for tests. */
  agentDailyCap?: number;
  /** Safety cap so a misconfigured run can't blow up. */
  maxDays?: number;
}

const MS_PER_HOUR = 3_600_000;
const WINDOW_HOURS = SEND_WINDOW_END_HOUR - SEND_WINDOW_START_HOUR;
const WINDOW_MS = WINDOW_HOURS * MS_PER_HOUR;

function pad(n: number): string {
  return n.toString().padStart(2, '0');
}

/** Returns the absolute instant for `${ymd} ${hour}:00:00` in APP_TZ. */
function instantAt(ymd: string, hour: number): number {
  return Date.parse(`${ymd}T${pad(hour)}:00:00${APP_TZ_OFFSET}`);
}

/** Returns the YYYY-MM-DD string for the day immediately after `ymd` (calendar arithmetic, TZ-independent). */
function nextYmd(ymd: string): string {
  const [y, m, d] = ymd.split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d, 12, 0, 0));
  dt.setUTCDate(dt.getUTCDate() + 1);
  return `${dt.getUTCFullYear()}-${pad(dt.getUTCMonth() + 1)}-${pad(dt.getUTCDate())}`;
}

/**
 * Distributes `clients` across days and within the daily 08:00–20:00 window,
 * honoring `dailyQuota` (per-campaign) and `agentDailyCap` (global) while
 * respecting `existingUsage` already on the calendar.
 *
 * The 48h-per-client gap is NOT enforced here — that check lives in the
 * caller, which filters the eligible set before invoking the spreader.
 *
 * Slots are evenly spaced across the available window with a half-step
 * inset on both ends; the per-send 5–30s jitter is still applied at send
 * time by the scheduler, on top of these instants.
 */
export function spreadCampaign(
  clients: ClientLite[],
  opts: SpreadOptions,
): SpreadResult {
  const recipients: SpreadRecipient[] = [];
  const batchPlan: BatchPlanDay[] = [];

  if (clients.length === 0) {
    return { recipients, batchPlan, unscheduledCount: 0 };
  }

  const agentCap = opts.agentDailyCap ?? DAILY_LIMIT;
  const maxDays = opts.maxDays ?? 365;
  const startMs = opts.startAt.getTime();

  let remaining = clients.slice();
  let currentDay = localYmd(opts.startAt);
  let firstDay = true;
  let safety = maxDays;

  while (remaining.length > 0 && safety-- > 0) {
    const existing = opts.existingUsage[currentDay] ?? 0;
    const todayCap = Math.min(opts.dailyQuota, Math.max(0, agentCap - existing));

    if (todayCap === 0) {
      currentDay = nextYmd(currentDay);
      firstDay = false;
      continue;
    }

    const dayWindowStart = instantAt(currentDay, SEND_WINDOW_START_HOUR);
    const dayWindowEnd   = instantAt(currentDay, SEND_WINDOW_END_HOUR);

    // On the first day, may need to start later than 08:00 if startAt is mid-day.
    const windowStart = firstDay ? Math.max(dayWindowStart, startMs) : dayWindowStart;
    const windowEnd   = dayWindowEnd;

    if (windowStart >= windowEnd) {
      // No usable window left today (e.g. startAt = 19:55 with 12-min spacing).
      currentDay = nextYmd(currentDay);
      firstDay = false;
      continue;
    }

    const N = Math.min(todayCap, remaining.length);
    const todayBatch = remaining.splice(0, N);
    const windowMs = windowEnd - windowStart;
    const step = windowMs / N;

    let firstSlot = Number.POSITIVE_INFINITY;
    let lastSlot  = Number.NEGATIVE_INFINITY;

    todayBatch.forEach((client, i) => {
      const slotMs = windowStart + step * (i + 0.5);
      const slot = new Date(slotMs);
      recipients.push({ clientId: client.id, name: client.name, scheduledFor: slot });
      if (slotMs < firstSlot) firstSlot = slotMs;
      if (slotMs > lastSlot)  lastSlot  = slotMs;
    });

    batchPlan.push({
      date: currentDay,
      count: N,
      firstSendAt: new Date(firstSlot).toISOString(),
      lastSendAt:  new Date(lastSlot).toISOString(),
      recipientPreview: todayBatch.slice(0, 5).map(c => ({ id: c.id, name: c.name })),
    });

    currentDay = nextYmd(currentDay);
    firstDay = false;
  }

  return { recipients, batchPlan, unscheduledCount: remaining.length };
}

/**
 * Re-derives a batchPlan from a (possibly filtered) recipient list. Use this
 * when post-processing the spreader output (e.g. dropping same-day conflicts)
 * so the UI sees correct per-day counts and recipientPreview.
 */
export function deriveBatchPlan(recipients: SpreadRecipient[]): BatchPlanDay[] {
  const byDay = new Map<string, SpreadRecipient[]>();
  for (const r of recipients) {
    const day = localYmd(r.scheduledFor);
    if (!byDay.has(day)) byDay.set(day, []);
    byDay.get(day)!.push(r);
  }
  return Array.from(byDay.keys()).sort().map(date => {
    const rs = byDay.get(date)!.slice().sort(
      (a, b) => a.scheduledFor.getTime() - b.scheduledFor.getTime(),
    );
    return {
      date,
      count: rs.length,
      firstSendAt: rs[0].scheduledFor.toISOString(),
      lastSendAt: rs[rs.length - 1].scheduledFor.toISOString(),
      recipientPreview: rs.slice(0, 5).map(r => ({ id: r.clientId, name: r.name })),
    };
  });
}
