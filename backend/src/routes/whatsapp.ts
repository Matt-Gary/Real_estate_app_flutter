import { Router, Request, Response } from 'express';
import { supabase } from '../services/supabase';
import { requireAuth } from '../middleware/auth';
import {
  createInstance,
  getConnectionState,
  getQrCode,
  logoutInstance,
  deleteInstance,
  configureWebhook,
} from '../services/evolution';

const router = Router();
router.use(requireAuth);

// Derive a deterministic, URL-safe instance name from the agent's UUID.
// e.g. agentId "a3f2b901-..." → "agent_a3f2b901"
function generateInstanceName(agentId: string): string {
  return 'agent_' + agentId.replace(/-/g, '').slice(0, 8);
}

// Fetch the agent's current whatsapp_instance_name from the DB.
async function getAgentInstance(agentId: string): Promise<string | null> {
  const { data, error } = await supabase
    .from('agents')
    .select('whatsapp_instance_name')
    .eq('id', agentId)
    .single();
  if (error) throw new Error(`getAgentInstance: ${error.message}`);
  return data?.whatsapp_instance_name ?? null;
}

// POST /api/whatsapp/connect
// Creates (or reconnects) the agent's Evolution API instance and returns the instance name.
router.post('/connect', async (req: Request, res: Response) => {
  const agentId = req.agentId!;
  try {
    let instanceName = await getAgentInstance(agentId);

    if (!instanceName) {
      instanceName = generateInstanceName(agentId);
    }

    // Create the instance on Evolution API (idempotent — safe if it already exists)
    await createInstance(instanceName);

    // Point Evolution at our webhook so opt-outs + connection events reach us
    await configureWebhook(instanceName);

    // Clear any previous pause state on (re)connect
    const { error: updateErr } = await supabase
      .from('agents')
      .update({
        whatsapp_instance_name: instanceName,
        queue_paused_at: null,
        queue_paused_reason: null,
      })
      .eq('id', agentId);

    if (updateErr) throw new Error(`Failed to persist instance name: ${updateErr.message}`);

    res.json({ instanceName });
  } catch (err: any) {
    console.error('[WhatsApp] /connect error:', err.message);
    res.status(502).json({ error: err.message });
  }
});

// GET /api/whatsapp/status
// Returns the WhatsApp connection state for the agent's instance.
router.get('/status', async (req: Request, res: Response) => {
  const agentId = req.agentId!;
  try {
    const instanceName = await getAgentInstance(agentId);

    if (!instanceName) {
      return res.json({ state: 'not_configured', instanceName: null });
    }

    const stateData = await getConnectionState(instanceName);
    // Normalise: Evolution may nest state under instance.state or return it directly
    const state: string =
      stateData?.instance?.state ?? stateData?.state ?? 'unknown';

    // Track first successful connection
    if (state === 'open') {
      const { data: agentRow } = await supabase
        .from('agents')
        .select('whatsapp_connected_at')
        .eq('id', agentId)
        .single();

      if (!agentRow?.whatsapp_connected_at) {
        await supabase
          .from('agents')
          .update({ whatsapp_connected_at: new Date().toISOString() })
          .eq('id', agentId);
      }
    }

    res.json({ state, instanceName });
  } catch (err: any) {
    console.error('[WhatsApp] /status error:', err.message);
    res.status(502).json({ error: err.message });
  }
});

// GET /api/whatsapp/qrcode
// Returns the QR code data for the agent to scan with their phone.
// The frontend polls this every 3 seconds until state becomes 'open'.
router.get('/qrcode', async (req: Request, res: Response) => {
  const agentId = req.agentId!;
  try {
    const instanceName = await getAgentInstance(agentId);

    if (!instanceName) {
      return res.status(404).json({ error: 'WhatsApp instance not initialised. Call /connect first.' });
    }

    // Check if already connected — no QR needed
    const stateData = await getConnectionState(instanceName);
    const state: string =
      stateData?.instance?.state ?? stateData?.state ?? 'unknown';

    if (state === 'open') {
      return res.json({ state: 'open', instanceName });
    }

    // Get QR code from Evolution API
    const qrData = await getQrCode(instanceName);
    res.json({ state, instanceName, ...qrData });
  } catch (err: any) {
    console.error('[WhatsApp] /qrcode error:', err.message);
    res.status(502).json({ error: err.message });
  }
});

// POST /api/whatsapp/disconnect
// Logs out the WhatsApp session (phone disconnects) but keeps the instance slot.
router.post('/disconnect', async (req: Request, res: Response) => {
  const agentId = req.agentId!;
  try {
    const instanceName = await getAgentInstance(agentId);

    if (!instanceName) {
      return res.status(400).json({ error: 'No WhatsApp instance configured.' });
    }

    await logoutInstance(instanceName);

    await supabase
      .from('agents')
      .update({ whatsapp_connected_at: null })
      .eq('id', agentId);

    res.json({ ok: true });
  } catch (err: any) {
    console.error('[WhatsApp] /disconnect error:', err.message);
    res.status(502).json({ error: err.message });
  }
});

// DELETE /api/whatsapp/instance
// Deletes the Evolution API instance entirely and clears it from the agent record.
router.delete('/instance', async (req: Request, res: Response) => {
  const agentId = req.agentId!;
  try {
    const instanceName = await getAgentInstance(agentId);

    if (!instanceName) {
      return res.status(400).json({ error: 'No WhatsApp instance configured.' });
    }

    await deleteInstance(instanceName);

    await supabase
      .from('agents')
      .update({ whatsapp_instance_name: null, whatsapp_connected_at: null })
      .eq('id', agentId);

    res.json({ ok: true });
  } catch (err: any) {
    console.error('[WhatsApp] /instance delete error:', err.message);
    res.status(502).json({ error: err.message });
  }
});

export default router;
