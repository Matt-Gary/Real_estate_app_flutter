import { Router, Request, Response } from 'express';
import { supabase } from '../services/supabase';
import { requireAuth } from '../middleware/auth';

const router = Router();
router.use(requireAuth);

// GET /api/property-links
router.get('/', async (req: Request, res: Response) => {
  const { data, error } = await supabase
    .from('property_links')
    .select('*')
    .eq('agent_id', req.agentId!)
    .order('created_at', { ascending: false });

  if (error) { res.status(500).json({ error: error.message }); return; }
  res.json(data ?? []);
});

// POST /api/property-links
router.post('/', async (req: Request, res: Response) => {
  const { link, description } = req.body;

  if (!link || !description) {
    res.status(400).json({ error: 'link and description are required' });
    return;
  }

  const { data, error } = await supabase
    .from('property_links')
    .insert({ agent_id: req.agentId!, link, description })
    .select()
    .single();

  if (error) { res.status(500).json({ error: error.message }); return; }
  res.status(201).json(data);
});

// PUT /api/property-links/:id
router.put('/:id', async (req: Request, res: Response) => {
  const { link, description } = req.body;

  const { data: existing } = await supabase
    .from('property_links')
    .select('id')
    .eq('id', req.params.id)
    .eq('agent_id', req.agentId!)
    .maybeSingle();

  if (!existing) { res.status(404).json({ error: 'Property link not found' }); return; }

  const updates: Record<string, any> = {};
  if (link        !== undefined) updates.link        = link;
  if (description !== undefined) updates.description = description;

  const { data, error } = await supabase
    .from('property_links')
    .update(updates)
    .eq('id', req.params.id)
    .select()
    .single();

  if (error) { res.status(500).json({ error: error.message }); return; }
  res.json(data);
});

// DELETE /api/property-links/:id
router.delete('/:id', async (req: Request, res: Response) => {
  const { data: existing } = await supabase
    .from('property_links')
    .select('id')
    .eq('id', req.params.id)
    .eq('agent_id', req.agentId!)
    .maybeSingle();

  if (!existing) { res.status(404).json({ error: 'Property link not found' }); return; }

  const { error } = await supabase
    .from('property_links')
    .delete()
    .eq('id', req.params.id);

  if (error) { res.status(500).json({ error: error.message }); return; }
  res.json({ ok: true });
});

export default router;
