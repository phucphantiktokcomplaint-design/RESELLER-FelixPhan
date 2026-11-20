-- RESELLER production schema for Supabase (Postgres)
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null,
  display_name text not null default '',
  role text not null default 'seller' check (role in ('admin','seller')),
  wallet bigint not null default 0 check (wallet >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.products (
  id text primary key,
  category text not null check (category in ('nox','acc')),
  name text not null,
  description text not null default '',
  price bigint not null check (price >= 0),
  image_url text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.inventory (
  id bigint generated always as identity primary key,
  product_id text not null references public.products(id) on delete cascade,
  payload text not null,
  sold_to uuid references public.profiles(id),
  sold_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists inventory_available_idx on public.inventory(product_id, id) where sold_to is null;

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references public.profiles(id),
  product_id text not null references public.products(id),
  product_name text not null,
  quantity integer not null check (quantity > 0),
  unit_price bigint not null,
  total bigint not null,
  delivered_items jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.wallet_transactions (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id),
  kind text not null check (kind in ('deposit','purchase','adjustment')),
  amount bigint not null,
  note text not null default '',
  order_id uuid references public.orders(id),
  created_at timestamptz not null default now()
);

create table if not exists public.deposit_requests (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references public.profiles(id),
  amount bigint not null check (amount >= 10000),
  transfer_memo text unique not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  proof_path text,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references public.profiles(id)
);

create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references public.profiles(id),
  sender_id uuid not null references public.profiles(id),
  body text not null default '',
  attachment_path text,
  created_at timestamptz not null default now()
);
create index if not exists chat_messages_seller_created_idx on public.chat_messages(seller_id, created_at);

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and role='admin' and active=true)
$$;

alter table public.profiles enable row level security;
alter table public.products enable row level security;
alter table public.inventory enable row level security;
alter table public.orders enable row level security;
alter table public.wallet_transactions enable row level security;
alter table public.deposit_requests enable row level security;
alter table public.chat_messages enable row level security;

-- Profiles: sellers can see/update only safe own profile fields; admin can manage all.
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated using (id=auth.uid() or public.is_admin());
drop policy if exists profiles_admin_all on public.profiles;
create policy profiles_admin_all on public.profiles for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Products are visible to signed-in active users. Only admin writes.
drop policy if exists products_read on public.products;
create policy products_read on public.products for select to authenticated using (active=true or public.is_admin());
drop policy if exists products_admin_write on public.products;
create policy products_admin_write on public.products for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Inventory content is never directly readable by sellers; allocation is via secure RPC.
drop policy if exists inventory_admin_all on public.inventory;
create policy inventory_admin_all on public.inventory for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Sellers can see their own orders and transactions; admin sees all.
drop policy if exists orders_read on public.orders;
create policy orders_read on public.orders for select to authenticated using (seller_id=auth.uid() or public.is_admin());
drop policy if exists transactions_read on public.wallet_transactions;
create policy transactions_read on public.wallet_transactions for select to authenticated using (profile_id=auth.uid() or public.is_admin());

drop policy if exists deposits_read on public.deposit_requests;
create policy deposits_read on public.deposit_requests for select to authenticated using (seller_id=auth.uid() or public.is_admin());
drop policy if exists deposits_insert on public.deposit_requests;
create policy deposits_insert on public.deposit_requests for insert to authenticated with check (seller_id=auth.uid() and status='pending');
drop policy if exists deposits_admin_update on public.deposit_requests;
create policy deposits_admin_update on public.deposit_requests for update to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists chat_read on public.chat_messages;
create policy chat_read on public.chat_messages for select to authenticated using (seller_id=auth.uid() or public.is_admin());
drop policy if exists chat_insert on public.chat_messages;
create policy chat_insert on public.chat_messages for insert to authenticated with check (sender_id=auth.uid() and (seller_id=auth.uid() or public.is_admin()));

-- Atomic purchase: checks wallet + stock, reserves exact rows, deducts wallet, records order and ledger.
create or replace function public.purchase_product(p_product_id text, p_quantity integer)
returns jsonb language plpgsql security definer set search_path=public as $$
declare u uuid:=auth.uid(); p public.products%rowtype; picked public.inventory%rowtype; items jsonb:='[]'::jsonb; total_cost bigint; order_uuid uuid;
begin
  if u is null then raise exception 'Vui lòng đăng nhập'; end if;
  if p_quantity<1 or p_quantity>100 then raise exception 'Số lượng không hợp lệ'; end if;
  select * into p from public.products where id=p_product_id and active=true;
  if not found then raise exception 'Sản phẩm không tồn tại'; end if;
  total_cost:=p.price*p_quantity;
  perform 1 from public.profiles where id=u and active=true for update;
  if not found then raise exception 'Tài khoản đã bị khóa'; end if;
  if (select wallet from public.profiles where id=u)<total_cost then raise exception 'Số dư ví không đủ'; end if;
  for picked in select * from public.inventory where product_id=p_product_id and sold_to is null order by id for update skip locked limit p_quantity loop
    items:=items||jsonb_build_array(picked.payload);
    update public.inventory set sold_to=u,sold_at=now() where id=picked.id;
  end loop;
  if jsonb_array_length(items)<>p_quantity then raise exception 'Kho không đủ hàng'; end if;
  update public.profiles set wallet=wallet-total_cost where id=u;
  insert into public.orders(seller_id,product_id,product_name,quantity,unit_price,total,delivered_items)
  values(u,p.id,p.name,p_quantity,p.price,total_cost,items) returning id into order_uuid;
  insert into public.wallet_transactions(profile_id,kind,amount,note,order_id)
  values(u,'purchase',-total_cost,'Mua '||p.name,order_uuid);
  return jsonb_build_object('order_id',order_uuid,'product_name',p.name,'quantity',p_quantity,'total',total_cost,'items',items);
end $$;
revoke all on function public.purchase_product(text,integer) from public;
grant execute on function public.purchase_product(text,integer) to authenticated;

-- Only admin can approve a deposit; wallet and ledger are updated in the same transaction.
create or replace function public.approve_deposit(p_deposit_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare d public.deposit_requests%rowtype;
begin
  if not public.is_admin() then raise exception 'Không có quyền duyệt nạp'; end if;
  select * into d from public.deposit_requests where id=p_deposit_id for update;
  if not found then raise exception 'Không tìm thấy yêu cầu nạp'; end if;
  if d.status<>'pending' then raise exception 'Yêu cầu đã được xử lý'; end if;
  update public.deposit_requests set status='approved',reviewed_at=now(),reviewed_by=auth.uid() where id=p_deposit_id;
  update public.profiles set wallet=wallet+d.amount where id=d.seller_id;
  insert into public.wallet_transactions(profile_id,kind,amount,note) values(d.seller_id,'deposit',d.amount,'Nạp tiền '||d.transfer_memo);
end $$;
revoke all on function public.approve_deposit(uuid) from public;
grant execute on function public.approve_deposit(uuid) to authenticated;

-- Bootstrap products (safe to re-run).
insert into public.products(id,category,name,description,price,image_url) values
('nox-hour','nox','Key Giờ APP NOX','Key truy cập APP NOX trong 1 giờ',7000,'assets/products/app-nox/nox-felix-phan.jpg'),
('nox-week','nox','Key Tuần APP NOX','Key truy cập APP NOX trong 7 ngày',45000,'assets/products/app-nox/nox-felix-phan.jpg'),
('nox-month','nox','Key Tháng APP NOX','Key truy cập APP NOX trong 30 ngày',115000,'assets/products/app-nox/nox-felix-phan.jpg'),
('acc-lv5','acc','CLONE FF LV5','Tài khoản Free Fire cấp độ 5',5000,'assets/products/acc-clone-ff/acc-clone-ff-banner.png'),
('acc-kc','acc','CLONE FF Rank KC','Tài khoản Free Fire rank KC',32000,'assets/products/acc-clone-ff/acc-clone-ff-banner.png'),
('acc-ht','acc','CLONE FF RANK HT','Tài khoản Free Fire rank HT',45000,'assets/products/acc-clone-ff/acc-clone-ff-banner.png')
on conflict(id) do nothing;

-- Storage bucket for chat attachments / payment proofs.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('reseller-files','reseller-files',false,10485760,array['image/png','image/jpeg','image/webp','application/pdf'])
on conflict(id) do nothing;
drop policy if exists "authenticated upload reseller files" on storage.objects;
create policy "authenticated upload reseller files" on storage.objects for insert to authenticated with check (bucket_id='reseller-files' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));
drop policy if exists "owner or admin read reseller files" on storage.objects;
create policy "owner or admin read reseller files" on storage.objects for select to authenticated using (bucket_id='reseller-files' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));

-- Realtime: enable chat updates in Supabase Dashboard if publication is not already configured.
do $$ begin alter publication supabase_realtime add table public.chat_messages; exception when duplicate_object then null; when undefined_object then null; end $$;

-- Product artwork is public; only authenticated admins may upload/update it.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('product-images','product-images',true,10485760,array['image/png','image/jpeg','image/webp'])
on conflict(id) do nothing;
drop policy if exists "admin upload product images" on storage.objects;
create policy "admin upload product images" on storage.objects for insert to authenticated with check (bucket_id='product-images' and public.is_admin());
drop policy if exists "admin update product images" on storage.objects;
create policy "admin update product images" on storage.objects for update to authenticated using (bucket_id='product-images' and public.is_admin()) with check (bucket_id='product-images' and public.is_admin());
drop policy if exists "public read product images" on storage.objects;
create policy "public read product images" on storage.objects for select to public using (bucket_id='product-images');

-- Chat attachment recipient can read files sent in their conversation, including files uploaded by Admin.
drop policy if exists "chat participants read attachments" on storage.objects;
create policy "chat participants read attachments" on storage.objects for select to authenticated using (
  bucket_id='reseller-files' and (
    (storage.foldername(name))[1]=auth.uid()::text
    or public.is_admin()
    or exists(select 1 from public.chat_messages m where m.attachment_path=name and m.seller_id=auth.uid())
  )
);

-- One-time Admin bootstrap. First create an Auth user in Supabase Dashboard with email
-- phucphanmedia@gmail.com and the password you choose, then run this statement:
-- insert into public.profiles(id,username,display_name,role)
-- select id,'phucphan','Phuc Phan','admin' from auth.users where email='phucphanmedia@gmail.com'
-- on conflict(id) do update set username='phucphan',display_name='Phuc Phan',role='admin',active=true;

create or replace function public.admin_dashboard_stats()
returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb;
begin
  if not public.is_admin() then raise exception 'Không có quyền xem thống kê'; end if;
  select jsonb_build_object(
    'seller_count',(select count(*) from public.profiles where role='seller' and active=true),
    'order_count',(select count(*) from public.orders),
    'revenue_total',(select coalesce(sum(total),0) from public.orders),
    'pending_deposits',(select count(*) from public.deposit_requests where status='pending'),
    'recent_orders',coalesce((select jsonb_agg(row_to_json(q)) from (
      select o.id,o.seller_id,p.username,o.product_name,o.quantity,o.total,o.created_at
      from public.orders o left join public.profiles p on p.id=o.seller_id
      order by o.created_at desc limit 50
    ) q),'[]'::jsonb)
  ) into result;
  return result;
end $$;
revoke all on function public.admin_dashboard_stats() from public;
grant execute on function public.admin_dashboard_stats() to authenticated;
