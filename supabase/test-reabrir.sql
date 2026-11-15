-- Teste transacional: não deixa dados de teste nem altera fechamentos reais.
begin;
do $$
declare uid uuid; result jsonb; invalid_date_rejected boolean:=false; audit_count bigint;
begin
 select id into uid from auth.users order by created_at limit 1;
 if uid is null then raise exception 'Crie um usuário antes de testar.'; end if;
 if exists(select 1 from public.realeza_closings where owner=uid and day='1900-01-01') then raise exception 'Data de teste já utilizada. Nenhuma mudança foi feita.'; end if;
 insert into public.realeza_closings(owner,day,snapshot) values(uid,'1900-01-01','{"total":1234,"count":2}');
 perform set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
 perform public.realeza_reopen_day('1900-01-01');
 if not exists(select 1 from public.realeza_closings where owner=uid and day='1900-01-01') then raise exception 'Falha na separação por usuário.'; end if;
 perform set_config('request.jwt.claim.sub',uid::text,true);
 result:=public.realeza_reopen_day('1900-01-01');
 if result->>'ok'<>'true' or exists(select 1 from public.realeza_closings where owner=uid and day='1900-01-01') then raise exception 'Falha ao reabrir.'; end if;
 if not exists(select 1 from public.realeza_audit where owner=uid and action='reopen' and details->>'day'='1900-01-01' and details->'previousClosing'->'snapshot'->>'total'='1234') then raise exception 'Fechamento anterior não foi preservado.'; end if;
 select count(*) into audit_count from public.realeza_audit where owner=uid;
 result:=public.realeza_reopen_day('1900-01-01');
 if result->>'alreadyOpen'<>'true' or audit_count<>(select count(*) from public.realeza_audit where owner=uid) then raise exception 'Reabertura repetida deve ser segura.'; end if;
 begin
  perform public.realeza_reopen_day(((now() at time zone 'America/Sao_Paulo')::date+1));
 exception when raise_exception then invalid_date_rejected:=true;
 end;
 if not invalid_date_rejected then raise exception 'Data futura deveria ser recusada.'; end if;
end; $$;
rollback;
select 'PASSOU: reabertura, auditoria, repetição, isolamento e data futura. Nenhum dado de teste foi mantido.' as resultado;
