begin;
do $$
declare a uuid=gen_random_uuid();t uuid;c uuid;c2 uuid;r drvn_registrations;r2 drvn_registrations;p uuid;begin
insert into auth.users(id,email) values(a,'drvn-test@example.invalid');insert into drvn_admins(user_id) values(a);
update drvn_settings set gcash_name='TEST ONLY',gcash_number='00000000000',gcash_qr='/assets/court.jpg';
t=drvn_save_event(a,jsonb_build_object('title','TEST ONLY','starts_at',now()+interval '5 days','opens_at',now()-interval '1 day','closes_at',now()+interval '4 days','status','published'),jsonb_build_array(jsonb_build_object('name','Test','unit','individual','fee_cents',10000,'capacity',1)));
select id into c from drvn_categories where tournament_id=t;
r=drvn_register(c,'Test One','test1@example.invalid','',repeat('a',64),gen_random_uuid(),false);
if r.status<>'awaiting_payment' then raise exception 'FAIL reservation';end if;
begin perform drvn_register(c,'Test Two','test2@example.invalid','',repeat('b',64),gen_random_uuid(),false);raise exception 'FAIL capacity';exception when others then if sqlerrm='FAIL capacity' then raise;end if;end;
r2=drvn_register(c,'Test Two','test2@example.invalid','',repeat('c',64),gen_random_uuid(),true);
if r2.status<>'waitlisted' then raise exception 'FAIL waitlist';end if;
p=drvn_submit_payment(r.id,'1234567890123',10000,now(),'Tester','test.jpg');perform drvn_review(p,a,'verified','Transaction matched');
if not exists(select 1 from drvn_registrations where id=r.id and status='confirmed' and payment_status='verified') then raise exception 'FAIL approval';end if;
begin perform drvn_review(p,a,'verified','');raise exception 'FAIL repeated review';exception when others then if sqlerrm='FAIL repeated review' then raise;end if;end;
perform drvn_entry_action(a,r.id,'refund','TEST REFUND');perform drvn_entry_action(a,r2.id,'promote','');
p=drvn_submit_payment(r2.id,'1234567890123',10000,now(),'Tester','test2.jpg');
begin perform drvn_review(p,a,'verified','Matched');raise exception 'FAIL duplicate reference';exception when unique_violation then null;end;
perform drvn_review(p,a,'correction_requested','Wrong reference');
perform drvn_cancel_event(a,t,'Test cancellation');
if exists(select 1 from drvn_registrations where category_id=c and status<>'cancelled') then raise exception 'FAIL cancellation';end if;
if not exists(select 1 from drvn_email_queue where registration_id=r.id) then raise exception 'FAIL email queue';end if;
-- A late payer must not displace a newer reservation.
t=drvn_save_event(a,jsonb_build_object('title','TEST LATE','starts_at',now()+interval '5 days','opens_at',now()-interval '1 day','closes_at',now()+interval '4 days','status','published'),jsonb_build_array(jsonb_build_object('name','Late test','unit','individual','fee_cents',10000,'capacity',1)));
select id into c2 from drvn_categories where tournament_id=t;
r=drvn_register(c2,'Late payer','late@example.invalid','',repeat('d',64),gen_random_uuid(),false);
update drvn_registrations set expires_at=now()-interval '1 hour' where id=r.id;
r2=drvn_register(c2,'New player','new@example.invalid','',repeat('e',64),gen_random_uuid(),false);
p=drvn_submit_payment(r.id,'9999999999999',10000,now(),'Tester','late.jpg');
begin perform drvn_review(p,a,'verified','Matched');raise exception 'FAIL late overbooking';exception when others then if sqlerrm not like 'No slot available%' then raise;end if;end;
perform drvn_entry_action(a,r2.id,'cancel','Test cancellation');
perform drvn_review(p,a,'verified','Slot now available');
if has_table_privilege('anon','public.drvn_registrations','SELECT') or has_table_privilege('authenticated','public.drvn_payments','SELECT') then raise exception 'FAIL private table access';end if;
if has_function_privilege('anon','public.drvn_review(uuid,uuid,text,text)','EXECUTE') then raise exception 'FAIL public review access';end if;
end $$;
rollback;
