begin;
set local role service_role;
do $$
declare actor uuid := 'ee6e2514-a985-4fa6-b790-2ca3c11ed163'; eid uuid:=gen_random_uuid(); cid uuid:=gen_random_uuid(); k uuid; r public.drvn_registrations; first_key uuid; first_id uuid; n int; result jsonb; started timestamptz:=clock_timestamp();begin
insert into public.drvn_tournaments(id,title,starts_at,opens_at,closes_at,status) values(eid,'Capacity regression fixture',now()+interval '3 days',now()-interval '1 day',now()+interval '2 days','published');
insert into public.drvn_categories(id,tournament_id,name,unit,fee_cents,capacity) values(cid,eid,'200 players','individual',0,200);
for i in 1..200 loop
k:=gen_random_uuid();r:=public.drvn_register(cid,'Simulated player '||i,'capacity-'||i||'@example.test','',k::text,k,false);
if r.status<>'confirmed' then raise exception 'Player % not confirmed',i;end if;
if i=1 then first_key:=k;first_id:=r.id;end if;
if not public.drvn_throttle('test-shared-network-'||eid,600) then raise exception 'Shared-network throttle blocked player %',i;end if;
end loop;
r:=public.drvn_register(cid,'Simulated player 1','capacity-1@example.test','',first_key::text,first_key,false);
if r.id<>first_id then raise exception 'Retry created a duplicate';end if;
begin k:=gen_random_uuid();perform public.drvn_register(cid,'Over capacity','full@example.test','',k::text,k,false);raise exception 'Overbooking accepted';exception when others then if sqlerrm not like '%full%' then raise;end if;end;
k:=gen_random_uuid();r:=public.drvn_register(cid,'Waitlisted','waitlist@example.test','',k::text,k,true);
if r.status<>'waitlisted' then raise exception 'Waitlist not used';end if;
for i in 1..8 loop
result:=public.drvn_admin_list(actor,'Registrations',i,'','confirmed',eid,25);
if (result->>'total')::int<>200 or jsonb_array_length(result->'rows')<>25 then raise exception 'Pagination failed on page %',i;end if;
end loop;
select count(*) into n from public.drvn_email_queue q join public.drvn_registrations x on x.id=q.registration_id where x.category_id=cid;
if n<>201 then raise exception 'Missing or duplicate confirmation queues: %',n;end if;
perform public.drvn_admin_list(actor,'Payments',1,'','',eid,25);
perform public.drvn_admin_list(actor,'Emails',1,'','',eid,25);
perform public.drvn_admin_list(actor,'Activity');
perform public.drvn_admin_summary(actor);
result:=public.drvn_public_events();
if not exists(select 1 from jsonb_array_elements(result) t,jsonb_array_elements(t->'categories') c where t->>'id'=eid::text and c->>'id'=cid::text and (c->>'available')::int=0) then raise exception 'Availability must be zero';end if;
insert into public.drvn_audit(action,detail) values('capacity_test_result',jsonb_build_object('players',200,'waitlist',1,'pages',8,'queued',n,'elapsed_ms',extract(epoch from clock_timestamp()-started)*1000));
end $$;
select detail from public.drvn_audit where action='capacity_test_result' order by id desc limit 1;
rollback;
