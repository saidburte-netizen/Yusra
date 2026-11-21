// Creates an auth user and its profile. The service-role key is read from the
// Edge Function environment only; it is never bundled into the Flutter app.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders, errors, json } from '../_shared/http.ts';
import {
  isEmail,
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
const BODY_KEYS = ['email', 'full_name', 'role', 'branch_id'] as const;

type AdminClient = ReturnType<typeof createClient>;

interface Actor {
  role: string | null;
  is_active: boolean | null;
  branch_id: string | null;
}

async function writeAudit(admin: AdminClient, entry: Record<string, unknown>) {
  const { error } = await admin.from('audit_logs').insert(entry);
  if (error) console.error('admin-create-user: audit insert failed:', error.message);
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders(req) });
  }
  if (req.method !== 'POST') return errors.methodNotAllowed(req);

  try {
    const url = Deno.env.get('SUPABASE_URL');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
    if (!url || !serviceKey || !anonKey) {
      console.error('admin-create-user: Supabase environment is not configured');
      return errors.internal(req);
    }

    const authHeader = req.headers.get('Authorization');
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

    // Role is always re-read from profiles through the service role: JWT
    // metadata is client-supplied and must never be trusted for authorization.
    const admin = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: actorRow, error: actorError } = await admin
      .from('profiles')
      .select('role, is_active, branch_id')
      .eq('id', identity.user.id)
      .maybeSingle();
    if (actorError) {
      console.error('admin-create-user: profile lookup failed:', actorError.message);
      return errors.internal(req);
    }
    if (!actorRow) {
      return errors.notFound(req, 'Your staff profile was not found.');
    }
    const actor = actorRow as Actor;
    if (!actor.is_active) {
      return errors.forbidden(req, 'This account is inactive.');
    }
    if (actor.role !== 'super_admin' && actor.role !== 'admin') {
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

    const password = temporaryPassword();
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
      console.error('admin-create-user: Auth admin API failed with status', status);
      if (status === 409 || status === 422) {
        return errors.conflict(req, 'A user with that email already exists.');
      }
      return errors.internal(req);
    }
    const created = (await response.json()) as { id?: unknown };
    if (typeof created.id !== 'string' || created.id.length === 0) {
      console.error('admin-create-user: Auth admin API returned no user id');
      return errors.internal(req);
    }

    const { error: profileError } = await admin.from('profiles').upsert({
      id: created.id,
      email,
      full_name: fullName,
      role,
      branch_id: branchId,
      is_active: true,
    });
    if (profileError) {
      console.error('admin-create-user: profile upsert failed:', profileError.message);
      return errors.internal(req);
    }

    await writeAudit(admin, {
      user_id: identity.user.id,
      action: 'create_user',
      table_name: 'profiles',
      record_id: created.id,
      branch_id: branchId,
      old_data: null,
      new_data: { email, role, branch_id: branchId },
      created_at: new Date().toISOString(),
    });

    return json(req, { user_id: created.id, temporary_password: password });
  } catch (error) {
    console.error(
      'admin-create-user: unexpected error:',
      error instanceof Error ? error.message : String(error),
    );
    return errors.internal(req);
  }
});
