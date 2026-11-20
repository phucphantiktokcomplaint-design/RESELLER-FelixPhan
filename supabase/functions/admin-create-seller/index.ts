import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return new Response(JSON.stringify({ error: 'Method not allowed' }), { status: 405, headers: { ...cors, 'Content-Type': 'application/json' } });

  const url = Deno.env.get('SUPABASE_URL')!;
  const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const authHeader = req.headers.get('Authorization') || '';
  const caller = createClient(url, anon, { global: { headers: { Authorization: authHeader } } });
  const { data: { user }, error: authError } = await caller.auth.getUser();
  if (authError || !user) return new Response(JSON.stringify({ error: 'Vui lòng đăng nhập lại.' }), { status: 401, headers: { ...cors, 'Content-Type': 'application/json' } });

  const admin = createClient(url, service, { auth: { autoRefreshToken: false, persistSession: false } });
  const { data: adminProfile } = await admin.from('profiles').select('role,active').eq('id', user.id).single();
  if (adminProfile?.role !== 'admin' || !adminProfile.active) return new Response(JSON.stringify({ error: 'Chỉ Admin mới được tạo Seller.' }), { status: 403, headers: { ...cors, 'Content-Type': 'application/json' } });

  try {
    const { username, password, display_name } = await req.json();
    const cleanUsername = String(username || '').trim().toLowerCase();
    const cleanDisplay = String(display_name || cleanUsername).trim();
    if (!/^[a-z0-9][a-z0-9._-]{2,29}$/.test(cleanUsername)) throw new Error('Tên đăng nhập phải từ 3–30 ký tự, chỉ gồm chữ thường, số, dấu chấm, gạch dưới hoặc gạch ngang.');
    if (cleanUsername === 'phucphan') throw new Error('Tên đăng nhập này dành riêng cho Admin.');
    if (typeof password !== 'string' || password.length < 8) throw new Error('Mật khẩu phải có ít nhất 8 ký tự.');

    const email = `${cleanUsername}@seller.reseller.local`;
    const { data: created, error: createError } = await admin.auth.admin.createUser({ email, password, email_confirm: true, user_metadata: { username: cleanUsername, display_name: cleanDisplay } });
    if (createError) throw createError;
    const { error: profileError } = await admin.from('profiles').insert({ id: created.user.id, username: cleanUsername, display_name: cleanDisplay, role: 'seller', wallet: 0, active: true });
    if (profileError) {
      await admin.auth.admin.deleteUser(created.user.id);
      throw profileError;
    }
    return new Response(JSON.stringify({ ok: true, username: cleanUsername }), { status: 200, headers: { ...cors, 'Content-Type': 'application/json' } });
  } catch (error) {
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : 'Không thể tạo Seller.' }), { status: 400, headers: { ...cors, 'Content-Type': 'application/json' } });
  }
});
