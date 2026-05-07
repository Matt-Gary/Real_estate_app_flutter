import { Router, Request, Response } from 'express';
import { supabase } from '../services/supabase';
import { requireAuth } from '../middleware/auth';

const router = Router();
router.use(requireAuth);

function validateSlot(value: unknown): { ok: true; slot: number | null } | { ok: false; error: string } {
  if (value === null) return { ok: true, slot: null };
  if (!Number.isInteger(value) || (value as number) < 1 || (value as number) > 5) {
    return { ok: false, error: 'default_slot must be an integer between 1 and 5, or null' };
  }
  return { ok: true, slot: value as number };
}

async function findSlotHolder(agentId: string, slot: number) {
  const { data } = await supabase
    .from('agent_templates')
    .select('id, name')
    .eq('agent_id', agentId)
    .eq('default_slot', slot)
    .maybeSingle();
  return data as { id: string; name: string } | null;
}

// GET /api/templates — list agent's templates (ordered by position, then created_at)
router.get('/', async (req: Request, res: Response) => {
  const { data, error } = await supabase
    .from('agent_templates')
    .select('*')
    .eq('agent_id', req.agentId)
    .order('position')
    .order('created_at');

  if (error) { res.status(500).json({ error: error.message }); return; }
  res.json(data);
});

// POST /api/templates — create a new template
router.post('/', async (req: Request, res: Response) => {
  const { name, body, default_slot } = req.body;

  if (!name || typeof name !== 'string' || name.trim() === '') {
    res.status(400).json({ error: 'name is required' }); return;
  }
  if (!body || typeof body !== 'string' || body.trim() === '') {
    res.status(400).json({ error: 'body is required' }); return;
  }

  let slot: number | null = null;
  if (default_slot !== undefined) {
    const v = validateSlot(default_slot);
    if (!v.ok) { res.status(400).json({ error: v.error }); return; }
    slot = v.slot;
  }

  if (slot !== null) {
    const holder = await findSlotHolder(req.agentId!, slot);
    if (holder) {
      res.status(409).json({
        error: 'slot_taken',
        conflicting_template_id: holder.id,
        conflicting_template_name: holder.name,
      });
      return;
    }
  }

  const { data: maxRow } = await supabase
    .from('agent_templates')
    .select('position')
    .eq('agent_id', req.agentId)
    .order('position', { ascending: false })
    .limit(1)
    .maybeSingle();
  const nextPosition = ((maxRow?.position as number | undefined) ?? 0) + 1;

  const { data, error } = await supabase
    .from('agent_templates')
    .insert({
      agent_id: req.agentId,
      name: name.trim(),
      body: body.trim(),
      default_slot: slot,
      position: nextPosition,
    })
    .select()
    .single();

  if (error) { res.status(500).json({ error: error.message }); return; }
  res.status(201).json(data);
});

// PUT /api/templates/reorder — persist new tile order
// Must be defined BEFORE PUT /:id so it isn't shadowed.
router.put('/reorder', async (req: Request, res: Response) => {
  const { ordered_ids } = req.body;
  if (!Array.isArray(ordered_ids) || ordered_ids.some((x) => typeof x !== 'string')) {
    res.status(400).json({ error: 'ordered_ids must be an array of strings' }); return;
  }

  const { data: existing, error: fetchErr } = await supabase
    .from('agent_templates')
    .select('id')
    .eq('agent_id', req.agentId);
  if (fetchErr) { res.status(500).json({ error: fetchErr.message }); return; }

  const existingIds = new Set((existing ?? []).map((r: { id: string }) => r.id));
  if (existingIds.size !== ordered_ids.length || !ordered_ids.every((id) => existingIds.has(id))) {
    res.status(400).json({ error: 'ordered_ids must be a permutation of the agent\'s template ids' }); return;
  }

  const updates = ordered_ids.map((id, index) =>
    supabase
      .from('agent_templates')
      .update({ position: index + 1 })
      .eq('id', id)
      .eq('agent_id', req.agentId)
  );
  const results = await Promise.all(updates);
  const failed = results.find((r) => r.error);
  if (failed?.error) { res.status(500).json({ error: failed.error.message }); return; }

  res.json({ ok: true });
});

// PUT /api/templates/:id — update name, body, and/or default_slot
router.put('/:id', async (req: Request, res: Response) => {
  const { id } = req.params;
  const { name, body, default_slot } = req.body;

  const updates: Record<string, unknown> = {};
  if (name !== undefined) {
    if (typeof name !== 'string' || name.trim() === '') {
      res.status(400).json({ error: 'name must be a non-empty string' }); return;
    }
    updates.name = name.trim();
  }
  if (body !== undefined) {
    if (typeof body !== 'string' || body.trim() === '') {
      res.status(400).json({ error: 'body must be a non-empty string' }); return;
    }
    updates.body = body.trim();
  }
  if (default_slot !== undefined) {
    const v = validateSlot(default_slot);
    if (!v.ok) { res.status(400).json({ error: v.error }); return; }

    if (v.slot !== null) {
      const holder = await findSlotHolder(req.agentId!, v.slot);
      if (holder && holder.id !== id) {
        res.status(409).json({
          error: 'slot_taken',
          conflicting_template_id: holder.id,
          conflicting_template_name: holder.name,
        });
        return;
      }
    }
    updates.default_slot = v.slot;
  }

  if (Object.keys(updates).length === 0) {
    res.status(400).json({ error: 'Nothing to update' }); return;
  }

  const { data, error } = await supabase
    .from('agent_templates')
    .update(updates)
    .eq('id', id)
    .eq('agent_id', req.agentId)   // ownership check
    .select()
    .single();

  if (error) { res.status(500).json({ error: error.message }); return; }
  if (!data) { res.status(404).json({ error: 'Template not found' }); return; }
  res.json(data);
});

// POST /api/templates/:id/reassign-slot — assign default_slot, swapping if needed
router.post('/:id/reassign-slot', async (req: Request, res: Response) => {
  const { id } = req.params;
  const { default_slot, force } = req.body;

  const v = validateSlot(default_slot);
  if (!v.ok) { res.status(400).json({ error: v.error }); return; }
  const slot = v.slot;

  // Verify the target template belongs to this agent
  const { data: target } = await supabase
    .from('agent_templates')
    .select('id')
    .eq('id', id)
    .eq('agent_id', req.agentId)
    .maybeSingle();
  if (!target) { res.status(404).json({ error: 'Template not found' }); return; }

  let cleared: { id: string } | null = null;
  if (slot !== null) {
    const holder = await findSlotHolder(req.agentId!, slot);
    if (holder && holder.id !== id) {
      if (!force) {
        res.status(409).json({
          error: 'slot_taken',
          conflicting_template_id: holder.id,
          conflicting_template_name: holder.name,
        });
        return;
      }
      const { error: clearErr } = await supabase
        .from('agent_templates')
        .update({ default_slot: null })
        .eq('id', holder.id)
        .eq('agent_id', req.agentId);
      if (clearErr) { res.status(500).json({ error: clearErr.message }); return; }
      cleared = { id: holder.id };
    }
  }

  const { data: updated, error: setErr } = await supabase
    .from('agent_templates')
    .update({ default_slot: slot })
    .eq('id', id)
    .eq('agent_id', req.agentId)
    .select()
    .single();
  if (setErr) { res.status(500).json({ error: setErr.message }); return; }

  res.json({ updated, cleared });
});

// DELETE /api/templates/:id
router.delete('/:id', async (req: Request, res: Response) => {
  const { id } = req.params;

  const { error } = await supabase
    .from('agent_templates')
    .delete()
    .eq('id', id)
    .eq('agent_id', req.agentId);   // ownership check

  if (error) { res.status(500).json({ error: error.message }); return; }
  res.json({ ok: true });
});

export default router;
