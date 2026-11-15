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
