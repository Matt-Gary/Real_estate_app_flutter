import { Router, Request, Response } from 'express';
import { timingSafeEqual } from 'crypto';
import { supabase } from '../services/supabase';

const router = Router();

// Opt-out phrases — normalize body (lowercase, strip diacritics) then test.
// Each entry is a regex source; all use word-boundary matching to avoid
// false positives like "parado" matching "para".
const OPT_OUT_PATTERNS: Array<{ phrase: string; regex: RegExp }> = [
  { phrase: 'stop',                       regex: /\bstop\b/ },
  { phrase: 'para',                       regex: /\bpara\b/ },
  { phrase: 'parar',                      regex: /\bparar\b/ },
  { phrase: 'nao quero',                  regex: /\bnao\s+quero\b/ },
  { phrase: 'me tira dessa lista',        regex: /\bme\s+tira\s+dessa\s+lista\b/ },
  { phrase: 'chega',                      regex: /\bchega\b/ },
  { phrase: 'para de me mandar mensagem', regex: /\bpara\s+de\s+me\s+mandar\s+mensagem/ },
  { phrase: 'nao me mande mais',          regex: /\bnao\s+me\s+mande\s+mais\b/ },
  { phrase: 'remove',                     regex: /\bremove\b/ },
  { phrase: 'cancelar',                   regex: /\bcancelar\b/ },
  { phrase: 'sair',                       regex: /\bsair\b/ },
];

function normalize(text: string): string {
  return text.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').trim();
}

function matchOptOut(body: string): string | null {
  const n = normalize(body);
  for (const p of OPT_OUT_PATTERNS) {
    if (p.regex.test(n)) return p.phrase;
  }
  return null;
}

// Evolution sends remoteJid like "5511987654321@s.whatsapp.net" (individuals)
// or "...@g.us" (groups — ignore). We store phone as "+5511987654321".
function jidToPhone(jid: string | undefined): string | null {
  if (!jid) return null;
  if (jid.includes('@g.us')) return null;
  const digits = jid.split('@')[0].replace(/\D/g, '');
  if (!digits) return null;
  return '+' + digits;
}

function extractMessageText(message: any): string {
  if (!message || typeof message !== 'object') return '';
  if (typeof message.conversation === 'string') return message.conversation;
  if (typeof message.extendedTextMessage?.text === 'string') return message.extendedTextMessage.text;
  if (typeof message.imageMessage?.caption === 'string') return message.imageMessage.caption;
  if (typeof message.videoMessage?.caption === 'string') return message.videoMessage.caption;
  if (typeof message.buttonsResponseMessage?.selectedDisplayText === 'string')
    return message.buttonsResponseMessage.selectedDisplayText;
  return '';
}

// Webhook secret check — Evolution can forward an `apikey` header or a
// custom `x-webhook-secret`. We accept either, compared against
// EVOLUTION_WEBHOOK_SECRET. Reject if the env var is unset (fail-closed).
function verifySecret(req: Request): boolean {
  const expected = process.env.EVOLUTION_WEBHOOK_SECRET;
  if (!expected) {
    console.warn('[Webhook] EVOLUTION_WEBHOOK_SECRET not configured — rejecting all webhook calls.');
    return false;
  }
  const got = req.header('x-webhook-secret') ?? req.header('apikey') ?? '';
  const a = Buffer.from(got);
  const b = Buffer.from(expected);
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

async function handleIncomingMessage(data: any) {
  const key = data?.key ?? {};
  if (key.fromMe === true) return;

  const phone = jidToPhone(key.remoteJid);
  if (!phone) return;

  const body = extractMessageText(data?.message);
  if (!body) return;

  const matched = matchOptOut(body);
  if (!matched) return;

  // Find the matching client. Use eq first; if none found, try without country
  // code tolerance via LIKE on suffix (handles stored "+55 11 …" variants).
  let clientId: string | null = null;
  let agentId: string | null = null;
  {
    const { data: rows } = await supabase
      .from('clients')
      .select('id, agent_id')
      .eq('phone_number', phone)
      .limit(1);
    if (rows && rows.length > 0) {
      clientId = rows[0].id as string;
      agentId  = rows[0].agent_id as string;
    }
  }
  if (!clientId) {
    console.log(`[Webhook] Opt-out from ${phone} — no matching client, ignoring.`);
    return;
  }

  // Mark client opted-out and deactivate
  await supabase
    .from('clients')
    .update({
      opted_out_at: new Date().toISOString(),
      opt_out_reason: matched,
      is_active: false,
      replied_at: new Date().toISOString(),
    })
    .eq('id', clientId);

  // Cancel all pending follow-up messages
  await supabase
    .from('follow_up_messages')
    .update({ status: 'cancelled' })
    .eq('client_id', clientId)
    .eq('status', 'pending');

  // Deactivate any cold campaigns for this client
  await supabase
    .from('cold_clients')
    .update({ is_active: false })
    .eq('client_id', clientId)
    .eq('is_active', true);

  // Notify the agent
  if (agentId) {
    await supabase.from('agent_alerts').insert({
      agent_id: agentId,
      kind: 'opt_out',
      severity: 'warning',
      message: `Cliente ${phone} pediu para parar ("${matched}"). Mensagens pendentes canceladas.`,
    });
  }

  console.log(`[Webhook] Opt-out processed for client ${clientId} (phrase: "${matched}")`);
}

async function handleConnectionUpdate(instance: string, data: any) {
  const state: string = data?.state ?? 'unknown';
  if (state === 'open') return;            // healthy — nothing to do

  const { data: agentRow } = await supabase
    .from('agents')
    .select('id, queue_paused_at')
    .eq('whatsapp_instance_name', instance)
    .maybeSingle();
  if (!agentRow) return;

  const kind = state === 'close' ? 'instance_offline' : 'qr_requested';
  const severity = 'critical';
  const message =
    kind === 'instance_offline'
      ? 'WhatsApp desconectou inesperadamente. Reconecte para retomar envios.'
      : 'WhatsApp pediu novo QR code no meio da sessão — possível sinal de problema.';

  if (!agentRow.queue_paused_at) {
    await supabase
      .from('agents')
      .update({ queue_paused_at: new Date().toISOString(), queue_paused_reason: state })
      .eq('id', agentRow.id);
  }

  await supabase.from('agent_alerts').insert({
    agent_id: agentRow.id,
    kind,
    severity,
    message,
  });
  console.warn(`[Webhook] Connection event for agent ${agentRow.id} — state=${state}, queue paused.`);
}

// POST /api/webhooks/evolution
// Evolution posts events as { event, instance, data }. Some self-hosted builds
// post one flat payload; others batch under { data: [ … ] }. We handle both.
router.post('/evolution', async (req: Request, res: Response) => {
  if (!verifySecret(req)) { res.status(401).json({ error: 'Unauthorized' }); return; }

  try {
    const payload = req.body ?? {};
    const event = payload.event ?? payload.type ?? '';
    const instance = payload.instance ?? payload.instanceName ?? '';

    const events = Array.isArray(payload.data) ? payload.data : [payload.data];

    for (const ev of events) {
      if (!ev) continue;
      if (event === 'messages.upsert' || event === 'MESSAGES_UPSERT') {
        await handleIncomingMessage(ev);
      } else if (event === 'connection.update' || event === 'CONNECTION_UPDATE') {
        await handleConnectionUpdate(instance, ev);
      }
    }

    res.json({ ok: true });
  } catch (err) {
    console.error('[Webhook] handler error:', err);
    res.status(500).json({ error: 'Webhook handler failed' });
  }
});

export default router;
