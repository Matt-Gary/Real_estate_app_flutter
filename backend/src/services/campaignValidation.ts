import {
  DAILY_LIMIT,
  isWithinSendWindow,
  SEND_WINDOW_START_HOUR,
  SEND_WINDOW_END_HOUR,
} from './rateLimits';

// The `{name}` placeholder is mandatory in every campaign template.
// Identical bulk messages are the single largest WhatsApp-ban risk —
// requiring per-recipient personalization is our cheapest mitigation.
const NAME_PLACEHOLDER = '{name}';

export interface ValidationError {
  field: string;
  code: string;
  message: string;
}

export function validateTemplateBody(body: unknown): ValidationError | null {
  if (typeof body !== 'string' || body.trim() === '') {
    return { field: 'templateBody', code: 'EMPTY', message: 'Mensagem da campanha é obrigatória' };
  }
  if (body.length > 4000) {
    return { field: 'templateBody', code: 'TOO_LONG', message: 'Mensagem deve ter no máximo 4000 caracteres' };
  }
  if (!body.includes(NAME_PLACEHOLDER)) {
    return {
      field: 'templateBody',
      code: 'MISSING_NAME_PLACEHOLDER',
      message: `A mensagem precisa conter o marcador ${NAME_PLACEHOLDER} para personalização`,
    };
  }
  return null;
}

export function validateDailyQuota(quota: unknown): ValidationError | null {
  if (typeof quota !== 'number' || !Number.isInteger(quota)) {
    return { field: 'dailyQuota', code: 'NOT_INTEGER', message: 'Quota diária precisa ser um número inteiro' };
  }
  if (quota < 1) {
    return { field: 'dailyQuota', code: 'TOO_LOW', message: 'Quota diária mínima é 1' };
  }
  if (quota > DAILY_LIMIT) {
    return {
      field: 'dailyQuota',
      code: 'EXCEEDS_AGENT_CAP',
      message: `Quota diária não pode ultrapassar o limite do agente (${DAILY_LIMIT})`,
    };
  }
  return null;
}

export function validateStartAt(startAtIso: unknown): ValidationError | null {
  if (typeof startAtIso !== 'string') {
    return { field: 'startAt', code: 'INVALID', message: 'Data de início precisa ser um timestamp ISO' };
  }
  const t = Date.parse(startAtIso);
  if (Number.isNaN(t)) {
    return { field: 'startAt', code: 'INVALID', message: 'Data de início inválida' };
  }
  // Reject if outside 08:00–20:00 APP_TZ window. The spreader will handle
  // "later today" → first valid slot, but we still reject obvious
  // mistakes (midnight launches) so the agent sees what's happening.
  if (!isWithinSendWindow(startAtIso)) {
    return {
      field: 'startAt',
      code: 'OUTSIDE_WINDOW',
      message: `Data de início precisa estar entre ${SEND_WINDOW_START_HOUR}:00 e ${SEND_WINDOW_END_HOUR}:00 (horário de São Paulo)`,
    };
  }
  return null;
}

export function validateName(name: unknown): ValidationError | null {
  if (typeof name !== 'string' || name.trim() === '') {
    return { field: 'name', code: 'EMPTY', message: 'Nome da campanha é obrigatório' };
  }
  if (name.length > 100) {
    return { field: 'name', code: 'TOO_LONG', message: 'Nome da campanha deve ter no máximo 100 caracteres' };
  }
  return null;
}
