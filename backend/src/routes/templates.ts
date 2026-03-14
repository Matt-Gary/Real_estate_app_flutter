import { Router, Request, Response } from 'express';
import { supabase } from '../services/supabase';
import { requireAuth } from '../middleware/auth';

const router = Router();
router.use(requireAuth);

// GET /api/templates
router.get('/', async (_req: Request, res: Response) => {
  const { data, error } = await supabase
    .from('templates')
    .select('*')
    .order('seq');

  if (error) { res.status(500).json({ error: error.message }); return; }
  res.json(data);
});

export default router;
