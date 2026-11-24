// Creates an auth user and its profile. The service-role key is read from the
// Edge Function environment only; it is never bundled into the Flutter app.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { errors, json, missingSecrets, preflight } from '../_shared/http.ts';
import {
  isAdminRole,
  isEmail,
  jwtAppRole,
  optionalUuid,
  readJsonObject,
  requiredString,
  temporaryPassword,
  ValidationError,
} from '../_shared/validate.ts';

const ALLOWED_ROLES = [
  'super_admin',
  'admin',
  'pharmacist',
  'cashier',
  'store_keeper',
  'accountant',
] as const;
type AllowedRole = (typeof ALLOWED_ROLES)[number];
const BODY_KEYS = [
  'email',
  'full_name',
  'role',
  'branch_id',
  'phone',
  'monthly_salary',
  'hiring_date',
] as const;

/** Optional phone: text, at most 30 characters; blank becomes null. */
function optionalPhone(value: unknown): string | null {
  if (value === undefined || value === null || value === '') return null;
  if (typeof value !== 'string') {
    throw new ValidationError('phone must be text.');
  }
  const phone = value.trim();
  if (phone.length === 0) return null;
  if (phone.length > 30) {
    throw new ValidationError('phone is too long (at most 30 characters).');
  }
  return phone;
}

/** Optional monthly salary: a non-negative finite number; blank becomes null. */
function optionalSalary(value: unknown): number | null {
  if (value === undefined || value === null || value === '') return null;
  const salary = typeof value === 'string' && value.trim() !== ''
    ? Number(value)
    : value;
  if (typeof salary !== 'number' || !Number.isFinite(salary) || salary < 0) {
    throw new ValidationError('monthly_salary must be a number of 0 or more.');
  }
  return salary;
}

/** Optional hiring date, strictly YYYY-MM-DD and a real calendar date. */
function optionalHiringDate(value: unknown): string | null {
  if (value === undefined || value === null || value === '') return null;
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new ValidationError('hiring_date must be in YYYY-MM-DD format.');
  }
  const [year, month, day] = value.split('-').map(Number);
  const parsed = new Date(Date.UTC(year, month - 1, day));
  if (
    parsed.getUTCFullYear() !== year ||
    parsed.getUTCMonth() !== month - 1 ||
    parsed.getUTCDate() !== day
  ) {
    throw new ValidationError('hiring_date is not a valid date.');
  }
  return value;
}

type AdminClient = ReturnType<typeof createClient>;

interface Actor {
  role: string | null;
  is_active: boolean | null;
  branch_id: string | null;
}

type CreateStage =
  | 'profile_lookup'
  | 'branch_lookup'
  | 'auth_create'
  | 'auth_no_id'
  | 'profile_save'
  | 'unexpected';

function limitText(value: string, max = 200): string {
  return value.length <= max ? value : `${value.slice(0, max - 3)}...`;
}

/** Removes known secrets and token-shaped values from any server detail. */
function redactSecrets(value: string, secrets: string[]): string {
  let result = value;
  for (const secret of secrets) {
    if (secret) result = result.split(secret).join('[redacted]');
  }
  return result
    .replace(/\bBearer\s+[A-Za-z0-9._~+/=-]+/gi, 'Bearer [redacted]')
    .replace(/\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/g, '[redacted]')
    .replace(
      /("(?:access_token|refresh_token|apikey|service_role|service_key|token)"\s*:\s*")[^"]*(")/gi,
      '$1[redacted]$2',
    );
}

/** One safe, single-line, truncated fragment for an admin-facing error. */
function safeDetail(value: unknown, secrets: string[]): string {
  const raw = value == null ? '' : String(value);
  const clean = redactSecrets(raw, secrets).replace(/\s+/g, ' ').trim();
  return limitText(clean || '<empty>');
}

function stageMessage(stage: CreateStage, detail: string): string {
  return `Create user failed at ${stage}: ${detail}`;
}

async function writeAudit(admin: unknown, entry: Record<string, unknown>) {
  // The Supabase client's generated table types differ between releases, so
  // keep the audit helper generic and let the client validate at runtime.
  const client = admin as AdminClient;
  const { error } = await client.from('audit_logs').insert([entry] as never);
  if (error) console.error('admin-create-user: audit insert failed:', error.message);
}

Deno.serve(async (req: Request): Promise<Response> => {
  const preflightResponse = preflight(req);
  if (preflightResponse) return preflightResponse;
  if (req.method !== 'POST') return errors.methodNotAllowed(req);

  // Populated after secrets are read so unexpected-error details can be
  // redacted before they reach the admin or the logs.
  const sensitiveValues: string[] = [];

  try {
    const missing = missingSecrets([
      'SUPABASE_URL',
      'SUPABASE_SERVICE_ROLE_KEY',
      'SUPABASE_ANON_KEY',
    ]);
    if (missing.length > 0) {
      // Names only: the values (which may be secrets) are never logged/echoed.
      console.error(
        'admin-create-user: missing Edge Function configuration:',
        missing.join(', '),
      );
      return errors.internal(
        req,
        `User creation is not configured on the server. Missing secrets: ${missing.join(', ')}. Ask the administrator to set them.`,
      );
    }
    // Checked above; the non-null assertions document that invariant.
    const url = Deno.env.get('SUPABASE_URL')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
    sensitiveValues.push(serviceKey, anonKey);

    const authHeader = req.headers.get('Authorization');
    if (authHeader) sensitiveValues.push(authHeader);
    if (!authHeader || !/^Bearer\s+\S+$/i.test(authHeader)) {
      return errors.unauthenticated(req);
    }

    // Verify the caller with their own JWT (anon key + caller Authorization).
    const caller = createClient(url, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: identity, error: identityError } = await caller.auth.getUser();
    if (identityError || !identity?.user) return errors.unauthenticated(req);

    // The JWT was verified against the Auth server by getUser(); its
    // app_metadata role is server-issued, not caller-controlled. Reject tokens
    // that explicitly carry a non-admin role even before the profile lookup.
    const tokenRole = jwtAppRole(identity.user);
    if (tokenRole !== null && !isAdminRole(tokenRole)) {
      return errors.forbidden(req);
    }

    // The profiles row remains the authoritative role source; it is re-read
    // through the service role so stale/edited client metadata cannot grant
    // access on its own.
    const admin = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: actorRow, error: actorError } = await admin
      .from('profiles')
      .select('role, is_active, branch_id')
      .eq('id', identity.user.id)
      .maybeSingle();
    if (actorError) {
      const detail = safeDetail(actorError.message, sensitiveValues);
      console.error('admin-create-user:', stageMessage('profile_lookup', detail));
      return errors.internal(req, stageMessage('profile_lookup', detail));
    }
    if (!actorRow) {
      return errors.notFound(req, 'Your staff profile was not found.');
    }
    const actor = actorRow as Actor;
    if (!actor.is_active) {
      return errors.forbidden(req, 'This account is inactive.');
    }
    if (!isAdminRole(actor.role)) {
      return errors.forbidden(req);
    }

    let body: Record<string, unknown>;
    try {
      body = await readJsonObject(req, BODY_KEYS);
    } catch (error) {
      if (error instanceof ValidationError) return errors.validation(req, error.message);
      return errors.badRequest(req);
    }

    let email: string;
    let fullName: string;
    let role: AllowedRole;
    let branchId: string | null;
    let phone: string | null;
    let monthlySalary: number | null;
    let hiringDate: string | null;
    try {
      email = requiredString(body.email, 'email', 254).toLowerCase();
      if (!isEmail(email)) throw new ValidationError('Enter a valid email address.');
      fullName = requiredString(body.full_name, 'full_name', 120);
      if (
        typeof body.role !== 'string' ||
        !(ALLOWED_ROLES as readonly string[]).includes(body.role)
      ) {
        throw new ValidationError('Select a valid role.');
      }
      role = body.role as AllowedRole;
      branchId = optionalUuid(body.branch_id, 'branch_id') ?? actor.branch_id ?? null;
      phone = optionalPhone(body.phone);
      monthlySalary = optionalSalary(body.monthly_salary);
      hiringDate = optionalHiringDate(body.hiring_date);
    } catch (error) {
      if (error instanceof ValidationError) return errors.validation(req, error.message);
      return errors.validation(req, 'The submitted details are not valid.');
    }

    if (role === 'super_admin' && actor.role !== 'super_admin') {
      return errors.forbidden(req, 'Only a super admin can create another super admin.');
    }
    if (
      actor.role !== 'super_admin' &&
      (!actor.branch_id || branchId !== actor.branch_id)
    ) {
      return errors.forbidden(req, 'You can only create users in your own branch.');
    }

    // Fail with a typed validation error instead of an opaque 500 from the
    // profiles FK if the requested branch does not exist.
    if (branchId) {
      const { data: branch, error: branchError } = await admin
        .from('branches')
        .select('id')
        .eq('id', branchId)
        .maybeSingle();
      if (branchError) {
        const detail = safeDetail(branchError.message, sensitiveValues);
        console.error('admin-create-user:', stageMessage('branch_lookup', detail));
        return errors.internal(req, stageMessage('branch_lookup', detail));
      }
      if (!branch) {
        return errors.validation(req, 'The selected branch does not exist.');
      }
    }

    const password = temporaryPassword();
    sensitiveValues.push(password);
    const response = await fetch(`${url}/auth/v1/admin/users`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${serviceKey}`,
        apikey: serviceKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        email,
        password,
        email_confirm: true,
        // handle_new_user reads role and branch_id from raw_app_meta_data.
        app_metadata: { role, branch_id: branchId },
        user_metadata: { full_name: fullName },
      }),
    });
    if (!response.ok) {
      const status = response.status;
      const bodyText = await response.text().catch(() => '');
      let authCode: string | undefined;
      let authMessage: string | undefined;
      try {
        const parsed = JSON.parse(bodyText) as Record<string, unknown>;
        const nestedError = parsed.error;
        authCode = typeof parsed.code === 'string'
          ? parsed.code
          : nestedError && typeof nestedError === 'object' && 'code' in nestedError &&
              typeof (nestedError as { code?: unknown }).code === 'string'
            ? (nestedError as { code: string }).code
            : undefined;
        authMessage = typeof parsed.message === 'string'
          ? parsed.message
          : typeof parsed.msg === 'string'
            ? parsed.msg
            : nestedError && typeof nestedError === 'object' && 'message' in nestedError &&
                typeof (nestedError as { message?: unknown }).message === 'string'
              ? (nestedError as { message: string }).message
              : undefined;
      } catch {
        // Keep the raw body text below; some Auth versions return plain text.
      }
      const combined = `${authCode ?? ''} ${authMessage ?? ''} ${bodyText}`;
      const weakPassword = status === 422 &&
        (authCode === 'weak_password' || /weak[_ -]?password/i.test(combined));
      const emailExists = status === 409 ||
        authCode === 'email_exists' ||
        authCode === 'email_address_exists' ||
        /\b(email|user)\b.*\b(already|exists|registered|in use)\b/i.test(combined);
      if (weakPassword) {
        const detail = safeDetail(authMessage ?? bodyText, sensitiveValues);
        console.error('admin-create-user:', stageMessage('auth_create', detail));
        return errors.validation(req, detail);
      }
      if (emailExists) {
        return errors.conflict(req, 'A user with that email already exists.');
      }
      const underlying = safeDetail(
        authMessage ?? bodyText ?? '<empty>',
        sensitiveValues,
      );
      const detail = `HTTP ${status}: ${underlying}; body: ${safeDetail(bodyText, sensitiveValues)}`;
      console.error('admin-create-user:', stageMessage('auth_create', detail));
      return errors.internal(req, stageMessage('auth_create', detail));
    }
    const created = (await response.json()) as { id?: unknown };
    if (typeof created.id !== 'string' || created.id.length === 0) {
      const detail = 'Auth admin API returned no user id.';
      console.error('admin-create-user:', stageMessage('auth_no_id', detail));
      return errors.internal(req, stageMessage('auth_no_id', detail));
    }

    const { error: profileError } = await admin.from('profiles').upsert({
      id: created.id,
      email,
      full_name: fullName,
      role,
      branch_id: branchId,
      phone,
      monthly_salary: monthlySalary,
      hiring_date: hiringDate,
      is_active: true,
    });
    if (profileError) {
      const detail = safeDetail(profileError.message, sensitiveValues);
      console.error('admin-create-user:', stageMessage('profile_save', detail));
      return errors.internal(req, stageMessage('profile_save', detail));
    }

    await writeAudit(admin, {
      user_id: identity.user.id,
      action: 'create_user',
      table_name: 'profiles',
      record_id: created.id,
      branch_id: branchId,
      old_data: null,
      new_data: { email, role, branch_id: branchId, phone, monthly_salary: monthlySalary, hiring_date: hiringDate },
      created_at: new Date().toISOString(),
    });

    return json(req, { user_id: created.id, temporary_password: password });
  } catch (error) {
    const detail = safeDetail(
      error instanceof Error ? error.message : String(error),
      sensitiveValues,
    );
    console.error('admin-create-user:', stageMessage('unexpected', detail));
    return errors.internal(req, stageMessage('unexpected', detail));
  }
});
