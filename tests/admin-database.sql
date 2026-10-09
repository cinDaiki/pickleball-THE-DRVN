begin;
do $$
declare actor uuid; event_id uuid:=gen_random_uuid(); category_id uuid:=gen_random_uuid(); registration_id uuid; payment_id uuid; result jsonb; total int;begin
select user_id into actor from public.drvn_admins a join auth.users u on u.id=a.user_id where u.email='xdqwerts@gmail.com';
if actor is null then raise exception 'Test requires existing authorized organizer';end if;
insert into public.drvn_tournaments(id,title,starts_at,opens_at,closes_at,status) values(event_id,'Pagination test',now()+interval '3 days',now()-interval '1 day',now()+interval '2 days','published');
insert into public.drvn_categories(id,tournament_id,name,unit,fee_cents,capacity) values(category_id,event_id,'Open','individual',10000,100);
for i in 1..27 loop
insert into public.drvn_registrations(category_id,player_name,email,amount_due,unit,status,payment_status,token_hash,idempotency_key,settings_snapshot,expires_at) values(category_id,'Test player '||i,'paging-'||i||'@example.test',10000,'individual','under_review','submitted',gen_random_uuid()::text,gen_random_uuid(),'{}',now()+interval '1 day') returning id into registration_id;
end loop;
result:=public.drvn_admin_list(actor,'Registrations',1,'','',event_id,25);
if (result->>'total')::int<>27 or jsonb_array_length(result->'rows')<>25 then raise exception 'First page failed';end if;
if (result->'rows'->0) ? 'token_hash' or (result->'rows'->0) ? 'idempotency_key' then raise exception 'Private fields leaked';end if;
result:=public.drvn_admin_list(actor,'Registrations',2,'','',event_id,25);
if jsonb_array_length(result->'rows')<>2 then raise exception 'Second page failed';end if;
result:=public.drvn_admin_list(actor,'Registrations',1,'paging-27@','',event_id,25);
if (result->>'total')::int<>1 then raise exception 'Search failed';end if;
result:=public.drvn_admin_list(actor,'Registrations',1,'','confirmed',event_id,25);
if (result->>'total')::int<>0 then raise exception 'Status filter failed';end if;
begin perform public.drvn_admin_list(gen_random_uuid(),'Registrations');raise exception 'Authorization failed';exception when others then if sqlerrm='Authorization failed' then raise;end if;end;
insert into public.drvn_payments(registration_id,reference,amount_cents,paid_at,sender_name,receipt_path) values(registration_id,'876543210987654321',10000,now(),'Test sender','test/receipt.jpg') returning id into payment_id;
perform public.drvn_review(payment_id,actor,'verified','Matched test transaction');
begin perform public.drvn_review(payment_id,actor,'verified','Repeat');raise exception 'Duplicate review accepted';exception when others then if sqlerrm='Duplicate review accepted' then raise;end if;end;
-- Queue claim must never claim the same job twice; isolate these jobs within rollback.
result:=public.drvn_admin_list(actor,'Payments',1,'876543210987654321','verified',event_id,25);
if (result->>'total')::int<>1 then raise exception 'Payment filter failed';end if;
if has_function_privilege('anon','public.drvn_admin_summary(uuid)','EXECUTE') then raise exception 'Public access exposed';end if;
end $$;
rollback;
