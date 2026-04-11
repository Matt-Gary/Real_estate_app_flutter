process.env.TZ = 'America/Sao_Paulo';
import dotenv from 'dotenv';
dotenv.config();

import express from 'express';
import cors from 'cors';
import { startScheduler } from './services/scheduler';

import authRoutes         from './routes/auth';
import clientRoutes       from './routes/clients';
import messageRoutes      from './routes/messages';
import templateRoutes     from './routes/templates';
import dashboardRoutes    from './routes/dashboard';
import coldClientRoutes   from './routes/cold_clients';
import propertyLinkRoutes from './routes/property_links';

const app  = express();
const PORT = parseInt(process.env.PORT ?? '3000', 10);

app.use(cors());
app.use(express.json());

// Routes
app.use('/api/auth',            authRoutes);
app.use('/api/clients',         clientRoutes);
app.use('/api',                 messageRoutes);   // /api/clients/:id/messages
app.use('/api/templates',       templateRoutes);
app.use('/api/dashboard',       dashboardRoutes);
app.use('/api/cold-clients',    coldClientRoutes);
app.use('/api/property-links',  propertyLinkRoutes);

app.get('/health', (_req, res) => res.json({ ok: true }));

app.listen(PORT, () => {
  console.log(`Backend running on port ${PORT}`);
  startScheduler();
});
