-- Todos os registros e alterações são revertidos ao final.
begin;
do $$
declare uid uuid; day_value date:=(now() at time zone 'America/Sao_Paulo')::date;
 product_id uuid; sale_id uuid:=gen_random_uuid(); base_cash bigint; expected bigint;
 rejected boolean:=false; result jsonb; snapshot jsonb; initial_count bigint;
begin
 select id into uid from auth.users order by created_at limit 1;
 if uid is null then raise exception 'Crie um usuário antes do teste.'; end if;
 perform set_config('request.jwt.claim.sub',uid::text,true);
 -- Alterações abaixo só existem dentro desta transação, que termina em ROLLBACK.
 delete from public.realeza_closings where owner=uid and day=day_value;
 delete from public.realeza_openings where owner=uid and day=day_value;
 select coalesce(sum(total),0) into base_cash from public.realeza_sales where owner=uid and day=day_value and deleted=0 and payment='Dinheiro';
 insert into public.realeza_products(owner,name,price) values(uid,'TESTE ABERTURA',1100) returning id into product_id;
 begin
  perform public.realeza_command(jsonb_build_object('action','sale','id',sale_id,'payment','Dinheiro','items',jsonb_build_array(jsonb_build_object('id',product_id,'qty',1))));
 exception when raise_exception then rejected:=true;
 end;
 if not rejected then raise exception 'Venda sem abertura deveria ser bloqueada.'; end if;
 perform public.realeza_command(jsonb_build_object('action','open','day',day_value,'initial_cash',5000));
 perform public.realeza_command(jsonb_build_object('action','open','day',day_value,'initial_cash',5000));
 select count(*) into initial_count from public.realeza_openings where owner=uid and day=day_value;
 if initial_count<>1 then raise exception 'Abertura duplicada.'; end if;
 perform public.realeza_command(jsonb_build_object('action','sale','id',sale_id,'payment','Dinheiro','items',jsonb_build_array(jsonb_build_object('id',product_id,'qty',1))));
 perform public.realeza_command(jsonb_build_object('action','sale','id',gen_random_uuid(),'payment','Pix','items',jsonb_build_array(jsonb_build_object('id',product_id,'qty',2))));
 expected:=5000+base_cash+1100;
 rejected:=false;
 begin
  perform public.realeza_command(jsonb_build_object('action','close','day',day_value));
 exception when raise_exception then rejected:=true;
 end;
 if not rejected then raise exception 'Fechamento sem contagem deveria ser bloqueado.'; end if;
 perform public.realeza_command(jsonb_build_object('action','close','day',day_value,'counted_cash',expected+200));
 select c.snapshot into snapshot from public.realeza_closings c where c.owner=uid and c.day=day_value;
 if (snapshot->>'expected_cash')::bigint<>expected or (snapshot->>'cash_difference')::bigint<>200 then raise exception 'Erro no esperado ou sobra.'; end if;
 perform public.realeza_reopen_day(day_value);
 if (select initial_cash from public.realeza_openings where owner=uid and day=day_value)<>5000 then raise exception 'Reabertura perdeu o dinheiro inicial.'; end if;
 perform public.realeza_command(jsonb_build_object('action','close','day',day_value,'counted_cash',expected-100));
 select c.snapshot into snapshot from public.realeza_closings c where c.owner=uid and c.day=day_value;
 if (snapshot->>'expected_cash')::bigint<>expected or (snapshot->>'cash_difference')::bigint<>-100 then raise exception 'Valor inicial duplicado ou falta incorreta.'; end if;
 if has_function_privilege('authenticated','public.realeza_command_base(jsonb)','EXECUTE') then raise exception 'Função base não deve estar acessível.'; end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
 result:=public.realeza_snapshot();
 if jsonb_array_length(result->'openings')<>0 then raise exception 'Abertura de outro usuário exposta.'; end if;
end; $$;
rollback;
select 'PASSOU: abertura, bloqueio sem abertura, dinheiro/Pix separados, contagem obrigatória, sobra, falta, reabertura sem duplicação e proteção por usuário. Testes revertidos.' as resultado;
