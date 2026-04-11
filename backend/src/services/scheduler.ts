import { supabase } from './supabase';
import { sendTextMessage, formatMessage } from './evolution';

let _timer: NodeJS.Timeout | null = null;
let _running = false;

// ── Cold clients ──────────────────────────────────────────────────────────────

async function fetchDueColdClients() {
  const now = new Date().toISOString();
  const { data, error } = await supabase
    .from('cold_clients')
    .select('*, clients!inner(name, phone_number, is_active, email, property_link_id, property_links(link))')
    .eq('is_active', true)
    .lte('next_send_at', now);

  if (error) throw new Error(`fetchDueColdClients: ${error.message}`);
  return (data ?? []).filter((row: any) => row.clients?.is_active === true);
}

async function sendColdBatch(rows: any[]) {
  for (const row of rows) {
    const client = row.clients ?? {};

    // Resolve template body
    let body = '';
    if (row.template_id) {
      const { data: tpl } = await supabase
        .from('agent_templates')
        .select('body')
        .eq('id', row.template_id)
        .maybeSingle();
      body = tpl?.body ?? '';
    }

    if (!body) {
      console.warn(`[ColdScheduler] cold_client ${row.id} has no template — skipping.`);
      continue;
    }

    const formatted = formatMessage(body, client);
    const { success, error } = await sendTextMessage(client.phone_number ?? '', formatted);

    if (success) {
      const newSent = (row.messages_sent ?? 0) + 1;
      const hitLimit = row.max_messages != null && newSent >= row.max_messages;
      const nextSendAt = new Date(Date.now() + row.interval_days * 86_400_000).toISOString();

      await supabase
        .from('cold_clients')
        .update({
          messages_sent: newSent,
          next_send_at:  hitLimit ? null : nextSendAt,
          is_active:     !hitLimit,
        })
        .eq('id', row.id);

      if (hitLimit) {
        console.log(`[ColdScheduler] cold_client ${row.id} reached max_messages (${row.max_messages}) — deactivated.`);
      }
    } else {
      console.error(`[ColdScheduler] Failed to send cold message for ${row.id}: ${error}`);
    }
  }
}

// ── Core logic (unchanged) ────────────────────────────────────────────────────

async function fetchPendingDueMessages() {
  const now = new Date().toISOString();
  const { data, error } = await supabase
    .from('follow_up_messages')
    .select('*, clients!inner(name, phone_number, is_active, email, property_link_id, property_links(link))')
    .eq('status', 'pending')
    .lte('send_at', now)
    .order('send_at');

  if (error) throw new Error(`fetchPendingDueMessages: ${error.message}`);
  return (data ?? []).filter((m: any) => m.clients?.is_active === true);
}

async function fetchNextPendingPerClient() {
  const { data, error } = await supabase
    .from('follow_up_messages')
    .select('*, clients!inner(name, phone_number, is_active, email, property_link_id, property_links(link))')
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

  // Next regular follow-up message
  const { data: fupData } = await supabase
    .from('follow_up_messages')
    .select('send_at, clients!inner(is_active)')
    .eq('status', 'pending')
    .gt('send_at', now)
    .order('send_at')
    .limit(10);

  const nextFup = (fupData ?? []).find((m: any) => m.clients?.is_active === true);

  // Next cold client send
  const { data: coldData } = await supabase
    .from('cold_clients')
    .select('next_send_at')
    .eq('is_active', true)
    .not('next_send_at', 'is', null)
    .gt('next_send_at', now)
    .order('next_send_at')
    .limit(1);

  const nextCold = coldData?.[0] ?? null;

  const candidates: Date[] = [];
  if (nextFup)  candidates.push(new Date(nextFup.send_at));
  if (nextCold) candidates.push(new Date(nextCold.next_send_at));

  if (candidates.length === 0) return null;
  return candidates.reduce((a, b) => (a < b ? a : b));
}

// ── Main loop ─────────────────────────────────────────────────────────────────

const MIN_SLEEP_MS  = 10_000;        // never sleep less than 10 seconds
const MAX_SLEEP_MS  = 60 * 60_000;   // never sleep more than 1 hour (safety cap)
const OVERDUE_GRACE = 5_000;         // wait 5s after wake-up before sending

async function tick() {
  if (!_running) return;

  try {
    // 1. Send regular follow-up messages due right now
    const messages = await fetchPendingDueMessages();
    if (messages.length > 0) {
      console.log(`[Scheduler] Sending ${messages.length} message(s).`);
      await sendBatch(messages);
    }

    // 2. Send cold client messages due right now
    const coldRows = await fetchDueColdClients();
    if (coldRows.length > 0) {
      console.log(`[ColdScheduler] Sending ${coldRows.length} cold message(s).`);
      await sendColdBatch(coldRows);
    }

    // 3. Find when the next message is due
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