import { Router, Request, Response } from 'express';
import { supabase } from '../services/supabase';
import { requireAuth } from '../middleware/auth';

const router = Router();
router.use(requireAuth);

// GET /api/templates — list agent's templates
router.get('/', async (req: Request, res: Response) => {
  const { data, error } = await supabase
    .from('agent_templates')
    .select('*')
    .eq('agent_id', req.agentId)
    .order('created_at');

  if (error) { res.status(500).json({ error: error.message }); return; }
  res.json(data);
});

// POST /api/templates — create a new template
router.post('/', async (req: Request, res: Response) => {
  const { name, body } = req.body;

  if (!name || typeof name !== 'string' || name.trim() === '') {
    res.status(400).json({ error: 'name is required' }); return;
  }
  if (!body || typeof body !== 'string' || body.trim() === '') {
    res.status(400).json({ error: 'body is required' }); return;
  }

  const { data, error } = await supabase
    .from('agent_templates')
    .insert({ agent_id: req.agentId, name: name.trim(), body: body.trim() })
    .select()
    .single();

  if (error) { res.status(500).json({ error: error.message }); return; }
  res.status(201).json(data);
});

// PUT /api/templates/:id — update name and/or body
router.put('/:id', async (req: Request, res: Response) => {
  const { id } = req.params;
  const { name, body } = req.body;

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

// DELETE /api/templates/:id
router.delete('/:id', async (req: Request, res: Response) => {
  const { id } = req.params;

  const { error } = await supabase
    .from('agent_templates')
    .delete()
    .eq('id', id)
    .eq('agent_id', req.agentId);   // ownership check

  if (error) { res.status(500).json({ error: error.message }); return; }
  res.json({ success: true });
});

export default router;
