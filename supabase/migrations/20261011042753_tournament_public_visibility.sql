begin;
alter table public.drvn_tournaments add column public_visible boolean not null default true;
-- Visibility is separate from lifecycle status. Existing entries and payment reviews remain intact.
create function public.drvn_set_visibility(p_actor uuid,p_event uuid,p_visible boolean) returns boolean
language plpgsql security invoker set search_path=public as $$
declare t drvn_tournaments;
begin
 if not exists(select 1 from drvn_admins where user_id=p_actor) then raise exception 'Admin required';end if;
 if p_visible is null then raise exception 'Choose public visibility';end if;
 select * into t from drvn_tournaments where id=p_event for update;
 if not found then raise exception 'Tournament not found';end if;
 if t.public_visible=p_visible then return p_visible;end if;
 update drvn_tournaments set public_visible=p_visible,updated_at=now() where id=p_event;
 insert into drvn_audit(actor,action,subject,detail) values(p_actor,case when p_visible then 'event_shown_publicly' else 'event_removed_from_public' end,p_event,jsonb_build_object('previous_visibility',t.public_visible,'public_visible',p_visible));
 return p_visible;
end $$;
revoke all on function public.drvn_set_visibility(uuid,uuid,boolean) from public,anon,authenticated;
grant execute on function public.drvn_set_visibility(uuid,uuid,boolean) to service_role;
create or replace function public.drvn_public_events() returns jsonb language sql security invoker set search_path=public as $$
with occupied as(select category_id,count(*) n from drvn_registrations where status in ('awaiting_payment','under_review','confirmed','correction_requested') and not(status='awaiting_payment' and expires_at<now()) group by category_id)
select coalesce(jsonb_agg(to_jsonb(t)||jsonb_build_object('categories',coalesce((select jsonb_agg(to_jsonb(c)||jsonb_build_object('available',greatest(0,c.capacity-coalesce(o.n,0))) order by c.name,c.id) from drvn_categories c left join occupied o on o.category_id=c.id where c.tournament_id=t.id and c.active),'[]'::jsonb)) order by t.featured desc,t.starts_at,t.id),'[]'::jsonb) from drvn_tournaments t where t.public_visible and t.status in ('published','closed','completed','cancelled');
$$;
create or replace function public.drvn_register(p_category uuid,p_name text,p_email text,p_partner text,p_token_hash text,p_key uuid,p_waitlist boolean) returns public.drvn_registrations language plpgsql set search_path=public as $$
declare c drvn_categories;t drvn_tournaments;r drvn_registrations;s drvn_settings;occupied int;begin
select * into c from drvn_categories where id=p_category for update;if not found or not c.active then raise exception 'Category unavailable';end if;
select * into r from drvn_registrations where idempotency_key=p_key;if found then return r;end if;
select * into t from drvn_tournaments where id=c.tournament_id;if not t.public_visible or t.status<>'published' or now()<t.opens_at or now()>t.closes_at then raise exception 'Registration is closed';end if;
update drvn_registrations set status='expired' where category_id=c.id and status='awaiting_payment' and expires_at<now();
if c.unit='team' and length(trim(p_partner))<2 then raise exception 'Partner name is required';end if;
select * into s from drvn_settings where id=true;
if c.fee_cents>0 and (s.gcash_name='' or s.gcash_number='' or s.gcash_qr='') then raise exception 'Payment instructions are not configured';end if;
select count(*) into occupied from drvn_registrations where category_id=c.id and status in ('awaiting_payment','under_review','confirmed','correction_requested');
if occupied>=c.capacity and not p_waitlist then raise exception 'Category is full; join the waitlist instead';end if;
insert into drvn_registrations(category_id,player_name,email,partner_name,amount_due,unit,status,payment_status,token_hash,idempotency_key,expires_at,settings_snapshot)
values(c.id,p_name,lower(p_email),p_partner,c.fee_cents,c.unit,case when occupied>=c.capacity then 'waitlisted' when c.fee_cents=0 then 'confirmed' else 'awaiting_payment' end,case when c.fee_cents=0 and occupied<c.capacity then 'verified' else 'unpaid' end,p_token_hash,p_key,now()+make_interval(hours=>s.reservation_hours),to_jsonb(s)) returning * into r;
insert into drvn_email_queue(registration_id,kind) values(r.id,case when r.status='confirmed' then 'entry_confirmed' else 'registration_received' end);return r;end $$;
commit;
