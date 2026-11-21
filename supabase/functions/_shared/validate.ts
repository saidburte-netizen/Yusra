// Input validation and password generation shared by the admin functions.

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const MAX_BODY_BYTES = 16_384;

export class ValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ValidationError';
  }
}

export function isUuid(value: unknown): value is string {
  return typeof value === 'string' && value.length === 36 && UUID_RE.test(value);
}

export function isEmail(value: string): boolean {
  return value.length <= 254 && EMAIL_RE.test(value);
}

/** Parse a bounded JSON object and reject arrays, scalars and unknown keys. */
export async function readJsonObject(
  req: Request,
  allowedKeys: readonly string[],
): Promise<Record<string, unknown>> {
  const raw = await req.text();
  if (raw.trim().length === 0) {
    throw new ValidationError('A JSON body is required.');
  }
  if (raw.length > MAX_BODY_BYTES) {
    throw new ValidationError('The request body is too large.');
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new ValidationError('The request body is not valid JSON.');
  }
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new ValidationError('The request body must be a JSON object.');
  }

  const body = parsed as Record<string, unknown>;
  const unknownKeys = Object.keys(body).filter((key) => !allowedKeys.includes(key));
  if (unknownKeys.length > 0) {
    throw new ValidationError(`Unknown field(s): ${unknownKeys.join(', ')}.`);
  }
  return body;
}

export function requiredString(
  value: unknown,
  field: string,
  maxLength: number,
): string {
  if (typeof value !== 'string') {
    throw new ValidationError(`${field} must be text.`);
  }
  const trimmed = value.trim();
  if (trimmed.length === 0) {
    throw new ValidationError(`${field} is required.`);
  }
  if (trimmed.length > maxLength) {
    throw new ValidationError(
      `${field} is too long (at most ${maxLength} characters).`,
    );
  }
  return trimmed;
}

export function requiredUuid(value: unknown, field: string): string {
  if (!isUuid(value)) {
    throw new ValidationError(`${field} must be a valid UUID.`);
  }
  return value;
}

export function optionalUuid(value: unknown, field: string): string | null {
  if (value === undefined || value === null || value === '') return null;
  return requiredUuid(value, field);
}

// Ambiguous characters (0/O, 1/l/I) are omitted. Sampling is rejection-based
// so every character is uniformly drawn from the alphabet (no modulo bias).
const PASSWORD_ALPHABET =
  'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%';
const PASSWORD_LENGTH = 14;
const SAMPLE_LIMIT =
  Math.floor(256 / PASSWORD_ALPHABET.length) * PASSWORD_ALPHABET.length;

function randomCharacters(count: number): Uint8Array {
  const result = new Uint8Array(count);
  let filled = 0;
  while (filled < count) {
    const batch = new Uint8Array((count - filled) * 2);
    crypto.getRandomValues(batch);
    for (const byte of batch) {
      if (byte < SAMPLE_LIMIT && filled < count) result[filled++] = byte;
    }
  }
  return result;
}

function hasAllCharacterClasses(password: string): boolean {
  return /[A-Z]/.test(password) && /[a-z]/.test(password) &&
    /[0-9]/.test(password) && /[!@#$%]/.test(password);
}

/** Generate a 14-character temporary password with uniform rejection sampling. */
export function temporaryPassword(): string {
  for (let attempt = 0; attempt < 64; attempt++) {
    let password = '';
    for (const byte of randomCharacters(PASSWORD_LENGTH)) {
      password += PASSWORD_ALPHABET[byte % PASSWORD_ALPHABET.length];
    }
    if (hasAllCharacterClasses(password)) return password;
  }
  // Statistically unreachable, but never return a weak password.
  throw new Error('Temporary password generation failed');
}
