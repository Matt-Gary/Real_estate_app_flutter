import { createClient, SupabaseClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
dotenv.config();

const url = process.env.SUPABASE_URL!;
const serviceKey = process.env.SUPABASE_SERVICE_KEY!;

if (!url || !serviceKey) {
  throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_KEY in .env');
}

// Single service-role client — bypasses RLS.
// All data isolation is enforced by filtering on agent_id in queries.
export const supabase: SupabaseClient = createClient(url, serviceKey);
