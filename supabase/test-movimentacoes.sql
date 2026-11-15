-- Teste integral revertido ao final. Não mantém lançamentos nem altera vendas reais.
begin;
do $$
declare uid uuid; day_value date:=(now() at time zone 'America/Sao_Paulo')::date;
 product_id uuid; withdrawal_id uuid:=gen_random_uuid(); consumption_id uuid:=gen_random_uuid();
 base_cash bigint; expected bigint; result jsonb; closing_snapshot jsonb; sale_count bigint; rejected boolean:=false;
begin
 select id into uid from auth.users order by created_at limit 1;
 if uid is null then raise exception 'Crie um usuário antes de testar.'; end if;
 perform set_config('request.jwt.claim.sub',uid::text,true);
 delete from public.realeza_closings where owner=uid and day=day_value;
 delete from public.realeza_openings where owner=uid and day=day_value;
 delete from public.realeza_movements where owner=uid and day=day_value;
 select coalesce(sum(total),0),count(*) into base_cash,sale_count from public.realeza_sales where owner=uid and day=day_value and deleted=0 and payment='Dinheiro';
 select count(*) into sale_count from public.realeza_sales where owner=uid and day=day_value;
 insert into public.realeza_products(owner,name,price) values(uid,'COCO TESTE MOVIMENTO',700) returning id into product_id;
 perform public.realeza_command(jsonb_build_object('action','open','day',day_value,'initial_cash',10000));
 perform public.realeza_command(jsonb_build_object('action','movement','id',withdrawal_id,'day',day_value,'kind','withdrawal','amount',1500,'description','Compra de gelo TESTE'));
 perform public.realeza_command(jsonb_build_object('action','movement','id',withdrawal_id,'day',day_value,'kind','withdrawal','amount',1500,'description','Compra de gelo TESTE'));
 if (select count(*) from public.realeza_movements where id=withdrawal_id)<>1 then raise exception 'Retirada duplicada.'; end if;
 perform public.realeza_command(jsonb_build_object('action','movement','id',consumption_id,'day',day_value,'kind','consumption','product_id',product_id,'qty',3,'description','Consumo interno TESTE'));
 if sale_count<>(select count(*) from public.realeza_sales where owner=uid and day=day_value) then raise exception 'Consumo não pode gerar venda.'; end if;
 expected:=10000+base_cash-1500;
 perform public.realeza_command(jsonb_build_object('action','close','day',day_value,'counted_cash',greatest(expected,0)));
 select snapshot into closing_snapshot from public.realeza_closings where owner=uid and day=day_value;
 if (closing_snapshot->>'expected_cash')::bigint<>expected or (closing_snapshot->>'cash_withdrawals')::bigint<>1500 then raise exception 'Retirada não descontada corretamente.'; end if;
 if jsonb_array_length(closing_snapshot->'consumptions')<>1 or (closing_snapshot->'consumptions'->0->>'qty')::integer<>3 then raise exception 'Consumo não registrado no relatório.'; end if;
 begin
  perform public.realeza_command(jsonb_build_object('action','void_movement','id',withdrawal_id));
 exception when raise_exception then rejected:=true;
 end;
 if not rejected then raise exception 'Dia fechado deve bloquear cancelamentos.'; end if;
 perform public.realeza_reopen_day(day_value);
 perform public.realeza_command(jsonb_build_object('action','void_movement','id',withdrawal_id));
 if not exists(select 1 from public.realeza_movements where id=withdrawal_id and voided=1) then raise exception 'Cancelamento deve manter o lançamento.'; end if;
 expected:=10000+base_cash;
 perform public.realeza_command(jsonb_build_object('action','close','day',day_value,'counted_cash',expected));
 select snapshot into closing_snapshot from public.realeza_closings where owner=uid and day=day_value;
 if (closing_snapshot->>'cash_withdrawals')::bigint<>0 or (closing_snapshot->>'expected_cash')::bigint<>expected then raise exception 'Cancelamento não atualizou o caixa.'; end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
 result:=public.realeza_snapshot();
 if jsonb_array_length(result->'movements')<>0 then raise exception 'Lançamentos de outro usuário expostos.'; end if;
 if has_function_privilege('authenticated','public.realeza_command_cash_base(jsonb)','EXECUTE') then raise exception 'Acesso indevido à função base.'; end if;
end; $$;
rollback;
select 'PASSOU: retiradas descontadas, consumo sem venda, relatório, repetição, cancelamento com registro, bloqueio após fechar e isolamento. Todos os testes revertidos.' as resultado;
