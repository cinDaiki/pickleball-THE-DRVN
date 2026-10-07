begin;
create function public.drvn_save_event(p_actor uuid,p_event jsonb,p_categories jsonb) returns uuid language plpgsql set search_path=public as $$
declare eid uuid; x jsonb; cid uuid; old drvn_categories; used int;begin
if not exists(select 1 from drvn_admins where user_id=p_actor) then raise exception 'Admin required';end if;
eid=coalesce(nullif(p_event->>'id','')::uuid,gen_random_uuid());
if p_event->>'status'='cancelled' then raise exception 'Use cancel event to notify players';end if;
insert into drvn_tournaments(id,title,description,cover_url,cover_alt,gallery,starts_at,venue,address,map_url,rules,opens_at,closes_at,status,featured)
values(eid,p_event->>'title',coalesce(p_event->>'description',''),coalesce(p_event->>'cover_url',''),coalesce(p_event->>'cover_alt',''),coalesce(p_event->'gallery','[]'),(p_event->>'starts_at')::timestamptz,coalesce(p_event->>'venue',''),coalesce(p_event->>'address',''),coalesce(p_event->>'map_url',''),coalesce(p_event->>'rules',''),(p_event->>'opens_at')::timestamptz,(p_event->>'closes_at')::timestamptz,coalesce(p_event->>'status','draft'),coalesce((p_event->>'featured')::boolean,false))
on conflict(id) do update set title=excluded.title,description=excluded.description,cover_url=excluded.cover_url,cover_alt=excluded.cover_alt,gallery=excluded.gallery,starts_at=excluded.starts_at,venue=excluded.venue,address=excluded.address,map_url=excluded.map_url,rules=excluded.rules,opens_at=excluded.opens_at,closes_at=excluded.closes_at,status=excluded.status,featured=excluded.featured,updated_at=now();
if jsonb_array_length(p_categories)<1 then raise exception 'Add at least one category';end if;
for x in select * from jsonb_array_elements(p_categories) loop
cid=coalesce(nullif(x->>'id','')::uuid,gen_random_uuid());
select * into old from drvn_categories where id=cid for update;
if found and old.tournament_id<>eid then raise exception 'Category belongs to another event';end if;
if old.id is not null and exists(select 1 from drvn_registrations where category_id=cid) and (old.fee_cents<>(x->>'fee_cents')::int or old.unit<>x->>'unit') then raise exception 'Fee and entry type cannot change after registration';end if;
select count(*) into used from drvn_registrations where category_id=cid and status in ('awaiting_payment','under_review','confirmed','correction_requested') and not(status='awaiting_payment' and expires_at<now());
if used>(x->>'capacity')::int then raise exception 'Capacity cannot be below reserved entries';end if;
insert into drvn_categories(id,tournament_id,name,unit,fee_cents,capacity,active) values(cid,eid,x->>'name',x->>'unit',(x->>'fee_cents')::int,(x->>'capacity')::int,coalesce((x->>'active')::boolean,true)) on conflict(id) do update set name=excluded.name,unit=excluded.unit,fee_cents=excluded.fee_cents,capacity=excluded.capacity,active=excluded.active;
end loop;
insert into drvn_audit(actor,action,subject) values(p_actor,'event_saved',eid);return eid;end $$;
create function public.drvn_entry_action(p_actor uuid,p_id uuid,p_action text,p_note text) returns void language plpgsql set search_path=public as $$
declare r drvn_registrations;c drvn_categories;s drvn_settings;n int;begin
if not exists(select 1 from drvn_admins where user_id=p_actor) then raise exception 'Admin required';end if;
select * into r from drvn_registrations where id=p_id;
select * into c from drvn_categories where id=r.category_id for update;
select * into r from drvn_registrations where id=p_id for update;
if not found then raise exception 'Entry not found';end if;
if p_action='promote' then
if r.status<>'waitlisted' then raise exception 'Entry is not waitlisted';end if;
if not exists(select 1 from drvn_tournaments where id=c.tournament_id and status='published' and closes_at>now()) then raise exception 'Registration is closed';end if;
update drvn_registrations set status='expired' where category_id=c.id and status='awaiting_payment' and expires_at<now();
select count(*) into n from drvn_registrations where category_id=c.id and status in ('awaiting_payment','under_review','confirmed','correction_requested');
if n>=c.capacity then raise exception 'No slot available';end if;
select * into s from drvn_settings where id;
update drvn_registrations set status=case when amount_due=0 then 'confirmed' else 'awaiting_payment' end,payment_status=case when amount_due=0 then 'verified' else 'unpaid' end,expires_at=now()+make_interval(hours=>s.reservation_hours) where id=r.id;
else
if length(trim(p_note))<3 then raise exception 'Provide a reason or refund reference';end if;
if p_action='cancel' then update drvn_registrations set status='cancelled' where id=r.id;
elsif p_action='refund' and r.payment_status='verified' then update drvn_registrations set status='cancelled',payment_status='refunded' where id=r.id;
else raise exception 'Invalid action';end if;
end if;
insert into drvn_audit(actor,action,subject,detail) values(p_actor,'entry_'||p_action,r.id,jsonb_build_object('note',p_note));
insert into drvn_email_queue(registration_id,kind,note) values(r.id,'entry_'||p_action,p_note);end $$;
create function public.drvn_cancel_event(p_actor uuid,p_id uuid,p_note text) returns void language plpgsql set search_path=public as $$ begin
if not exists(select 1 from drvn_admins where user_id=p_actor) then raise exception 'Admin required';end if;
if length(trim(p_note))<3 then raise exception 'Provide a cancellation reason';end if;
perform id from drvn_categories where tournament_id=p_id order by id for update;
update drvn_tournaments set status='cancelled',updated_at=now() where id=p_id;
insert into drvn_email_queue(registration_id,kind,note) select r.id,'event_cancelled',p_note from drvn_registrations r join drvn_categories c on c.id=r.category_id where c.tournament_id=p_id and r.status<>'cancelled';
update drvn_registrations r set status='cancelled' from drvn_categories c where c.id=r.category_id and c.tournament_id=p_id;
insert into drvn_audit(actor,action,subject,detail) values(p_actor,'event_cancelled',p_id,jsonb_build_object('note',p_note));end $$;
do $$ declare f record;begin for f in select oid::regprocedure sig from pg_proc where pronamespace='public'::regnamespace and proname like 'drvn_%' loop execute format('revoke all on function %s from public,anon,authenticated',f.sig);execute format('grant execute on function %s to service_role',f.sig);end loop;end $$;
commit;
