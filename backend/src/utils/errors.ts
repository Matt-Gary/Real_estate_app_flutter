import type { Response } from 'express';

/**
 * Map a Supabase / Postgres error into a sanitized PT-BR user message.
 *
 * Why: never return `error.message` directly — it can include schema names,
 * constraint names, or SQL snippets, which leaks internals and is unreadable
 * to non-technical users. Log the raw error server-side for debugging,
 * return a friendly Portuguese message to the client.
 *
 * Usage:
 *   if (error) return sendDbError(res, error, '[POST /clients]');
 */
export function sendDbError(
  res: Response,
  error: unknown,
  contextTag: string,
  status = 500,
  userMessage = 'Erro interno ao processar a solicitação. Tente novamente.',
): void {
  console.error(contextTag, error);
  res.status(status).json({ error: userMessage });
}

/**
 * Standard 404 with a Portuguese message.
 */
export function sendNotFound(res: Response, what: string = 'Recurso'): void {
  res.status(404).json({ error: `${what} não encontrado` });
}

/**
 * Standard 400 validation error with a Portuguese message.
 */
export function sendValidation(res: Response, message: string, code?: string): void {
  res.status(400).json({ error: message, ...(code ? { code } : {}) });
}
