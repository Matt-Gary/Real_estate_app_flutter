import cron from 'node-cron';
import { supabase } from './supabase';
import { sendTextMessage, formatMessage } from './evolution';

// Mirrors Python scheduler.py — smart scheduling:
// processes due messages and logs every attempt.

let cronJob: cron.ScheduledTask | null = null;

// ── Core send logic (mirrors Python _send_batch) ──────────────────────────────

async function fetchPendingDueMessages() {
  const now = new Date().toISOString();
  const { data, error } = await supabase
    .from('follow_up_messages')
    .select('*, clients!inner(name, phone_number, property_link, is_active, email)')
    .eq('status', 'pending')
    .lte('send_at', now)
    .order('send_at');

  if (error) throw new Error(`fetchPendingDueMessages: ${error.message}`);
  // Filter is_active in JS — Supabase client can't filter on joined columns
  return (data ?? []).filter((m: any) => m.clients?.is_active === true);
}

async function fetchNextPendingPerClient() {
  // Used by sendNow — ignores send_at, returns lowest seq per active client
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

    // Mark sent or failed (mirrors Python mark_message_sent / mark_message_failed)
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

    // Append-only send log (mirrors Python log_send_attempt)
    await supabase.from('send_log').insert({
      message_id:      msg.id,
      success,
      response_status: statusCode,
      error_detail:    error,
    });
  }
}

// ── Scheduled job (runs every minute — mirrors Python _process_pending) ───────

async function processPending() {
  try {
    const messages = await fetchPendingDueMessages();
    if (messages.length === 0) return;
    console.log(`[Scheduler] ${messages.length} message(s) to send.`);
    await sendBatch(messages);
  } catch (err) {
    console.error('[Scheduler] Error:', err);
  }
}

// ── Public API ────────────────────────────────────────────────────────────────

export function startScheduler() {
  if (cronJob) return;
  // Every minute — equivalent to Python IntervalTrigger(seconds=60)
  cronJob = cron.schedule('* * * * *', processPending, { timezone: process.env.TZ });
  console.log(`[Scheduler] Started — TZ: ${process.env.TZ}`);
}

export function stopScheduler() {
  cronJob?.stop();
  cronJob = null;
}

// Mirrors Python run_now() — sends next message per client ignoring schedule
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
