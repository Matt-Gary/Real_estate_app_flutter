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
// POST /api/auth/forgot-password
router.post('/forgot-password', async (req: Request, res: Response) => {
  const { email } = req.body;
  if (!email) { res.status(400).json({ error: 'Email is required' }); return; }

  const { data: agent } = await supabase
    .from('agents')
    .select('id, email')
    .eq('email', email.toLowerCase())
    .maybeSingle();

  // Always return 200 to avoid email enumeration
  if (!agent) { res.json({ message: 'If that email exists, a reset link was sent.' }); return; }

  // Invalidate any previous tokens for this agent
  await supabase
    .from('password_reset_tokens')
    .delete()
    .eq('agent_id', agent.id)
    .is('used_at', null);

  const crypto = await import('crypto');
  const token = crypto.randomBytes(32).toString('hex');
  const expires_at = new Date(Date.now() + 60 * 60 * 1000).toISOString(); // 1 hour

  await supabase.from('password_reset_tokens').insert({
    agent_id: agent.id,
    token,
    expires_at,
  });

  const resetUrl = `${process.env.APP_URL}/reset-password?token=${token}`;
  
  try {
    const { sendPasswordResetEmail } = await import('../services/mailer');
    await sendPasswordResetEmail(agent.email, resetUrl);
  } catch (e) {
    console.error('Email send failed:', e);
    res.status(500).json({ error: 'Failed to send email' });
    return;
  }

  res.json({ message: 'If that email exists, a reset link was sent.' });
});

// POST /api/auth/reset-passwordd
router.post('/reset-password', async (req: Request, res: Response) => {
  const { token, newPassword } = req.body;
  if (!token || !newPassword) { res.status(400).json({ error: 'Token and new password are required' }); return; }
  if (newPassword.length < 8) { res.status(400).json({ error: 'Password must be at least 8 characters' }); return; }

  const { data: record } = await supabase
    .from('password_reset_tokens')
    .select('id, agent_id, expires_at, used_at')
    .eq('token', token)
    .maybeSingle();

  if (!record) { res.status(400).json({ error: 'Invalid or expired reset token' }); return; }
  if (record.used_at) { res.status(400).json({ error: 'This reset link has already been used' }); return; }
  if (new Date(record.expires_at) < new Date()) { res.status(400).json({ error: 'Reset link has expired' }); return; }

  const password_hash = await bcrypt.hash(newPassword, 12);

  await supabase.from('agents').update({ password_hash }).eq('id', record.agent_id);

  // Mark token as used
  await supabase.from('password_reset_tokens').update({ used_at: new Date().toISOString() }).eq('id', record.id);

  res.json({ message: 'Password updated successfully' });
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
