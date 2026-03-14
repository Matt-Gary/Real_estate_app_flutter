import axios from 'axios';
import dotenv from 'dotenv';
dotenv.config();

const BASE_URL  = (process.env.EVOLUTION_API_URL || '').replace(/\/$/, '');
const API_KEY   = process.env.EVOLUTION_API_KEY!;
const INSTANCE  = process.env.EVOLUTION_INSTANCE!;
const DRY_RUN   = process.env.DRY_RUN === 'true';

const headers = {
  apikey: API_KEY,
  'Content-Type': 'application/json',
};

export interface SendResult {
  success: boolean;
  statusCode: number | null;
  error: string | null;
}

// Mirrors Python evolution.send_text_message()
export async function sendTextMessage(phone: string, text: string): Promise<SendResult> {
  if (DRY_RUN) {
    console.log(`[DRY RUN] Would send to ${phone}: ${text.slice(0, 80)}...`);
    return { success: true, statusCode: 200, error: null };
  }

  const url = `${BASE_URL}/message/sendText/${INSTANCE}`;
  const payload = {
    number: phone.replace(/^\+/, ''),
    options: { delay: 1200, presence: 'composing' },
    text,                    // Evolution API v2: top-level "text"
  };

  try {
    const res = await axios.post(url, payload, { headers, timeout: 15000 });
    console.log(`Message sent to ${phone} ✓`);
    return { success: true, statusCode: res.status, error: null };
  } catch (err: any) {
    const statusCode = err.response?.status ?? null;
    const detail     = err.response?.data
      ? JSON.stringify(err.response.data).slice(0, 300)
      : err.message;
    console.warn(`Evolution API error ${statusCode}: ${detail}`);
    return { success: false, statusCode, error: detail };
  }
}

// Mirrors Python evolution.check_instance_status()
export async function checkInstanceStatus(): Promise<Record<string, any>> {
  try {
    const url = `${BASE_URL}/instance/connectionState/${INSTANCE}`;
    const res = await axios.get(url, { headers, timeout: 10000 });
    return res.data;
  } catch (err: any) {
    return { state: 'error', detail: err.message };
  }
}

// Mirrors Python evolution.format_message()
export function formatMessage(body: string, client: Record<string, any>): string {
  return body
    .replace(/\{name\}/g,          client.name          ?? '')
    .replace(/\{property_link\}/g, client.property_link ?? '')
    .replace(/\{email\}/g,         client.email         ?? '');
}
