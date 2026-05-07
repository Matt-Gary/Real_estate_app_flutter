import { Router, Request, Response } from 'express';
import { supabase } from '../services/supabase';
import { requireAuth } from '../middleware/auth';

const router = Router();
router.use(requireAuth);

const HEX_COLOR = /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/;

function validateName(value: unknown): { ok: true; name: string } | { ok: false; error: string } {
  if (typeof value !== 'string') return { ok: false, error: 'name must be a string' };
  const trimmed = value.trim();
  if (trimmed === '') return { ok: false, error: 'name must be non-empty' };
  if (trimmed.length > 60) return { ok: false, error: 'name must be at most 60 characters' };
  return { ok: true, name: trimmed };
}

function validateColor(value: unknown): { ok: true; color: string | null } | { ok: false; error: string } {
  if (value === null || value === undefined) return { ok: true, color: null };
  if (typeof value !== 'string') return { ok: false, error: 'color must be a hex string or null' };
  if (!HEX_COLOR.test(value)) return { ok: false, error: 'color must match #RGB or #RRGGBB' };
  return { ok: true, color: value };
}

async function ownsClient(agentId: string, clientId: string): Promise<boolean> {
  const { data } = await supabase
    .from('clients')
    .select('id')
    .eq('id', clientId)
    .eq('agent_id', agentId)
    .maybeSingle();
  return !!data;
}

async function ownsLabel(agentId: string, labelId: string): Promise<boolean> {
  const { data } = await supabase
    .from('client_labels')
    .select('id')
    .eq('id', labelId)
    .eq('agent_id', agentId)
    .maybeSingle();
  return !!data;
}

// ────────────────────────────────────────────────────────────────────────────
// GET /api/labels — list agent's labels with assignment counts
// ────────────────────────────────────────────────────────────────────────────
router.get('/labels', async (req: Request, res: Response) => {
  const { data: labels, error } = await supabase
    .from('client_labels')
    .select('*')
    .eq('agent_id', req.agentId!)
    .order('name');

  if (error) { res.status(500).json({ error: error.message }); return; }

  const labelIds = (labels ?? []).map(l => l.id);
  let counts: Record<string, number> = {};
  if (labelIds.length > 0) {
    const { data: assignments, error: aerr } = await supabase
      .from('client_label_assignments')
      .select('label_id')
      .in('label_id', labelIds);
    if (aerr) { res.status(500).json({ error: aerr.message }); return; }
    counts = (assignments ?? []).reduce<Record<string, number>>((acc, row) => {
      acc[row.label_id] = (acc[row.label_id] ?? 0) + 1;
      return acc;
    }, {});
  }

  res.json((labels ?? []).map(l => ({ ...l, client_count: counts[l.id] ?? 0 })));
});

// ────────────────────────────────────────────────────────────────────────────
// POST /api/labels — create
// ────────────────────────────────────────────────────────────────────────────
router.post('/labels', async (req: Request, res: Response) => {
  const nameV = validateName(req.body?.name);
  if (!nameV.ok) { res.status(400).json({ error: nameV.error }); return; }
  const colorV = validateColor(req.body?.color);
  if (!colorV.ok) { res.status(400).json({ error: colorV.error }); return; }

  const { data, error } = await supabase
    .from('client_labels')
    .insert({ agent_id: req.agentId!, name: nameV.name, color: colorV.color })
    .select()
    .single();

  if (error) {
    // Unique violation (case-insensitive index) → 409
    if ((error as any).code === '23505') {
      res.status(409).json({ error: 'A label with this name already exists', code: 'NAME_TAKEN' });
      return;
    }
    res.status(500).json({ error: error.message });
    return;
  }
  res.status(201).json({ ...data, client_count: 0 });
});

// ────────────────────────────────────────────────────────────────────────────
// PATCH /api/labels/:id — rename / recolor
// ────────────────────────────────────────────────────────────────────────────
router.patch('/labels/:id', async (req: Request, res: Response) => {
  const updates: Record<string, unknown> = {};

  if (req.body?.name !== undefined) {
    const nameV = validateName(req.body.name);
    if (!nameV.ok) { res.status(400).json({ error: nameV.error }); return; }
    updates.name = nameV.name;
  }
  if (req.body?.color !== undefined) {
    const colorV = validateColor(req.body.color);
    if (!colorV.ok) { res.status(400).json({ error: colorV.error }); return; }
    updates.color = colorV.color;
  }

  if (Object.keys(updates).length === 0) {
    res.status(400).json({ error: 'Nothing to update' });
    return;
  }

  const { data, error } = await supabase
    .from('client_labels')
    .update(updates)
    .eq('id', req.params.id)
    .eq('agent_id', req.agentId!)
    .select()
    .maybeSingle();

  if (error) {
    if ((error as any).code === '23505') {
      res.status(409).json({ error: 'A label with this name already exists', code: 'NAME_TAKEN' });
      return;
    }
    res.status(500).json({ error: error.message });
    return;
  }
  if (!data) { res.status(404).json({ error: 'Label not found' }); return; }
  res.json(data);
});

// ────────────────────────────────────────────────────────────────────────────
// DELETE /api/labels/:id — also removes assignments via FK cascade
// ────────────────────────────────────────────────────────────────────────────
router.delete('/labels/:id', async (req: Request, res: Response) => {
  // Block deletion if a non-completed campaign still targets this label.
  const { data: blocking, error: cerr } = await supabase
    .from('campaigns')
    .select('id, name, status')
    .eq('agent_id', req.agentId!)
    .eq('label_id', req.params.id)
    .in('status', ['draft', 'scheduled', 'running', 'paused'])
    .limit(1);

  if (cerr) { res.status(500).json({ error: cerr.message }); return; }
  if (blocking && blocking.length > 0) {
    res.status(409).json({
      error: 'label_in_use',
      message: 'Cancel or finish the campaign that targets this label first.',
      campaign_id: blocking[0].id,
      campaign_name: blocking[0].name,
    });
    return;
  }

  const { error } = await supabase
    .from('client_labels')
    .delete()
    .eq('id', req.params.id)
    .eq('agent_id', req.agentId!);

  if (error) { res.status(500).json({ error: error.message }); return; }
  res.json({ ok: true });
});

// ────────────────────────────────────────────────────────────────────────────
// GET /api/labels/:id/clients — list clients carrying this label
// ────────────────────────────────────────────────────────────────────────────
router.get('/labels/:id/clients', async (req: Request, res: Response) => {
  if (!(await ownsLabel(req.agentId!, req.params.id))) {
    res.status(404).json({ error: 'Label not found' });
    return;
  }

  // Filter by agent_id at the DB level via inner join — never trust the embed
  // shape to keep cross-agent data out of the response.
  const { data, error } = await supabase
    .from('client_label_assignments')
    .select('clients!inner(*)')
    .eq('label_id', req.params.id)
    .eq('clients.agent_id', req.agentId!);

  if (error) {
    console.error('[GET /labels/:id/clients]', error);
    res.status(500).json({ error: 'Erro ao carregar clientes da etiqueta' });
    return;
  }

  const clients = (data ?? []).map((row: any) => row.clients).filter(Boolean);
  res.json(clients);
});

// ────────────────────────────────────────────────────────────────────────────
// GET /api/clients/:clientId/labels — labels currently on a client
// ────────────────────────────────────────────────────────────────────────────
router.get('/clients/:clientId/labels', async (req: Request, res: Response) => {
  if (!(await ownsClient(req.agentId!, req.params.clientId))) {
    res.status(404).json({ error: 'Client not found' });
    return;
  }

  const { data, error } = await supabase
    .from('client_label_assignments')
    .select('client_labels(*)')
    .eq('client_id', req.params.clientId);

  if (error) { res.status(500).json({ error: error.message }); return; }

  const labels = (data ?? [])
    .map((row: any) => row.client_labels)
    .filter((l: any) => l && l.agent_id === req.agentId);
  res.json(labels);
});

// ────────────────────────────────────────────────────────────────────────────
// POST /api/clients/:clientId/labels — replace label set for a client
// Body: { labelIds: string[] }
// ────────────────────────────────────────────────────────────────────────────
router.post('/clients/:clientId/labels', async (req: Request, res: Response) => {
  if (!(await ownsClient(req.agentId!, req.params.clientId))) {
    res.status(404).json({ error: 'Client not found' });
    return;
  }

  const incoming = req.body?.labelIds;
  if (!Array.isArray(incoming) || incoming.some(x => typeof x !== 'string')) {
    res.status(400).json({ error: 'labelIds must be an array of strings' });
    return;
  }
  const labelIds: string[] = Array.from(new Set(incoming as string[]));

  // Verify every incoming label belongs to this agent (prevents cross-agent attach).
  if (labelIds.length > 0) {
    const { data: owned, error: oerr } = await supabase
      .from('client_labels')
      .select('id')
      .eq('agent_id', req.agentId!)
      .in('id', labelIds);
    if (oerr) { res.status(500).json({ error: oerr.message }); return; }
    const ownedIds = new Set((owned ?? []).map(r => r.id));
    const stranger = labelIds.find(id => !ownedIds.has(id));
    if (stranger) {
      res.status(400).json({ error: `Label ${stranger} does not belong to this agent` });
      return;
    }
  }

  // Replace strategy: delete current assignments, then insert the new set.
  const { error: delErr } = await supabase
    .from('client_label_assignments')
    .delete()
    .eq('client_id', req.params.clientId);
  if (delErr) { res.status(500).json({ error: delErr.message }); return; }

  if (labelIds.length > 0) {
    const rows = labelIds.map(label_id => ({ client_id: req.params.clientId, label_id }));
    const { error: insErr } = await supabase
      .from('client_label_assignments')
      .insert(rows);
    if (insErr) { res.status(500).json({ error: insErr.message }); return; }
  }

  res.json({ ok: true, label_ids: labelIds });
});

export default router;
