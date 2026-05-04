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
    console.error('[register]', error);
    res.status(500).json({ error: 'Registration failed. Please try again.' });
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

  // Always run bcrypt.compare even when the user doesn't exist, so login latency
  // doesn't leak whether the email is registered (timing-attack mitigation).
  // The dummy hash is a real bcrypt hash of a value that will never match.
  const DUMMY_HASH = '$2b$10$CwTycUXWue0Thq9StjUM0uJ8.1Z9vN6g5o0X9tJ7Fz4y5wQ3wBgFa';
  const hashToCompare = (error || !agent) ? DUMMY_HASH : agent.password_hash;
  const valid = await bcrypt.compare(password, hashToCompare);

  if (error || !agent || !valid) {
    res.status(401).json({ error: 'Email ou senha inválidos' });
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

// POST /api/auth/reset-password
router.post('/reset-password', async (req: Request, res: Response) => {
  const { token, newPassword } = req.body;
  if (!token || !newPassword) { res.status(400).json({ error: 'Token and new password are required' }); return; }
  if (newPassword.length < 8) { res.status(400).json({ error: 'Password must be at least 8 characters' }); return; }

  // Atomically claim the token in a single UPDATE — prevents race condition where
  // two concurrent requests both read "unused" before either marks it used.
  const { data: record, error: claimError } = await supabase
    .from('password_reset_tokens')
    .update({ used_at: new Date().toISOString() })
    .eq('token', token)
    .is('used_at', null)
    .gt('expires_at', new Date().toISOString())
    .select('id, agent_id')
    .maybeSingle();

  if (claimError) {
    console.error('[reset-password]', claimError);
    res.status(500).json({ error: 'An error occurred. Please try again.' });
    return;
  }

  if (!record) {
    // Could be invalid token, already used, or expired — don't distinguish to avoid info leak
    res.status(400).json({ error: 'Invalid or expired reset token' });
    return;
  }

  const password_hash = await bcrypt.hash(newPassword, 12);

  const { error: updateError } = await supabase
    .from('agents')
    .update({ password_hash })
    .eq('id', record.agent_id);

  if (updateError) {
    console.error('[reset-password] password update failed', updateError);
    res.status(500).json({ error: 'Failed to update password. Please try again.' });
    return;
  }

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
