begin;
create table public.realeza_movements (
 id uuid primary key, owner uuid not null references auth.users(id), day date not null,
 created timestamptz not null default now(), kind text not null check(kind in ('withdrawal','consumption')),
 description text not null check(length(description) between 1 and 300), amount integer not null default 0,
 product_id uuid references public.realeza_products(id), product_name text, qty integer,
 voided integer not null default 0 check(voided in (0,1)),
 check((kind='withdrawal' and amount between 1 and 100000000 and product_id is null and qty is null)
 or (kind='consumption' and amount=0 and product_id is not null and product_name is not null and qty between 1 and 1000))
);
create index realeza_movements_day on public.realeza_movements(owner,day);
alter table public.realeza_movements enable row level security;
create policy own_movements on public.realeza_movements for select to authenticated using(owner=(select auth.uid()));
revoke all on public.realeza_movements from anon,authenticated;
grant select on public.realeza_movements to authenticated;

alter function public.realeza_command(jsonb) rename to realeza_command_cash_base;
revoke all on function public.realeza_command_cash_base(jsonb) from public,anon,authenticated;
create function public.realeza_command(payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); action text:=payload->>'action'; selected_day date;
 previous public.realeza_movements%rowtype; product public.realeza_products%rowtype;
 target uuid; movement_amount integer:=0; quantity integer; result jsonb;
 withdrawals bigint; expected bigint; closing_snapshot jsonb; withdrawal_items jsonb; consumption_items jsonb;
begin
 if uid is null then raise exception 'Entre na sua conta.'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(uid::text,0));
 if action in ('movement','void_movement') then
  target:=(payload->>'id')::uuid;
  if target is null then raise exception 'Identificador inválido.'; end if;
  if action='void_movement' then
   select * into previous from public.realeza_movements m where m.id=target and m.owner=uid;
   if not found then raise exception 'Lançamento indisponível.'; end if;
   selected_day:=previous.day;
  else
   select * into previous from public.realeza_movements m where m.id=target;
   if found then
    if previous.owner=uid then return jsonb_build_object('ok',true,'replayed',true); end if;
    raise exception 'Identificador indisponível.';
   end if;
   if coalesce(payload->>'day','') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Data inválida.'; end if;
   selected_day:=(payload->>'day')::date;
  end if;
  if selected_day>(now() at time zone 'America/Sao_Paulo')::date then raise exception 'Data futura inválida.'; end if;
  if exists(select 1 from public.realeza_closings c where c.owner=uid and c.day=selected_day) then raise exception 'Reabra o dia antes de alterar os lançamentos.'; end if;
  if not exists(select 1 from public.realeza_openings o where o.owner=uid and o.day=selected_day) then raise exception 'Registre a abertura de caixa deste dia primeiro.'; end if;
  if action='void_movement' then
   if previous.voided=1 then return jsonb_build_object('ok',true); end if;
   update public.realeza_movements set voided=1 where id=target and owner=uid;
  else
   if coalesce(length(trim(payload->>'description')),0) not between 1 and 300 then raise exception 'Informe uma descrição do que foi retirado ou comprado.'; end if;
   if payload->>'kind'='withdrawal' then
    if coalesce(payload->>'amount','') !~ '^[0-9]{1,9}$' then raise exception 'Informe o valor retirado em dinheiro.'; end if;
    movement_amount:=(payload->>'amount')::integer;
    if movement_amount not between 1 and 100000000 then raise exception 'Valor retirado inválido.'; end if;
   elsif payload->>'kind'='consumption' then
    if coalesce(payload->>'qty','') !~ '^[0-9]{1,4}$' then raise exception 'Informe a quantidade de produtos.'; end if;
    quantity:=(payload->>'qty')::integer;
    if quantity not between 1 and 1000 then raise exception 'Quantidade inválida.'; end if;
    select * into product from public.realeza_products p where p.id=(payload->>'product_id')::uuid and p.owner=uid and p.active=1;
    if not found then raise exception 'Produto indisponível.'; end if;
   else raise exception 'Tipo de lançamento inválido.';
   end if;
   insert into public.realeza_movements(id,owner,day,kind,description,amount,product_id,product_name,qty)
   values(target,uid,selected_day,payload->>'kind',trim(payload->>'description'),movement_amount,product.id,product.name,quantity);
  end if;
  insert into public.realeza_audit(owner,action,details) values(uid,action,jsonb_build_object('request',payload,'before',case when previous.id is not null then to_jsonb(previous) else null end));
  return jsonb_build_object('ok',true);
 end if;
 if action='close' then
  if coalesce(payload->>'day','') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Data inválida.'; end if;
  selected_day:=(payload->>'day')::date;
  if exists(select 1 from public.realeza_closings c where c.owner=uid and c.day=selected_day) then return jsonb_build_object('ok',true,'alreadyClosed',true); end if;
  result:=public.realeza_command_cash_base(payload);
  select coalesce(sum(m.amount),0),coalesce(jsonb_agg(to_jsonb(m) order by m.created),'[]'::jsonb)
   into withdrawals,withdrawal_items from public.realeza_movements m where m.owner=uid and m.day=selected_day and m.kind='withdrawal' and m.voided=0;
  select coalesce(jsonb_agg(to_jsonb(m) order by m.created),'[]'::jsonb) into consumption_items
   from public.realeza_movements m where m.owner=uid and m.day=selected_day and m.kind='consumption' and m.voided=0;
  select snapshot into closing_snapshot from public.realeza_closings c where c.owner=uid and c.day=selected_day;
  expected:=(closing_snapshot->>'initial_cash')::bigint+(closing_snapshot->>'Dinheiro')::bigint-withdrawals;
  update public.realeza_closings c set snapshot=c.snapshot||jsonb_build_object('cash_withdrawals',withdrawals,'withdrawals',withdrawal_items,'consumptions',consumption_items,'expected_cash',expected,'cash_difference',(c.snapshot->>'counted_cash')::bigint-expected)
   where c.owner=uid and c.day=selected_day;
  return result;
 end if;
 return public.realeza_command_cash_base(payload);
end; $$;
revoke all on function public.realeza_command(jsonb) from public,anon;
grant execute on function public.realeza_command(jsonb) to authenticated;

alter function public.realeza_snapshot() rename to realeza_snapshot_cash_base;
revoke all on function public.realeza_snapshot_cash_base() from public,anon,authenticated;
create function public.realeza_snapshot() returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();
begin
 if uid is null then raise exception 'Entre na sua conta.'; end if;
 return public.realeza_snapshot_cash_base()||jsonb_build_object('movements',coalesce((select jsonb_agg(to_jsonb(m) order by m.created) from public.realeza_movements m where m.owner=uid),'[]'::jsonb));
end; $$;
revoke all on function public.realeza_snapshot() from public,anon;
grant execute on function public.realeza_snapshot() to authenticated;
commit;
