import { supabase } from './supabase';
import { sendTextMessage, formatMessage } from './evolution';

let _timer: NodeJS.Timeout | null = null;
let _running = false;

// ── Core logic (unchanged) ────────────────────────────────────────────────────

async function fetchPendingDueMessages() {
  const now = new Date().toISOString();
  const { data, error } = await supabase
    .from('follow_up_messages')
    .select('*, clients!inner(name, phone_number, property_link, is_active, email)')
    .eq('status', 'pending')
    .lte('send_at', now)
    .order('send_at');

  if (error) throw new Error(`fetchPendingDueMessages: ${error.message}`);
  return (data ?? []).filter((m: any) => m.clients?.is_active === true);
}

async function fetchNextPendingPerClient() {
  const { data, error } = await supabase
    .from('follow_up_messages')
    .select('*, clients!inner(name, phone_number, property_link, is_active, email)')
    .eq('status', 'pending')
    .order('client_id')
    .order('seq');

  if (error) throw new Error(`fetchNextPendingPerClient: ${error.message}`);

  const seen = new Set<string>();
  const result: any[] = [];
  for (const m of (data ?? [])) {
    if (!m.clients?.is_active) continue;
    if (!seen.has(m.client_id)) {
      seen.add(m.client_id);
      result.push(m);
    }
  }
  return result;
}

async function sendBatch(messages: any[]) {
  for (const msg of messages) {
    const client = msg.clients ?? {};
    const body   = formatMessage(msg.body, client);
    const phone  = client.phone_number ?? '';

    const { success, statusCode, error } = await sendTextMessage(phone, body);

    if (success) {
      await supabase
        .from('follow_up_messages')
        .update({ status: 'sent', sent_at: new Date().toISOString() })
        .eq('id', msg.id);
    } else {
      await supabase
        .from('follow_up_messages')
        .update({ status: 'failed', error_detail: error ?? 'Unknown error' })
        .eq('id', msg.id);
    }

    await supabase.from('send_log').insert({
      message_id:      msg.id,
      success,
      response_status: statusCode,
      error_detail:    error,
    });
  }
}

// ── Smart sleep: find the next send_at in the DB ──────────────────────────────

async function fetchNextSendAt(): Promise<Date | null> {
  const now = new Date().toISOString();
  const { data, error } = await supabase
    .from('follow_up_messages')
    .select('send_at, clients!inner(is_active)')
    .eq('status', 'pending')
    .gt('send_at', now)         // only future messages
    .order('send_at')
    .limit(10);                 // grab a few in case some have inactive clients

  if (error || !data || data.length === 0) return null;

  // Find the first one belonging to an active client
  const next = data.find((m: any) => m.clients?.is_active === true);
  return next ? new Date(next.send_at) : null;
}

// ── Main loop ─────────────────────────────────────────────────────────────────

const MIN_SLEEP_MS  = 10_000;        // never sleep less than 10 seconds
const MAX_SLEEP_MS  = 60 * 60_000;   // never sleep more than 1 hour (safety cap)
const OVERDUE_GRACE = 5_000;         // wait 5s after wake-up before sending

async function tick() {
  if (!_running) return;

  try {    
    // 1. Send anything that's due right now
    const messages = await fetchPendingDueMessages();
    if (messages.length > 0) {
      console.log(`[Scheduler] Sending ${messages.length} message(s).`);
      await sendBatch(messages);
    }

    // 2. Find when the next message is due
    const nextAt = await fetchNextSendAt();

    let sleepMs: number;

    if (!nextAt) {
      sleepMs = MAX_SLEEP_MS;
      console.log('[Scheduler] No upcoming messages. Sleeping 1 hour.');
    } else {
      const msUntilNext = nextAt.getTime() - Date.now();
      sleepMs = Math.max(MIN_SLEEP_MS, msUntilNext + OVERDUE_GRACE);
      console.log(`[Scheduler] Next message at ${nextAt.toISOString()} — sleeping ${Math.round(sleepMs / 1000)}s.`);
    }

    sleepMs = Math.min(sleepMs, MAX_SLEEP_MS);
    _timer = setTimeout(tick, sleepMs);

  } catch (err) {
    console.error('[Scheduler] Error:', err);
    _timer = setTimeout(tick, 60_000);
  }
}

// ── Public API ────────────────────────────────────────────────────────────────

export function startScheduler() {
  if (_running) return;
  _running = true;
  console.log('[Scheduler] Started — smart sleep mode.');
  tick(); // kick off immediately
}

export function stopScheduler() {
  _running = false;
  if (_timer) { clearTimeout(_timer); _timer = null; }
  console.log('[Scheduler] Stopped.');
}

export async function sendNow(): Promise<{ sent: number }> {
  const messages = await fetchNextPendingPerClient();
  if (messages.length === 0) {
    console.log('[SendNow] No pending messages.');
    return { sent: 0 };
  }
  console.log(`[SendNow] Sending ${messages.length} message(s).`);
  await sendBatch(messages);
  return { sent: messages.length };
}

// ── Called whenever a new message is scheduled ────────────────────────────────
// Import and call this from your clients route after inserting messages,
// so the scheduler wakes up immediately instead of waiting out its current sleep.

export function nudgeScheduler() {
  if (!_running) return;
  if (_timer) { clearTimeout(_timer); _timer = null; }
  console.log('[Scheduler] Nudged — re-evaluating schedule.');
  tick();
}