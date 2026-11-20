-- 02 · IMPORT DATA FROM THE PREVIOUS RESELLER FOUNDATION
-- Run after 00_prepare_previous_schema.sql and schema.sql.
-- Legacy tables are retained. This imports profiles, products, stock, deposits,
-- wallet ledger and chat. Legacy order history remains preserved in legacy_orders
-- and legacy_order_items because the previous schema allowed multi-product orders.

do $$
begin
  if to_regclass('public.legacy_profiles') is not null then
    insert into public.profiles(id,username,display_name,role,wallet,active,created_at)
    select lp.id,
      lower(coalesce(nullif(lp.username,''), split_part(coalesce(lp.email,lp.id::text),'@',1))),
      coalesce(nullif(lp.username,''),'Seller'),
      case when lp.role='admin' then 'admin' else 'seller' end,
      greatest(coalesce(lp.wallet_balance,0),0)::bigint,
      coalesce(lp.is_active,true),
      coalesce(lp.created_at,now())
    from public.legacy_profiles lp
    on conflict(id) do update set
      role=excluded.role, wallet=excluded.wallet, active=excluded.active;
  end if;

  if to_regclass('public.legacy_products') is not null then
    insert into public.products(id,category,name,description,price,image_url,active,created_at)
    select 'legacy-'||lp.id::text,
      case when lp.category='app-nox' then 'nox' else 'acc' end,
      lp.name,coalesce(lp.description,''),coalesce(lp.price,0)::bigint,
      lp.image_url,coalesce(lp.is_active,true),coalesce(lp.created_at,now())
    from public.legacy_products lp
    on conflict(id) do nothing;
  end if;

  if to_regclass('public.legacy_key_stock') is not null then
    insert into public.inventory(product_id,payload,sold_to,sold_at,created_at)
    select 'legacy-'||ks.product_id::text,ks.key_value,ks.sold_to,ks.sold_at,coalesce(ks.created_at,now())
    from public.legacy_key_stock ks
    where exists(select 1 from public.products p where p.id='legacy-'||ks.product_id::text);
  end if;

  if to_regclass('public.legacy_acc_stock') is not null then
    insert into public.inventory(product_id,payload,sold_to,sold_at,created_at)
    select 'legacy-'||a.product_id::text,a.account_username||'|'||a.account_password,a.sold_to,a.sold_at,coalesce(a.created_at,now())
    from public.legacy_acc_stock a
    where exists(select 1 from public.products p where p.id='legacy-'||a.product_id::text);
  end if;

  if to_regclass('public.legacy_deposits') is not null then
    insert into public.deposit_requests(id,seller_id,amount,transfer_memo,status,created_at,reviewed_at,reviewed_by)
    select d.id,d.seller_id,d.amount::bigint,
      case when nullif(d.transfer_content,'') is null then 'LEGACY-'||left(d.id::text,12) else left(d.transfer_content,40)||'-'||left(d.id::text,8) end,
      case when d.status in ('approved','rejected') then d.status else 'pending' end,
      coalesce(d.created_at,now()),d.approved_at,d.approved_by
    from public.legacy_deposits d
    where exists(select 1 from public.profiles p where p.id=d.seller_id)
    on conflict(id) do nothing;
  end if;

  if to_regclass('public.legacy_transactions') is not null then
    insert into public.wallet_transactions(profile_id,kind,amount,note,created_at)
    select t.seller_id,
      case when t.type='deposit' then 'deposit' when t.type='purchase' then 'purchase' else 'adjustment' end,
      t.amount::bigint,coalesce(t.description,''),coalesce(t.created_at,now())
    from public.legacy_transactions t
    where exists(select 1 from public.profiles p where p.id=t.seller_id);
  end if;

  if to_regclass('public.legacy_messages') is not null then
    insert into public.chat_messages(seller_id,sender_id,body,attachment_path,created_at)
    select case when sender.role='admin' then m.recipient_id else m.sender_id end,
      m.sender_id,coalesce(m.content,''),null,coalesce(m.created_at,now())
    from public.legacy_messages m
    left join public.profiles sender on sender.id=m.sender_id
    where exists(
      select 1 from public.profiles p
      where p.id=case when sender.role='admin' then m.recipient_id else m.sender_id end
        and p.role='seller'
    );
  end if;
end $$;
