// Anti-ban guardrails shared by message validation and the scheduler.
// All time comparisons use APP_TZ (driven by process.env.TZ, set at boot).

export const APP_TZ = process.env.TZ ?? 'America/Sao_Paulo';

export const DAILY_LIMIT = 100;
export const SEND_WINDOW_START_HOUR = 8;   // inclusive
export const SEND_WINDOW_END_HOUR   = 20;  // exclusive — last allowed slot is 19:59
export const MIN_GAP_HOURS_SAME_CLIENT = 48;
export const JITTER_MIN_MS = 5_000;
export const JITTER_MAX_MS = 30_000;

const _ymdFmt = new Intl.DateTimeFormat('en-CA', {
  timeZone: APP_TZ, year: 'numeric', month: '2-digit', day: '2-digit',
});
const _hourFmt = new Intl.DateTimeFormat('en-US', {
  timeZone: APP_TZ, hour: '2-digit', hour12: false,
});

// 'YYYY-MM-DD' in APP_TZ for the given ISO string / Date.
export function localYmd(iso: string | Date): string {
  const d = typeof iso === 'string' ? new Date(iso) : iso;
  return _ymdFmt.format(d);
}

// Hour-of-day (0–23) in APP_TZ for the given ISO string / Date.
export function localHour(iso: string | Date): number {
  const d = typeof iso === 'string' ? new Date(iso) : iso;
  // Intl 'en-US' with hour12:false returns '24' for midnight in some Node builds — normalize.
  const h = parseInt(_hourFmt.format(d), 10);
  return h === 24 ? 0 : h;
}

export function isWithinSendWindow(iso: string | Date): boolean {
  const h = localHour(iso);
  return h >= SEND_WINDOW_START_HOUR && h < SEND_WINDOW_END_HOUR;
}

export function applyJitter(): number {
  return JITTER_MIN_MS + Math.floor(Math.random() * (JITTER_MAX_MS - JITTER_MIN_MS + 1));
}

export function sleep(ms: number): Promise<void> {
  return new Promise(r => setTimeout(r, ms));
}
