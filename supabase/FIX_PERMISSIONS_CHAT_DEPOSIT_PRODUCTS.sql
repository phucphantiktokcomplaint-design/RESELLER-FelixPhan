-- RESELLER FIX PACK — run once in Supabase SQL Editor
-- Restores table privileges while keeping Row Level Security policies in force.
-- Does not expose inventory to sellers and does not auto-approve deposits.

grant usage on schema public to authenticated;

-- Required table privileges; RLS below remains the actual access boundary.
grant select on public.profiles, public.products, public.orders,
  public.wallet_transactions, public.deposit_requests, public.chat_messages
to authenticated;

grant insert, update, delete on public.products to authenticated;
grant select, insert, update, delete on public.inventory to authenticated;
grant insert on public.deposit_requests, public.chat_messages to authenticated;
grant update on public.profiles, public.deposit_requests to authenticated;

-- Ensure only an active Admin can manage products and inventory.
drop policy if exists products_admin_write on public.products;
create policy products_admin_write on public.products
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists inventory_admin_all on public.inventory;
create policy inventory_admin_all on public.inventory
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- Seller can read their own chat; Admin can read all conversations.
drop policy if exists chat_read on public.chat_messages;
create policy chat_read on public.chat_messages
  for select to authenticated
  using (seller_id = auth.uid() or public.is_admin());

-- Seller sends as themselves in their own conversation.
-- Admin sends as themselves to an existing Seller conversation.
drop policy if exists chat_insert on public.chat_messages;
create policy chat_insert on public.chat_messages
  for insert to authenticated
  with check (
    sender_id = auth.uid()
    and (
      (seller_id = auth.uid() and exists (
        select 1 from public.profiles p
        where p.id = auth.uid() and p.role = 'seller' and p.active = true
      ))
      or
      (public.is_admin() and exists (
        select 1 from public.profiles p
        where p.id = seller_id and p.role = 'seller'
      ))
    )
  );

-- Seller can create only their own pending deposit request.
drop policy if exists deposits_insert on public.deposit_requests;
create policy deposits_insert on public.deposit_requests
  for insert to authenticated
  with check (
    seller_id = auth.uid()
    and status = 'pending'
    and amount >= 10000
  );

-- Only Admin can review/change deposit requests.
drop policy if exists deposits_admin_update on public.deposit_requests;
create policy deposits_admin_update on public.deposit_requests
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- Products are readable by signed-in users under the existing products_read policy.
-- Inventory remains Admin-only under inventory_admin_all; purchases use the secure RPC.

-- Allow authenticated users to use the identity sequence; RLS still limits inventory writes.
grant usage, select on all sequences in schema public to authenticated;

-- Reassert RPC execution permissions.
grant execute on function public.purchase_product(text, integer) to authenticated;
grant execute on function public.approve_deposit(uuid) to authenticated;
grant execute on function public.admin_dashboard_stats() to authenticated;

