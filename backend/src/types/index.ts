export interface Agent {
  id: string;
  email: string;
  name: string;
  created_at: string;
}

export interface Client {
  id: string;
  agent_id: string;
  name: string;
  phone_number: string;
  email: string | null;
  property_link: string | null;
  is_active: boolean;
  replied_at: string | null;
  created_at: string;
  notes: string | null;
}

export interface FollowUpMessage {
  id: string;
  client_id: string;
  seq: number;
  body: string;
  send_at: string;
  sent_at: string | null;
  status: 'pending' | 'sent' | 'failed' | 'cancelled';
  error_detail: string | null;
}

export interface Template {
  id: number;
  seq: number;
  body: string;
}

export interface JwtPayload {
  agentId: string;
  email: string;
}

declare global {
  namespace Express {
    interface Request {
      agentId?: string;
      agentEmail?: string;
    }
  }
}
