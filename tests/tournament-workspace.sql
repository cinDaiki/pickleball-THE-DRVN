-- Rollback-only fixtures. No player notifications are sent by this script.
begin;
do $$
declare actor uuid; a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); ca uuid:=gen_random_uuid(); ct uuid:=gen_random_uuid(); cb uuid:=gen_random_uuid(); rid uuid; summary jsonb; result jsonb; seen int:=0;
begin
 select user_id into actor from public.drvn_admins limit 1;
 if actor is null then raise exception 'Authorized admin required for test';end if;
 insert into public.drvn_tournaments(id,title,starts_at,opens_at,closes_at,status)
 values(a,'Workspace A',now()+interval '3 days',now()-interval '1 day',now()+interval '2 days','published'),(b,'Workspace B',now()+interval '3 days',now()-interval '1 day',now()+interval '2 days','draft');
 insert into public.drvn_categories(id,tournament_id,name,unit,fee_cents,capacity)
 values(ca,a,'Singles','individual',10000,101),(ct,a,'Doubles','team',10000,101),(cb,b,'Separate event','individual',90000,10);
 for i in 1..202 loop
  insert into public.drvn_registrations(category_id,player_name,email,partner_name,amount_due,unit,status,payment_status,token_hash,idempotency_key,settings_snapshot,expires_at)
  values(case when i<=100 or i=201 then ca else ct end,'Player '||i,'workspace-'||i||'@example.test',case when i>100 and i<>201 then 'Partner '||i else '' end,10000,case when i<=100 or i=201 then 'individual' else 'team' end,case when i=2 then 'cancelled' when i=3 then 'under_review' when i=201 then 'awaiting_payment' when i=202 then 'waitlisted' else 'confirmed' end,case when i=2 then 'refunded' when i=3 then 'submitted' when i>200 then 'unpaid' else 'verified' end,gen_random_uuid()::text,gen_random_uuid(),'{}',case when i=201 then now()-interval '1 day' else now()+interval '1 day' end) returning id into rid;
  if i<=3 then insert into public.drvn_payments(registration_id,reference,amount_cents,paid_at,sender_name,receipt_path,status) values(rid,gen_random_uuid()::text,10000,now(),'Fixture','test/receipt.jpg',case when i=3 then 'submitted' else 'verified' end);end if;
 end loop;
 insert into public.drvn_registrations(category_id,player_name,email,amount_due,unit,status,payment_status,token_hash,idempotency_key,settings_snapshot)
 values(cb,'Other player','other@example.test',90000,'individual','confirmed','verified',gen_random_uuid()::text,gen_random_uuid(),'{}') returning id into rid;
 insert into public.drvn_payments(registration_id,reference,amount_cents,paid_at,sender_name,receipt_path,status) values(rid,gen_random_uuid()::text,90000,now(),'Other','test/other.jpg','verified');
 summary:=public.drvn_tournament_summary(actor,a);
 if (summary->>'registrations')::int<>202 or (summary->>'confirmed')::int<>198 or (summary->>'confirmed_players')::int<>298 then raise exception 'Entry/player counts failed: %',summary;end if;
 if (summary->>'collections')::int<>10000 or (summary->>'refunds')::int<>10000 or (summary->>'pending')::int<>1 then raise exception 'Payment scope/refund failed';end if;
 if (summary->>'available')::int<>3 or (summary->>'waitlisted')::int<>1 or (summary->'statuses'->>'expired')::int<>1 then raise exception 'Capacity/expiry failed: %',summary;end if;
 if jsonb_array_length(summary->'categories')<>2 then raise exception 'Categories crossed events';end if;
 for i in 1..9 loop
  result:=public.drvn_admin_list(actor,'Registrations',i,'','',a,25);seen:=seen+jsonb_array_length(result->'rows');
  if exists(select 1 from jsonb_array_elements(result->'rows') r where r->>'tournament_title'<>'Workspace A') then raise exception 'Cross-event registration leak';end if;
 end loop;
 if seen<>202 then raise exception 'Pagination lost records';end if;
 result:=public.drvn_admin_list(actor,'Payments',1,'','',a,25);
 if (result->>'total')::int<>3 then raise exception 'Payments crossed events';end if;
 summary:=public.drvn_tournament_summary(actor,b);
 if (summary->>'registrations')::int<>1 or (summary->>'collections')::int<>90000 then raise exception 'Other event summary failed';end if;
 begin perform public.drvn_tournament_summary(gen_random_uuid(),a);raise exception 'Unauthorized summary allowed';exception when others then if sqlerrm='Unauthorized summary allowed' then raise;end if;end;
 begin perform public.drvn_tournament_summary(actor,gen_random_uuid());raise exception 'Missing event accepted';exception when others then if sqlerrm='Missing event accepted' then raise;end if;end;
 if has_function_privilege('anon','public.drvn_tournament_summary(uuid,uuid)','EXECUTE') or has_function_privilege('authenticated','public.drvn_tournament_summary(uuid,uuid)','EXECUTE') then raise exception 'Summary exposed to client';end if;
end $$;
rollback;
