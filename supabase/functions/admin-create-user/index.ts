// Creates an auth user and its profile. The service-role key is read from the
// Edge Function environment only; it is never bundled into the Flutter app.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const ALLOWED_ROLES = [
  'super_admin',
  'admin',
  'pharmacist',
  'cashier',
  'store_keeper',
  'accountant',
];

function temporaryPassword(): string {
  const alphabet =
    'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%';
  const bytes = new Uint8Array(14);
  crypto.getRandomValues(bytes);
  let password = '';
  for (const byte of bytes) password += alphabet[byte % alphabet.length];
  return password;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405);
  }

  try {
    const url = Deno.env.get('SUPABASE_URL');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
    if (!url || !serviceKey || !anonKey) {
      throw new Error('Server is not configured');
    }

    const authHeader = req.headers.get('Authorization');
    if (!authHeader) throw new Error('Please sign in again');

    // Verify the caller using their own JWT (anon key + caller Authorization).
    const caller = createClient(url, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: identity, error: identityError } = await caller.auth.getUser();
    if (identityError || !identity.user) throw new Error('Please sign in again');

    const admin = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: actor, error: actorError } = await admin
      .from('profiles')
      .select('role, is_active, branch_id')
      .eq('id', identity.user.id)
      .single();
    if (actorError || !actor) throw new Error('Profile not found');
    if (!actor.is_active) throw new Error('This account is inactive');
    if (actor.role !== 'super_admin' && actor.role !== 'admin') {
      throw new Error('You do not have permission to create users');
    }

    const body = await req.json();
    const email = String(body.email ?? '').trim().toLowerCase();
    const fullName = String(body.full_name ?? '').trim();
    const role = String(body.role ?? '');
    const branchId = body.branch_id || actor.branch_id || null;

    if (!email || !email.includes('@')) throw new Error('A valid email is required');
    if (!fullName) throw new Error('Full name is required');
    if (!ALLOWED_ROLES.includes(role)) throw new Error('Select a valid role');
    if (role === 'super_admin' && actor.role !== 'super_admin') {
      throw new Error('Only a super admin can create another super admin');
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
        app_metadata: { role },
        user_metadata: { full_name: fullName },
      }),
    });
    const created = await response.json();
    if (!response.ok) {
      const message = created.msg ?? created.message ?? 'Could not create the user';
      throw new Error(String(message));
    }

    const { error: profileError } = await admin.from('profiles').upsert({
      id: created.id,
      email,
      full_name: fullName,
      role,
      branch_id: branchId,
      is_active: true,
    });
    if (profileError) throw profileError;

    try {
      await admin.from('audit_log').insert({
        actor_id: identity.user.id,
        action: 'create_user',
        table_name: 'profiles',
        record_id: created.id,
        new_values: { email, role, branch_id: branchId },
      });
    } catch {
      // Audit is best effort: never fail user creation because of logging.
    }

    return json({ user_id: created.id, temporary_password: password });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Something went wrong';
    return json({ error: message }, 400);
  }
});
