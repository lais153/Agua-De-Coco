-- Execute uma vez no SQL Editor de um projeto Supabase novo.
begin;
create table public.realeza_products (
 id uuid primary key default gen_random_uuid(), owner uuid not null references auth.users(id),
 name text not null check(length(name) between 1 and 100), price integer not null check(price between 1 and 100000000),
 active integer not null default 1 check(active in (0,1)), sort_order integer not null default 0,
 created timestamptz not null default now()
);
create table public.realeza_sales (
 id uuid primary key, owner uuid not null references auth.users(id), day date not null,
 created timestamptz not null default now(), payment text not null check(payment in ('Pix','Dinheiro','Débito','Crédito')),
 items jsonb not null, total integer not null check(total between 1 and 100000000),
 deleted integer not null default 0, version integer not null default 1
);
create table public.realeza_closings (
 owner uuid not null references auth.users(id), day date not null, created timestamptz not null default now(),
 snapshot jsonb not null, primary key(owner,day)
);
create table public.realeza_audit (
 id uuid primary key default gen_random_uuid(), owner uuid not null references auth.users(id),
 created timestamptz not null default now(), action text not null, details jsonb not null
);
create index realeza_sales_day on public.realeza_sales(owner,day);
create index realeza_products_owner on public.realeza_products(owner,sort_order,created);
create index realeza_audit_owner on public.realeza_audit(owner,created);

alter table public.realeza_products enable row level security;
alter table public.realeza_sales enable row level security;
alter table public.realeza_closings enable row level security;
alter table public.realeza_audit enable row level security;
create policy own_products on public.realeza_products for select to authenticated using(owner=(select auth.uid()));
create policy own_sales on public.realeza_sales for select to authenticated using(owner=(select auth.uid()));
create policy own_closings on public.realeza_closings for select to authenticated using(owner=(select auth.uid()));
create policy own_audit on public.realeza_audit for select to authenticated using(owner=(select auth.uid()));
-- Nenhuma escrita direta: regras e auditoria são executadas atomicamente pela função.
revoke all on public.realeza_products,public.realeza_sales,public.realeza_closings,public.realeza_audit from anon,authenticated;
grant select on public.realeza_products,public.realeza_sales,public.realeza_closings,public.realeza_audit to authenticated;

create function public.realeza_snapshot() returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); result jsonb;
begin
 if uid is null then raise exception 'Entre na sua conta.'; end if;
 select jsonb_build_object(
  'today',(now() at time zone 'America/Sao_Paulo')::date::text,
  'products',coalesce((select jsonb_agg(to_jsonb(p) order by p.sort_order,p.created,p.id) from public.realeza_products p where p.owner=uid),'[]'::jsonb),
  'sales',coalesce((select jsonb_agg(to_jsonb(s)||jsonb_build_object('items',s.items::text) order by s.created) from public.realeza_sales s where s.owner=uid),'[]'::jsonb),
  'closings',coalesce((select jsonb_agg(to_jsonb(c)||jsonb_build_object('snapshot',c.snapshot::text) order by c.day) from public.realeza_closings c where c.owner=uid),'[]'::jsonb),
  'audit',coalesce((select jsonb_agg(to_jsonb(a) order by a.created) from public.realeza_audit a where a.owner=uid),'[]'::jsonb)
 ) into result;
 return result;
end; $$;

create function public.realeza_command(payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 uid uuid:=auth.uid(); action text:=payload->>'action'; today date:=(now() at time zone 'America/Sao_Paulo')::date;
 target uuid; selected_day date; product public.realeza_products%rowtype; old_sale public.realeza_sales%rowtype;
 line jsonb; previous jsonb; prepared jsonb:='[]'::jsonb; amount bigint:=0; qty integer; unit_price integer;
 item_name text; ids uuid[]; expected uuid[]; snapshot jsonb; existing public.realeza_sales%rowtype;
begin
 if uid is null then raise exception 'Entre na sua conta.'; end if;
 if jsonb_typeof(payload) is distinct from 'object' then raise exception 'Pedido inválido.'; end if;
 -- Serializa todas as alterações do mesmo usuário, inclusive venda versus fechamento.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(uid::text,0));
 if action='initial_products' then
  if exists(select 1 from public.realeza_products p where p.owner=uid) then return jsonb_build_object('ok',true); end if;
  if jsonb_typeof(payload->'products') is distinct from 'array' then raise exception 'Catálogo inválido.'; end if;
  if jsonb_array_length(payload->'products')>200 then raise exception 'Catálogo muito grande.'; end if;
  qty:=0;
  for line in select value from jsonb_array_elements(payload->'products') loop
   if coalesce(length(trim(line->>'name')),0) not between 1 and 100 or coalesce(line->>'price','') !~ '^[0-9]{1,9}$' then raise exception 'Produto inválido.'; end if;
   unit_price:=(line->>'price')::integer;
   if unit_price not between 1 and 100000000 then raise exception 'Preço inválido.'; end if;
   insert into public.realeza_products(owner,name,price,sort_order) values(uid,trim(line->>'name'),unit_price,qty);
   qty:=qty+1;
  end loop;
 elsif action='product' then
  if coalesce(length(trim(payload->>'name')),0) not between 1 and 100
     or coalesce(payload->>'price','') !~ '^[0-9]{1,9}$' then raise exception 'Informe nome e preço válidos.'; end if;
  unit_price:=(payload->>'price')::integer;
  if unit_price not between 1 and 100000000 then raise exception 'Preço inválido.'; end if;
  if payload->>'id' is null then
   select coalesce(max(p.sort_order),-1)+1 into qty from public.realeza_products p where p.owner=uid;
   insert into public.realeza_products(owner,name,price,sort_order) values(uid,trim(payload->>'name'),unit_price,qty);
  else
   update public.realeza_products set name=trim(payload->>'name'),price=unit_price where id=(payload->>'id')::uuid and owner=uid;
   if not found then raise exception 'Produto indisponível.'; end if;
  end if;
 elsif action='archive' then
  update public.realeza_products set active=0 where id=(payload->>'id')::uuid and owner=uid;
  if not found then raise exception 'Produto indisponível.'; end if;
 elsif action='reorder' then
  if jsonb_typeof(payload->'ids') is distinct from 'array' then raise exception 'Lista inválida.'; end if;
  select array_agg(value::uuid order by value) into ids from jsonb_array_elements_text(payload->'ids');
  select array_agg(p.id order by p.id) into expected from public.realeza_products p where p.owner=uid and p.active=1;
  if ids is distinct from expected then raise exception 'A lista mudou. Atualize e tente novamente.'; end if;
  update public.realeza_products p set sort_order=(a.ordinality-1)::integer
  from jsonb_array_elements_text(payload->'ids') with ordinality a(value,ordinality)
  where p.id=a.value::uuid and p.owner=uid and p.active=1;
 elsif action='close' then
  if coalesce(payload->>'day','') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Data inválida.'; end if;
  selected_day:=(payload->>'day')::date;
  if selected_day>today then raise exception 'Não é possível fechar uma data futura.'; end if;
  select jsonb_build_object('total',coalesce(sum(s.total),0),'count',count(*),
   'Pix',coalesce(sum(s.total) filter(where s.payment='Pix'),0),
   'Dinheiro',coalesce(sum(s.total) filter(where s.payment='Dinheiro'),0),
   'Débito',coalesce(sum(s.total) filter(where s.payment='Débito'),0),
   'Crédito',coalesce(sum(s.total) filter(where s.payment='Crédito'),0)) into snapshot
  from public.realeza_sales s where s.owner=uid and s.day=selected_day and s.deleted=0;
  insert into public.realeza_closings(owner,day,snapshot) values(uid,selected_day,snapshot) on conflict(owner,day) do nothing;
 elsif action in ('sale','delete') then
  target:=coalesce(payload->>'editId',payload->>'id')::uuid;
  if target is null then raise exception 'Identificador inválido.'; end if;
  if action='delete' or payload->>'editId' is not null then
   select * into old_sale from public.realeza_sales s where s.id=target and s.owner=uid;
   if not found or old_sale.deleted=1 then raise exception 'Venda indisponível.'; end if;
   if coalesce(payload->>'version','') !~ '^[0-9]+$' then raise exception 'Versão inválida.'; end if;
   if old_sale.version<>(payload->>'version')::integer then raise exception 'Venda alterada em outro aparelho. Atualize o histórico.'; end if;
   selected_day:=old_sale.day;
  else
   -- Uma tentativa repetida de pedido já salvo não cria uma segunda venda.
   select * into existing from public.realeza_sales s where s.id=target;
   if found then
    if existing.owner=uid then return jsonb_build_object('ok',true,'replayed',true); end if;
    raise exception 'Identificador indisponível.';
   end if;
   selected_day:=today;
  end if;
  if exists(select 1 from public.realeza_closings c where c.owner=uid and c.day=selected_day) then raise exception 'Dia fechado. As vendas não podem ser alteradas.'; end if;
  if action='delete' then
   update public.realeza_sales set deleted=1,version=version+1 where id=target and owner=uid;
  else
   if coalesce(payload->>'payment','') not in ('Pix','Dinheiro','Débito','Crédito') then raise exception 'Pagamento inválido.'; end if;
   if jsonb_typeof(payload->'items') is distinct from 'array' then raise exception 'Pedido inválido.'; end if;
   if jsonb_array_length(payload->'items') not between 1 and 100 then raise exception 'Pedido inválido.'; end if;
   if (select count(*)<>count(distinct x->>'id') from jsonb_array_elements(payload->'items') x) then raise exception 'Produto repetido no pedido.'; end if;
   for line in select value from jsonb_array_elements(payload->'items') loop
    if coalesce(line->>'qty','') !~ '^[0-9]{1,4}$' then raise exception 'Quantidade inválida.'; end if;
    qty:=(line->>'qty')::integer;
    if qty not between 1 and 1000 then raise exception 'Quantidade inválida.'; end if;
    select * into product from public.realeza_products p where p.id=(line->>'id')::uuid and p.owner=uid;
    if not found then raise exception 'Produto indisponível.'; end if;
    previous:=null;
    if old_sale.id is not null then select value into previous from jsonb_array_elements(old_sale.items) where value->>'id'=product.id::text; end if;
    if product.active=0 and previous is null then raise exception 'Produto arquivado.'; end if;
    unit_price:=coalesce((previous->>'price')::integer,product.price);
    item_name:=coalesce(previous->>'name',product.name);
    amount:=amount+unit_price::bigint*qty;
    prepared:=prepared||jsonb_build_array(jsonb_build_object('id',product.id,'name',item_name,'price',unit_price,'qty',qty));
   end loop;
   if amount not between 1 and 100000000 then raise exception 'Total inválido.'; end if;
   if old_sale.id is null then
    insert into public.realeza_sales(id,owner,day,payment,items,total) values(target,uid,selected_day,payload->>'payment',prepared,amount::integer);
   else
    update public.realeza_sales set items=prepared,total=amount::integer,payment=payload->>'payment',version=version+1 where id=target and owner=uid;
   end if;
  end if;
 else raise exception 'Ação inválida.';
 end if;
 insert into public.realeza_audit(owner,action,details) values(uid,action,jsonb_build_object('request',payload,'before',case when old_sale.id is not null then to_jsonb(old_sale) else null end));
 return jsonb_build_object('ok',true);
end; $$;
revoke all on function public.realeza_snapshot() from public,anon;
revoke all on function public.realeza_command(jsonb) from public,anon;
grant execute on function public.realeza_snapshot() to authenticated;
grant execute on function public.realeza_command(jsonb) to authenticated;
commit;

-- Pode ser aplicado ao banco existente. Não altera as vendas cadastradas.
begin;
create or replace function public.realeza_reopen_day(target_day date) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); previous_closing public.realeza_closings%rowtype;
begin
 if uid is null then raise exception 'Entre na sua conta.'; end if;
 if target_day is null or target_day>(now() at time zone 'America/Sao_Paulo')::date then raise exception 'Data inválida.'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(uid::text,0));
 select * into previous_closing from public.realeza_closings c where c.owner=uid and c.day=target_day;
 if not found then return jsonb_build_object('ok',true,'alreadyOpen',true); end if;
 insert into public.realeza_audit(owner,action,details) values(uid,'reopen',jsonb_build_object('day',target_day,'previousClosing',to_jsonb(previous_closing)));
 delete from public.realeza_closings c where c.owner=uid and c.day=target_day;
 return jsonb_build_object('ok',true);
end; $$;
revoke all on function public.realeza_reopen_day(date) from public,anon;
grant execute on function public.realeza_reopen_day(date) to authenticated;
commit;

begin;
create table public.realeza_openings (
 owner uuid not null references auth.users(id), day date not null,
 created timestamptz not null default now(), initial_cash integer not null check(initial_cash between 0 and 100000000),
 primary key(owner,day)
);
alter table public.realeza_openings enable row level security;
create policy own_openings on public.realeza_openings for select to authenticated using(owner=(select auth.uid()));
revoke all on public.realeza_openings from anon,authenticated;
grant select on public.realeza_openings to authenticated;

-- A função antiga fica privada; toda escrita passa pela abertura e pela contagem.
alter function public.realeza_command(jsonb) rename to realeza_command_base;
revoke all on function public.realeza_command_base(jsonb) from public,anon,authenticated;
create function public.realeza_command(payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); action text:=payload->>'action'; selected_day date;
 opening public.realeza_openings%rowtype; initial_value integer; counted integer; expected bigint;
 result jsonb; closing_snapshot jsonb;
begin
 if uid is null then raise exception 'Entre na sua conta.'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(uid::text,0));
 if action='open' then
  if coalesce(payload->>'day','') !~ '^\d{4}-\d{2}-\d{2}$' or coalesce(payload->>'initial_cash','') !~ '^[0-9]{1,9}$' then raise exception 'Informe a data e o valor inicial em dinheiro.'; end if;
  selected_day:=(payload->>'day')::date; initial_value:=(payload->>'initial_cash')::integer;
  if selected_day>(now() at time zone 'America/Sao_Paulo')::date or initial_value not between 0 and 100000000 then raise exception 'Data ou valor inicial inválido.'; end if;
  if exists(select 1 from public.realeza_closings c where c.owner=uid and c.day=selected_day) then raise exception 'Reabra o dia fechado antes de informar a abertura.'; end if;
  select * into opening from public.realeza_openings o where o.owner=uid and o.day=selected_day;
  if found then
   if opening.initial_cash=initial_value then return jsonb_build_object('ok',true,'alreadyOpen',true); end if;
   raise exception 'A abertura já foi registrada em outro aparelho. Atualize a tela.';
  end if;
  insert into public.realeza_openings(owner,day,initial_cash) values(uid,selected_day,initial_value);
  insert into public.realeza_audit(owner,action,details) values(uid,'open',jsonb_build_object('day',selected_day,'initial_cash',initial_value));
  return jsonb_build_object('ok',true);
 end if;
 if action='sale' and payload->>'editId' is null then
  -- Uma venda confirmada antes desta atualização continua idempotente.
  if not exists(select 1 from public.realeza_sales s where s.owner=uid and s.id=(payload->>'id')::uuid)
   and not exists(select 1 from public.realeza_openings o where o.owner=uid and o.day=(now() at time zone 'America/Sao_Paulo')::date)
  then raise exception 'Abra o caixa e informe o dinheiro inicial antes de vender.'; end if;
 end if;
 if action='close' then
  if coalesce(payload->>'day','') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Data inválida.'; end if;
  selected_day:=(payload->>'day')::date;
  if exists(select 1 from public.realeza_closings c where c.owner=uid and c.day=selected_day) then return jsonb_build_object('ok',true,'alreadyClosed',true); end if;
  select * into opening from public.realeza_openings o where o.owner=uid and o.day=selected_day;
  if not found then raise exception 'Informe o dinheiro inicial para este dia antes de fechar.'; end if;
  if coalesce(payload->>'counted_cash','') !~ '^[0-9]{1,9}$' then raise exception 'Informe quanto dinheiro foi contado no caixa.'; end if;
  counted:=(payload->>'counted_cash')::integer;
  if counted not between 0 and 100000000 then raise exception 'Valor contado inválido.'; end if;
  result:=public.realeza_command_base(payload);
  select snapshot into closing_snapshot from public.realeza_closings c where c.owner=uid and c.day=selected_day;
  expected:=opening.initial_cash::bigint+(closing_snapshot->>'Dinheiro')::bigint;
  update public.realeza_closings c set snapshot=c.snapshot||jsonb_build_object('initial_cash',opening.initial_cash,'expected_cash',expected,'counted_cash',counted,'cash_difference',counted-expected)
  where c.owner=uid and c.day=selected_day;
  return result;
 end if;
 return public.realeza_command_base(payload);
end; $$;
revoke all on function public.realeza_command(jsonb) from public,anon;
grant execute on function public.realeza_command(jsonb) to authenticated;

alter function public.realeza_snapshot() rename to realeza_snapshot_base;
revoke all on function public.realeza_snapshot_base() from public,anon,authenticated;
create function public.realeza_snapshot() returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();
begin
 if uid is null then raise exception 'Entre na sua conta.'; end if;
 return public.realeza_snapshot_base()||jsonb_build_object('openings',coalesce((select jsonb_agg(to_jsonb(o) order by o.day) from public.realeza_openings o where o.owner=uid),'[]'::jsonb));
end; $$;
revoke all on function public.realeza_snapshot() from public,anon;
grant execute on function public.realeza_snapshot() to authenticated;
commit;

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
