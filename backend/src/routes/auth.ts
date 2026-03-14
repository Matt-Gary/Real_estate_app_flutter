import { Router, Request, Response } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { supabase } from '../services/supabase';

const router = Router();

// POST /api/auth/register
router.post('/register', async (req: Request, res: Response) => {
  const { email, password, name } = req.body;

  if (!email || !password || !name) {
    res.status(400).json({ error: 'email, password and name are required' });
    return;
  }
  if (password.length < 8) {
    res.status(400).json({ error: 'Password must be at least 8 characters' });
    return;
  }

  // Check if email already exists
  const { data: existing } = await supabase
    .from('agents')
    .select('id')
    .eq('email', email.toLowerCase())
    .maybeSingle();

  if (existing) {
    res.status(409).json({ error: 'An account with this email already exists' });
    return;
  }

  const password_hash = await bcrypt.hash(password, 12);

  const { data, error } = await supabase
    .from('agents')
    .insert({ email: email.toLowerCase(), password_hash, name })
    .select('id, email, name, created_at')
    .single();

  if (error) {
    res.status(500).json({ error: error.message });
    return;
  }

  const token = jwt.sign(
    { agentId: data.id, email: data.email },
    process.env.JWT_SECRET!,
    { expiresIn: '7d' }
  );

  res.status(201).json({ token, agent: data });
});

// POST /api/auth/login
router.post('/login', async (req: Request, res: Response) => {
  const { email, password } = req.body;

  if (!email || !password) {
    res.status(400).json({ error: 'email and password are required' });
    return;
  }

  const { data: agent, error } = await supabase
    .from('agents')
    .select('id, email, name, password_hash, created_at')
    .eq('email', email.toLowerCase())
    .maybeSingle();

  if (error || !agent) {
    res.status(401).json({ error: 'Invalid email or password' });
    return;
  }

  const valid = await bcrypt.compare(password, agent.password_hash);
  if (!valid) {
    res.status(401).json({ error: 'Invalid email or password' });
    return;
  }

  const token = jwt.sign(
    { agentId: agent.id, email: agent.email },
    process.env.JWT_SECRET!,
    { expiresIn: '7d' }
  );

  const { password_hash: _, ...safeAgent } = agent;
  res.json({ token, agent: safeAgent });
});

// GET /api/auth/me
router.get('/me', async (req: Request, res: Response) => {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    res.status(401).json({ error: 'Not authenticated' });
    return;
  }
  try {
    const payload: any = jwt.verify(header.slice(7), process.env.JWT_SECRET!);
    const { data, error } = await supabase
      .from('agents')
      .select('id, email, name, created_at')
      .eq('id', payload.agentId)
      .single();
    if (error || !data) { res.status(404).json({ error: 'Agent not found' }); return; }
    res.json({ agent: data });
  } catch {
    res.status(401).json({ error: 'Invalid token' });
  }
});

export default router;
