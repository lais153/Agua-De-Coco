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
