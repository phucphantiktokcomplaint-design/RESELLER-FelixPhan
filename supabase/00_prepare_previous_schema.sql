-- 00 · PREPARE EXISTING RESELLER FOUNDATION
-- Run this ONLY if you already ran the earlier schema containing profiles.email,
-- profiles.wallet_balance and products.category values 'app-nox'/'acc-clone-ff'.
-- It preserves the old tables by renaming them; it does not delete their data.
do $$
begin
  if to_regclass('public.profiles') is not null
     and exists (select 1 from information_schema.columns where table_schema='public' and table_name='profiles' and column_name='wallet_balance')
     and to_regclass('public.legacy_profiles') is null then
    alter table public.profiles rename to legacy_profiles;
  end if;
  if to_regclass('public.products') is not null
     and exists (select 1 from information_schema.columns where table_schema='public' and table_name='products' and column_name='product_type')
     and to_regclass('public.legacy_products') is null then
    alter table public.products rename to legacy_products;
  end if;
  if to_regclass('public.key_stock') is not null and to_regclass('public.legacy_key_stock') is null then
    alter table public.key_stock rename to legacy_key_stock;
  end if;
  if to_regclass('public.acc_stock') is not null and to_regclass('public.legacy_acc_stock') is null then
    alter table public.acc_stock rename to legacy_acc_stock;
  end if;
  if to_regclass('public.orders') is not null
     and exists (select 1 from information_schema.columns where table_schema='public' and table_name='orders' and column_name='total_amount')
     and to_regclass('public.legacy_orders') is null then
    alter table public.orders rename to legacy_orders;
  end if;
  if to_regclass('public.order_items') is not null and to_regclass('public.legacy_order_items') is null then
    alter table public.order_items rename to legacy_order_items;
  end if;
  if to_regclass('public.deposits') is not null and to_regclass('public.legacy_deposits') is null then
    alter table public.deposits rename to legacy_deposits;
  end if;
  if to_regclass('public.transactions') is not null and to_regclass('public.legacy_transactions') is null then
    alter table public.transactions rename to legacy_transactions;
  end if;
  if to_regclass('public.messages') is not null and to_regclass('public.legacy_messages') is null then
    alter table public.messages rename to legacy_messages;
  end if;
end $$;
