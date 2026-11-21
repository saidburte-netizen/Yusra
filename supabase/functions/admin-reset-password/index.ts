// Issues a new temporary password for a user. Uses the service-role key only
// inside this Edge Function; the Flutter app never holds it.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders, errors, json } from '../_shared/http.ts';
import {
  readJsonObject,
  requiredString,
  requiredUuid,
  temporaryPassword,
  ValidationError,
} from '../_shared/validate.ts';

const BODY_KEYS = ['user_id'] as const;

type AdminClient = ReturnType<typeof createClient>;

interface Profile {
  role: string | null;
  is_active: boolean | null;
  branch_id: string | null;
}

async function writeAudit(admin: AdminClient, entry: Record<string, unknown>) {
  const { error } = await admin.from('audit_logs').insert(entry);
  if (error) {
    console.error('admin-reset-password: audit insert failed:', error.message);
  }
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
      console.error('admin-reset-password: Supabase environment is not configured');
      return errors.internal(req);
    }

    const authHeader = req.headers.get('Authorization');
    if (!authHeader || !/^Bearer\s+\S+$/i.test(authHeader)) {
      return errors.unauthenticated(req);
    }

    const caller = createClient(url, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: identity, error: identityError } = await caller.auth.getUser();
    if (identityError || !identity?.user) return errors.unauthenticated(req);

    // Role is re-read from profiles through the service role on every call.
    const admin = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: actorRow, error: actorError } = await admin
      .from('profiles')
      .select('role, is_active, branch_id')
      .eq('id', identity.user.id)
      .maybeSingle();
    if (actorError) {
      console.error('admin-reset-password: profile lookup failed:', actorError.message);
      return errors.internal(req);
    }
    if (!actorRow) {
      return errors.notFound(req, 'Your staff profile was not found.');
    }
    const actor = actorRow as Profile;
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

    let userId: string;
    try {
      userId = requiredUuid(requiredString(body.user_id, 'user_id', 36), 'user_id');
    } catch (error) {
      if (error instanceof ValidationError) return errors.validation(req, error.message);
      return errors.validation(req, 'The submitted details are not valid.');
    }

    const { data: targetRow, error: targetError } = await admin
      .from('profiles')
      .select('role, branch_id, is_active')
      .eq('id', userId)
      .maybeSingle();
    if (targetError) {
      console.error('admin-reset-password: target lookup failed:', targetError.message);
      return errors.internal(req);
    }
    if (!targetRow) {
      return errors.notFound(req, 'That user was not found.');
    }
    const target = targetRow as Profile;
    if (!target.is_active) {
      return errors.forbidden(req, 'That account is inactive.');
    }
    if (target.role === 'super_admin' && actor.role !== 'super_admin') {
      return errors.forbidden(req, 'Only a super admin can reset a super admin.');
    }
    if (
      actor.role !== 'super_admin' &&
      (!actor.branch_id || target.branch_id !== actor.branch_id)
    ) {
      return errors.forbidden(req, 'You can only manage users in your own branch.');
    }

    const password = temporaryPassword();
    const response = await fetch(`${url}/auth/v1/admin/users/${userId}`, {
      method: 'PUT',
      headers: {
        Authorization: `Bearer ${serviceKey}`,
        apikey: serviceKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ password }),
    });
    if (!response.ok) {
      const status = response.status;
      console.error('admin-reset-password: Auth admin API failed with status', status);
      if (status === 404) return errors.notFound(req, 'That user was not found.');
      return errors.internal(req);
    }

    await writeAudit(admin, {
      user_id: identity.user.id,
      action: 'reset_password',
      table_name: 'profiles',
      record_id: userId,
      branch_id: target.branch_id,
      old_data: null,
      new_data: { action: 'reset_password' },
      created_at: new Date().toISOString(),
    });

    return json(req, { user_id: userId, temporary_password: password });
  } catch (error) {
    console.error(
      'admin-reset-password: unexpected error:',
      error instanceof Error ? error.message : String(error),
    );
    return errors.internal(req);
  }
});
