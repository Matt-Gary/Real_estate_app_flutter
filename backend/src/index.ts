process.env.TZ = 'America/Sao_Paulo';
import dotenv from 'dotenv';
dotenv.config();

// Validate required env vars at startup — fail fast with a clear message
const REQUIRED_ENV = ['JWT_SECRET', 'SUPABASE_URL', 'SUPABASE_SERVICE_KEY'];
for (const key of REQUIRED_ENV) {
  if (!process.env[key]) {
    console.error(`[Startup] Missing required environment variable: ${key}`);
    process.exit(1);
  }
}

import express, { NextFunction, Request, Response } from 'express';
import cors from 'cors';
import { startScheduler, stopScheduler } from './services/scheduler';

import authRoutes         from './routes/auth';
import clientRoutes       from './routes/clients';
import messageRoutes      from './routes/messages';
import templateRoutes     from './routes/templates';
import dashboardRoutes    from './routes/dashboard';
import coldClientRoutes   from './routes/cold_clients';
import propertyLinkRoutes from './routes/property_links';
import whatsappRoutes     from './routes/whatsapp';
import webhookRoutes      from './routes/webhooks';

const app  = express();
const PORT = parseInt(process.env.PORT ?? '3000', 10);

if (isNaN(PORT)) {
  console.error('[Startup] Invalid PORT environment variable');
  process.exit(1);
}

app.use(cors());
app.use(express.json({ limit: '1mb' }));

// Routes
app.use('/api/auth',            authRoutes);
app.use('/api/webhooks',        webhookRoutes);   // mount BEFORE the broad '/api' router so webhooks skip JWT auth
app.use('/api/clients',         clientRoutes);
app.use('/api',                 messageRoutes);   // /api/clients/:id/messages
app.use('/api/templates',       templateRoutes);
app.use('/api/dashboard',       dashboardRoutes);
app.use('/api/cold-clients',    coldClientRoutes);
app.use('/api/property-links',  propertyLinkRoutes);
app.use('/api/whatsapp',        whatsappRoutes);

app.get('/health', (_req, res) => res.json({ ok: true }));

// Global error handler — catches any unhandled errors in async route handlers
// eslint-disable-next-line @typescript-eslint/no-unused-vars
app.use((err: any, _req: Request, res: Response, _next: NextFunction) => {
  console.error('[Unhandled error]', err);
  res.status(500).json({ error: 'Internal server error' });
});

const server = app.listen(PORT, () => {
  console.log(`Backend running on port ${PORT}`);
  startScheduler();
});

// Graceful shutdown — lets the scheduler finish in-flight work
function shutdown(signal: string) {
  console.log(`[Shutdown] Received ${signal}. Stopping scheduler and closing server.`);
  stopScheduler();
  server.close(() => {
    console.log('[Shutdown] Server closed.');
    process.exit(0);
  });
  // Force exit after 10 s if graceful shutdown hangs
  setTimeout(() => process.exit(1), 10_000).unref();
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT',  () => shutdown('SIGINT'));
