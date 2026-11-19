// Issues a new temporary password for a user. Uses the service-role key only
// inside this Edge Function; the Flutter app never holds it.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

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
      throw new Error('You do not have permission to reset passwords');
    }

    const body = await req.json();
    const userId = String(body.user_id ?? '');
    if (!userId) throw new Error('Select a user');

    const { data: target, error: targetError } = await admin
      .from('profiles')
      .select('role, branch_id, is_active')
      .eq('id', userId)
      .single();
    if (targetError || !target) throw new Error('User not found');
    if (target.role === 'super_admin' && actor.role !== 'super_admin') {
      throw new Error('Only a super admin can reset a super admin');
    }
    if (
      actor.role !== 'super_admin' &&
      target.branch_id &&
      actor.branch_id &&
      target.branch_id !== actor.branch_id
    ) {
      throw new Error('You can only manage users in your own branch');
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
      const failure = await response.json();
      const message = failure.msg ?? failure.message ?? 'Could not reset the password';
      throw new Error(String(message));
    }

    try {
      await admin.from('audit_log').insert({
        actor_id: identity.user.id,
        action: 'reset_password',
        table_name: 'profiles',
        record_id: userId,
      });
    } catch {
      // Audit is best effort.
    }

    return json({ user_id: userId, temporary_password: password });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Something went wrong';
    return json({ error: message }, 400);
  }
});
