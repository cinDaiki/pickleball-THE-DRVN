begin;
-- Additive DRVN namespace. Review existing project objects before applying.
create table public.drvn_admins(user_id uuid primary key references auth.users(id), created_at timestamptz not null default now());
create table public.drvn_settings(id boolean primary key default true check(id), club_name text not null default 'The DRVN',contact_email text not null default '',gcash_name text not null default '',gcash_number text not null default '',gcash_qr text not null default '',reservation_hours int not null default 24 check(reservation_hours between 1 and 168),payment_instructions text not null default '',refund_policy text not null default 'Contact the organizer for cancellation and refund requests.');
insert into public.drvn_settings(id) values(true);
create table public.drvn_tournaments(id uuid primary key default gen_random_uuid(),title text not null check(length(title) between 1 and 150),description text not null default '',cover_url text not null default '',cover_alt text not null default '',gallery jsonb not null default '[]',starts_at timestamptz not null,venue text not null default '',address text not null default '',map_url text not null default '',rules text not null default '',opens_at timestamptz not null,closes_at timestamptz not null,status text not null default 'draft' check(status in ('draft','published','closed','completed','cancelled','archived')),featured boolean not null default false,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),check(closes_at>opens_at),check(starts_at>=closes_at));
create table public.drvn_categories(id uuid primary key default gen_random_uuid(),tournament_id uuid not null references public.drvn_tournaments(id),name text not null check(length(name) between 1 and 100),unit text not null check(unit in ('individual','team')),fee_cents int not null check(fee_cents between 0 and 100000000),capacity int not null check(capacity between 1 and 10000),active boolean not null default true);
create table public.drvn_registrations(id uuid primary key default gen_random_uuid(),category_id uuid not null references public.drvn_categories(id),player_name text not null,email text not null,partner_name text not null default '',amount_due int not null,unit text not null,status text not null check(status in ('awaiting_payment','under_review','confirmed','correction_requested','waitlisted','expired','cancelled')),payment_status text not null default 'unpaid' check(payment_status in ('unpaid','submitted','verified','correction_requested','rejected','refunded')),token_hash text not null unique,idempotency_key uuid not null unique,expires_at timestamptz,settings_snapshot jsonb not null,created_at timestamptz not null default now());
create unique index drvn_registration_duplicate on public.drvn_registrations(category_id,lower(email)) where status not in ('expired','cancelled');
create table public.drvn_payments(id uuid primary key default gen_random_uuid(),registration_id uuid not null references public.drvn_registrations(id),reference text not null,amount_cents int not null check(amount_cents>0),paid_at timestamptz not null,sender_name text not null,receipt_path text not null,status text not null default 'submitted' check(status in ('submitted','verified','correction_requested','rejected')),review_reason text not null default '',reviewed_by uuid references auth.users(id),reviewed_at timestamptz,created_at timestamptz not null default now());
create unique index drvn_reference_verified on public.drvn_payments(reference) where status='verified';
create unique index drvn_one_pending_payment on public.drvn_payments(registration_id) where status='submitted';
create table public.drvn_audit(id bigint generated always as identity primary key,actor uuid references auth.users(id),action text not null,subject uuid,detail jsonb not null default '{}',created_at timestamptz not null default now());
create table public.drvn_email_queue(id uuid primary key default gen_random_uuid(),registration_id uuid not null references public.drvn_registrations(id),kind text not null,note text not null default '',status text not null default 'pending' check(status in ('pending','sending','sent','failed')),attempts int not null default 0,locked_until timestamptz,last_error text not null default '',provider_id text,created_at timestamptz not null default now(),sent_at timestamptz);
create table public.drvn_rate_limits(key text primary key,hits int not null,until_at timestamptz not null);
-- Direct anonymous/authenticated access is denied. All application access goes through checked server functions.
do $$ declare t text; begin foreach t in array array['admins','settings','tournaments','categories','registrations','payments','audit','email_queue','rate_limits'] loop execute format('alter table public.drvn_%I enable row level security',t);execute format('revoke all on public.drvn_%I from anon, authenticated',t);execute format('grant all on public.drvn_%I to service_role',t);end loop;end $$;
grant usage,select on sequence public.drvn_audit_id_seq to service_role;
create function public.drvn_limit(p_key text) returns boolean language plpgsql set search_path=public as $$ declare n int;begin insert into drvn_rate_limits(key,hits,until_at) values(p_key,1,now()+interval '1 hour') on conflict(key) do update set hits=case when drvn_rate_limits.until_at<now() then 1 else drvn_rate_limits.hits+1 end,until_at=case when drvn_rate_limits.until_at<now() then now()+interval '1 hour' else drvn_rate_limits.until_at end returning hits into n;return n<=30;end $$;
create function public.drvn_expire() returns void language sql set search_path=public as $$ update drvn_registrations set status='expired' where status='awaiting_payment' and expires_at<now(); $$;
create function public.drvn_register(p_category uuid,p_name text,p_email text,p_partner text,p_token_hash text,p_key uuid,p_waitlist boolean) returns public.drvn_registrations language plpgsql set search_path=public as $$
declare c drvn_categories;t drvn_tournaments;r drvn_registrations;s drvn_settings;occupied int;begin
select * into c from drvn_categories where id=p_category for update;if not found or not c.active then raise exception 'Category unavailable';end if;
select * into r from drvn_registrations where idempotency_key=p_key;if found then return r;end if;
select * into t from drvn_tournaments where id=c.tournament_id;if t.status<>'published' or now()<t.opens_at or now()>t.closes_at then raise exception 'Registration is closed';end if;
update drvn_registrations set status='expired' where category_id=c.id and status='awaiting_payment' and expires_at<now();
if c.unit='team' and length(trim(p_partner))<2 then raise exception 'Partner name is required';end if;
select * into s from drvn_settings where id=true;
if c.fee_cents>0 and (s.gcash_name='' or s.gcash_number='' or s.gcash_qr='') then raise exception 'Payment instructions are not configured';end if;
select count(*) into occupied from drvn_registrations where category_id=c.id and status in ('awaiting_payment','under_review','confirmed','correction_requested');
if occupied>=c.capacity and not p_waitlist then raise exception 'Category is full; join the waitlist instead';end if;
insert into drvn_registrations(category_id,player_name,email,partner_name,amount_due,unit,status,payment_status,token_hash,idempotency_key,expires_at,settings_snapshot)
values(c.id,p_name,lower(p_email),p_partner,c.fee_cents,c.unit,case when occupied>=c.capacity then 'waitlisted' when c.fee_cents=0 then 'confirmed' else 'awaiting_payment' end,case when c.fee_cents=0 and occupied<c.capacity then 'verified' else 'unpaid' end,p_token_hash,p_key,now()+make_interval(hours=>s.reservation_hours),to_jsonb(s)) returning * into r;
insert into drvn_email_queue(registration_id,kind) values(r.id,case when r.status='confirmed' then 'entry_confirmed' else 'registration_received' end);return r;end $$;
create function public.drvn_submit_payment(p_registration uuid,p_reference text,p_amount int,p_paid_at timestamptz,p_sender text,p_path text) returns uuid language plpgsql set search_path=public as $$ declare r drvn_registrations;pid uuid;begin
select * into r from drvn_registrations where id=p_registration for update;
if not found or r.payment_status in ('verified','refunded') or r.status in ('waitlisted','cancelled','confirmed') then raise exception 'Payment proof cannot be submitted for this registration';end if;
if exists(select 1 from drvn_payments where registration_id=r.id and status='submitted') then raise exception 'A payment is already awaiting review';end if;
insert into drvn_payments(registration_id,reference,amount_cents,paid_at,sender_name,receipt_path) values(r.id,p_reference,p_amount,p_paid_at,p_sender,p_path) returning id into pid;
update drvn_registrations set payment_status='submitted',status=case when status='expired' or (status='awaiting_payment' and expires_at<now()) then 'expired' else 'under_review' end where id=r.id;
insert into drvn_email_queue(registration_id,kind) values(r.id,'payment_submitted');return pid;end $$;
create function public.drvn_review(p_payment uuid,p_actor uuid,p_action text,p_reason text) returns uuid language plpgsql set search_path=public as $$ declare p drvn_payments;r drvn_registrations;c drvn_categories;occupied int;begin
if not exists(select 1 from drvn_admins where user_id=p_actor) then raise exception 'Admin required';end if;
select * into p from drvn_payments where id=p_payment; if not found then raise exception 'Payment missing';end if;
select * into r from drvn_registrations where id=p.registration_id;
select * into c from drvn_categories where id=r.category_id for update;
select * into r from drvn_registrations where id=p.registration_id for update;
select * into p from drvn_payments where id=p_payment for update;
if p.status<>'submitted' then raise exception 'Payment has already been reviewed';end if;
if p_action not in ('verified','correction_requested','rejected') then raise exception 'Invalid action';end if;
if p_action<>'verified' and length(trim(p_reason))<3 then raise exception 'A review reason is required';end if;
if p_action='verified' then
if r.status='cancelled' then raise exception 'Entry is cancelled';end if;
if p.amount_cents<>r.amount_due then raise exception 'Amount does not match the amount due';end if;
if exists(select 1 from drvn_tournaments where id=c.tournament_id and status in ('cancelled','archived','completed')) then raise exception 'Event no longer accepts entries';end if;
update drvn_registrations set status='expired' where category_id=c.id and status='awaiting_payment' and expires_at<now();
select count(*) into occupied from drvn_registrations where category_id=c.id and id<>r.id and status in ('awaiting_payment','under_review','confirmed','correction_requested');
if occupied>=c.capacity then raise exception 'No slot available; resolve the late payment manually';end if;
end if;
update drvn_payments set status=p_action,review_reason=p_reason,reviewed_by=p_actor,reviewed_at=now() where id=p.id;
update drvn_registrations set payment_status=case when p_action='verified' then 'verified' else p_action end,status=case when p_action='verified' then 'confirmed' when status='expired' then 'expired' else 'correction_requested' end where id=r.id;
insert into drvn_audit(actor,action,subject,detail) values(p_actor,'payment_'||p_action,p.id,jsonb_build_object('reason',p_reason));
insert into drvn_email_queue(registration_id,kind,note) values(r.id,'payment_'||p_action,p_reason);return r.id;end $$;
create function public.drvn_claim_emails() returns setof public.drvn_email_queue language sql set search_path=public as $$ update drvn_email_queue set status='sending',locked_until=now()+interval '5 minutes',attempts=attempts+1 where id in(select id from drvn_email_queue where (status='pending' or(status='sending' and locked_until<now())) and attempts<5 order by created_at for update skip locked limit 5) returning *; $$;
-- Every function is server-only, including rate limiting and email queue claims.
do $$ declare f record;begin for f in select oid::regprocedure sig from pg_proc where pronamespace='public'::regnamespace and proname like 'drvn_%' loop execute format('revoke all on function %s from public,anon,authenticated',f.sig);execute format('grant execute on function %s to service_role',f.sig);end loop;end $$;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('drvn-photos','drvn-photos',true,2097152,array['image/jpeg','image/png','image/webp']),('drvn-receipts','drvn-receipts',false,2097152,array['image/jpeg','image/png','image/webp']);
commit;
