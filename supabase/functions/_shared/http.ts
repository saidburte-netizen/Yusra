// Shared CORS handling and typed JSON responses for the admin Edge Functions.
// APP_ORIGIN is a comma-separated allowlist. When it is unset we fall back to
// local development origins plus the configured Supabase URL origin.

export type ErrorCode =
  | 'bad_request'
  | 'unauthenticated'
  | 'forbidden'
  | 'not_found'
  | 'validation_error'
  | 'conflict'
  | 'method_not_allowed'
  | 'internal_error';

export interface ApiErrorBody {
  error: { code: ErrorCode; message: string };
}

const DEV_ORIGINS = [
  'http://localhost:3000',
  'http://localhost:5173',
  'http://127.0.0.1:3000',
  'http://127.0.0.1:5173',
];

function allowedOrigins(): string[] {
  const configured = (Deno.env.get('APP_ORIGIN') ?? '')
    .split(',')
    .map((value) => value.trim())
    .filter((value) => value.length > 0);
  if (configured.length > 0) return configured;

  const fallback = [...DEV_ORIGINS];
  const url = Deno.env.get('SUPABASE_URL');
  if (url) {
    try {
      fallback.push(new URL(url).origin);
    } catch {
      // A malformed SUPABASE_URL is caught by the caller configuration check.
    }
  }
  return fallback;
}

function isAllowed(origin: string, allowed: string[]): boolean {
  return allowed.some((candidate) =>
    candidate.endsWith('*')
      ? origin.startsWith(candidate.slice(0, -1))
      : candidate === origin
  );
}

export function corsHeaders(req: Request): HeadersInit {
  const allowed = allowedOrigins();
  const origin = req.headers.get('origin');
  // Never reflect an arbitrary Origin: unmatched requests get the first
  // configured (or fallback) origin and the browser blocks the response.
  const allowOrigin = origin && isAllowed(origin, allowed) ? origin : allowed[0];
  return {
    'Access-Control-Allow-Origin': allowOrigin,
    'Access-Control-Allow-Headers':
      'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin',
  };
}

export function json(req: Request, body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(req),
      'Content-Type': 'application/json; charset=utf-8',
    },
  });
}

export function apiError(
  req: Request,
  code: ErrorCode,
  message: string,
  status: number,
): Response {
  const body: ApiErrorBody = { error: { code, message } };
  return json(req, body, status);
}

// All messages are static: upstream error.message values are logged on the
// server only and never leak through these helpers.
export const errors = {
  badRequest: (req: Request, message = 'The request could not be read.') =>
    apiError(req, 'bad_request', message, 400),
  unauthenticated: (req: Request, message = 'Please sign in again.') =>
    apiError(req, 'unauthenticated', message, 401),
  forbidden: (
    req: Request,
    message = 'You do not have permission to do that.',
  ) => apiError(req, 'forbidden', message, 403),
  notFound: (req: Request, message = 'The requested record was not found.') =>
    apiError(req, 'not_found', message, 404),
  validation: (req: Request, message: string) =>
    apiError(req, 'validation_error', message, 422),
  conflict: (
    req: Request,
    message = 'That record already exists. Please choose different details.',
  ) => apiError(req, 'conflict', message, 409),
  methodNotAllowed: (req: Request) =>
    apiError(req, 'method_not_allowed', 'Use POST for this request.', 405),
  internal: (
    req: Request,
    message = 'Something went wrong. Please try again.',
  ) => apiError(req, 'internal_error', message, 500),
};
