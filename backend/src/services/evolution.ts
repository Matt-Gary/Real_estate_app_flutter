import axios from 'axios';
import dotenv from 'dotenv';
dotenv.config();

const BASE_URL = (process.env.EVOLUTION_API_URL || '').replace(/\/$/, '');
const API_KEY  = process.env.EVOLUTION_API_KEY!;
const DRY_RUN  = process.env.DRY_RUN === 'true';

const headers = {
  apikey: API_KEY,
  'Content-Type': 'application/json',
};

export interface SendResult {
  success: boolean;
  statusCode: number | null;
  error: string | null;
}

// Send a WhatsApp text message via the agent's own Evolution instance.
export async function sendTextMessage(
  phone: string,
  text: string,
  instanceName: string,
): Promise<SendResult> {
  if (!instanceName) {
    return { success: false, statusCode: null, error: 'No WhatsApp instance configured for this agent' };
  }

  if (DRY_RUN) {
    console.log(`[DRY RUN] Would send to ${phone} via ${instanceName}: ${text.slice(0, 80)}...`);
    return { success: true, statusCode: 200, error: null };
  }

  const url = `${BASE_URL}/message/sendText/${instanceName}`;
  const payload = {
    number: phone.replace(/^\+/, ''),
    options: { delay: 1200, presence: 'composing' },
    text,
  };

  try {
    const res = await axios.post(url, payload, { headers, timeout: 15000 });
    console.log(`Message sent to ${phone} via ${instanceName} ✓`);
    return { success: true, statusCode: res.status, error: null };
  } catch (err: any) {
    const statusCode = err.response?.status ?? null;
    const detail = err.response?.data
      ? JSON.stringify(err.response.data).slice(0, 300)
      : err.message;
    console.warn(`Evolution API error ${statusCode} (${instanceName}): ${detail}`);
    return { success: false, statusCode, error: detail };
  }
}

// Get connection state for an agent's instance.
export async function checkInstanceStatus(instanceName: string): Promise<Record<string, any>> {
  try {
    const url = `${BASE_URL}/instance/connectionState/${instanceName}`;
    const res = await axios.get(url, { headers, timeout: 10000 });
    return res.data;
  } catch (err: any) {
    return { state: 'error', detail: err.message };
  }
}

// Create a new Evolution API instance for an agent.
// Treats "already exists" as success — safe to call multiple times.
export async function createInstance(instanceName: string): Promise<Record<string, any>> {
  try {
    const url = `${BASE_URL}/instance/create`;
    const res = await axios.post(
      url,
      { instanceName, integration: 'WHATSAPP-BAILEYS' },
      { headers, timeout: 15000 },
    );
    return res.data;
  } catch (err: any) {
    const status = err.response?.status ?? null;
    const body   = err.response?.data ?? {};
    // Evolution returns 4xx when the instance already exists — treat as success
    if (status && status >= 400 && status < 500) {
      const msg: string = JSON.stringify(body).toLowerCase();
      if (msg.includes('already') || msg.includes('exists') || msg.includes('conflict')) {
        console.log(`[Evolution] Instance ${instanceName} already exists — proceeding.`);
        return body;
      }
    }
    throw new Error(`createInstance failed (${status}): ${JSON.stringify(body).slice(0, 200)}`);
  }
}

// Get the QR code (or pairing code) needed to connect a phone to the instance.
export async function getQrCode(instanceName: string): Promise<Record<string, any>> {
  try {
    const url = `${BASE_URL}/instance/connect/${instanceName}`;
    const res = await axios.get(url, { headers, timeout: 15000 });
    return res.data;
  } catch (err: any) {
    const status = err.response?.status ?? null;
    const body   = err.response?.data ?? {};
    throw new Error(`getQrCode failed (${status}): ${JSON.stringify(body).slice(0, 200)}`);
  }
}

// Get the full connection state object for an instance.
export async function getConnectionState(instanceName: string): Promise<Record<string, any>> {
  try {
    const url = `${BASE_URL}/instance/connectionState/${instanceName}`;
    const res = await axios.get(url, { headers, timeout: 10000 });
    return res.data;
  } catch (err: any) {
    return { state: 'error', detail: err.message };
  }
}

// Logout (disconnect the phone) but keep the instance slot.
export async function logoutInstance(instanceName: string): Promise<void> {
  try {
    const url = `${BASE_URL}/instance/logout/${instanceName}`;
    await axios.delete(url, { headers, timeout: 10000 });
  } catch (err: any) {
    const status = err.response?.status ?? null;
    throw new Error(`logoutInstance failed (${status}): ${err.message}`);
  }
}

// Delete the instance entirely from Evolution API.
export async function deleteInstance(instanceName: string): Promise<void> {
  try {
    const url = `${BASE_URL}/instance/delete/${instanceName}`;
    await axios.delete(url, { headers, timeout: 10000 });
  } catch (err: any) {
    const status = err.response?.status ?? null;
    throw new Error(`deleteInstance failed (${status}): ${err.message}`);
  }
}

// Point an instance at our webhook endpoint so we receive incoming-message and
// connection-state events. Safe to call repeatedly (Evolution replaces the URL).
export async function configureWebhook(instanceName: string): Promise<void> {
  const publicUrl = process.env.PUBLIC_WEBHOOK_URL;
  if (!publicUrl) {
    console.warn('[Evolution] PUBLIC_WEBHOOK_URL not set — skipping webhook configuration.');
    return;
  }
  const secret = process.env.EVOLUTION_WEBHOOK_SECRET;
  try {
    const url = `${BASE_URL}/webhook/set/${instanceName}`;
    await axios.post(
      url,
      {
        url: publicUrl,
        enabled: true,
        webhook_by_events: false,
        events: ['MESSAGES_UPSERT', 'CONNECTION_UPDATE'],
        headers: secret ? { 'x-webhook-secret': secret } : undefined,
      },
      { headers, timeout: 10000 },
    );
    console.log(`[Evolution] Webhook configured for instance ${instanceName} → ${publicUrl}`);
  } catch (err: any) {
    const status = err.response?.status ?? null;
    console.warn(`[Evolution] configureWebhook(${instanceName}) failed (${status}): ${err.message}`);
  }
}

// Format a message template with client data and property links.
// links[0] = position-1 link, links[1] = position-2, etc.
export function formatMessage(body: string, client: Record<string, any>, links: string[] = []): string {
  const name  = client.name  ?? '';
  const email = client.email ?? '';
  let result = body
    .replace(/\{name\}/g,          () => name)
    .replace(/\{property_link\}/g, () => links[0] ?? '')   // backwards-compat alias for {link_1}
    .replace(/\{email\}/g,         () => email);
  links.forEach((url, i) => {
    result = result.replace(new RegExp(`\\{link_${i + 1}\\}`, 'g'), () => url);
  });
  return result;
}
