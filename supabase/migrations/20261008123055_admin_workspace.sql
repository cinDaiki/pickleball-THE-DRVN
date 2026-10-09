begin;
-- Server-only paged organizer queries. Never return status-link hashes or idempotency keys.
create or replace function public.drvn_admin_list(p_actor uuid,p_section text,p_page int default 1,p_query text default '',p_filter text default '',p_event uuid default null,p_size int default 25) returns jsonb language plpgsql security invoker set search_path=public as $$
declare result jsonb;begin
if not exists(select 1 from drvn_admins where user_id=p_actor) then raise exception 'Admin required';end if;
if p_page<1 or p_size<1 or p_size>100 or length(p_query)>150 then raise exception 'Invalid pagination or search';end if;
if p_section='Registrations' then
with filtered as(select r.id,r.category_id,r.player_name,r.email,r.partner_name,r.amount_due,r.unit,r.status,r.payment_status,r.expires_at,r.created_at,c.name category_name,t.title tournament_title from drvn_registrations r join drvn_categories c on c.id=r.category_id join drvn_tournaments t on t.id=c.tournament_id where (p_filter='' or r.status=p_filter) and (p_event is null or t.id=p_event) and (p_query='' or strpos(lower(r.player_name||' '||r.email||' '||t.title),lower(p_query))>0)), paged as(select * from filtered order by created_at desc,id limit p_size offset (p_page-1)*p_size)
select jsonb_build_object('total',(select count(*) from filtered),'rows',coalesce((select jsonb_agg(to_jsonb(paged)) from paged),'[]')) into result;
elsif p_section='Payments' then
with filtered as(select p.id,p.registration_id,p.reference,p.amount_cents,p.paid_at,p.sender_name,p.status,p.review_reason,p.reviewed_by,p.reviewed_at,p.created_at,r.player_name,r.email,r.amount_due,t.title tournament_title,exists(select 1 from drvn_payments x where x.reference=p.reference and x.id<>p.id) duplicate from drvn_payments p join drvn_registrations r on r.id=p.registration_id join drvn_categories c on c.id=r.category_id join drvn_tournaments t on t.id=c.tournament_id where (p_filter='' or p.status=p_filter) and (p_event is null or t.id=p_event) and (p_query='' or strpos(lower(r.player_name||' '||r.email||' '||p.reference||' '||t.title),lower(p_query))>0)), paged as(select * from filtered order by (status='submitted') desc,created_at desc,id limit p_size offset (p_page-1)*p_size)
select jsonb_build_object('total',(select count(*) from filtered),'rows',coalesce((select jsonb_agg(to_jsonb(paged)) from paged),'[]')) into result;
elsif p_section='Emails' then
with filtered as(select m.id,m.kind,m.status,m.attempts,m.last_error,m.created_at,m.sent_at,r.email,t.title tournament_title from drvn_email_queue m join drvn_registrations r on r.id=m.registration_id join drvn_categories c on c.id=r.category_id join drvn_tournaments t on t.id=c.tournament_id where (p_filter='' or m.status=p_filter) and (p_event is null or t.id=p_event) and (p_query='' or strpos(lower(r.player_name||' '||r.email||' '||t.title),lower(p_query))>0)), paged as(select * from filtered order by created_at desc,id limit p_size offset (p_page-1)*p_size)
select jsonb_build_object('total',(select count(*) from filtered),'rows',coalesce((select jsonb_agg(to_jsonb(paged)) from paged),'[]')) into result;
elsif p_section='Activity' then
with filtered as(select a.*,u.email actor_email from drvn_audit a left join auth.users u on u.id=a.actor where p_query='' or strpos(lower(a.action||' '||coalesce(u.email,'')||' '||a.detail::text),lower(p_query))>0),paged as(select * from filtered order by created_at desc,id desc limit p_size offset (p_page-1)*p_size)
select jsonb_build_object('total',(select count(*) from filtered),'rows',coalesce((select jsonb_agg(to_jsonb(paged)) from paged),'[]')) into result;
else raise exception 'Unknown section';end if;
return result;end $$;
create or replace function public.drvn_admin_summary(p_actor uuid) returns jsonb language plpgsql security invoker set search_path=public as $$ begin
if not exists(select 1 from drvn_admins where user_id=p_actor) then raise exception 'Admin required';end if;
return jsonb_build_object('registrations',(select count(*) from drvn_registrations),'pending',(select count(*) from drvn_payments where status='submitted'),'collections',(select coalesce(sum(p.amount_cents),0) from drvn_payments p join drvn_registrations r on r.id=p.registration_id where p.status='verified' and r.payment_status='verified'),'upcoming',(select count(*) from drvn_tournaments where status='published' and starts_at>=now()),'failed_emails',(select count(*) from drvn_email_queue where status='failed'),'waitlisted',(select count(*) from drvn_registrations where status='waitlisted'));
end $$;
create or replace function public.drvn_retry_email(p_actor uuid,p_id uuid) returns boolean language plpgsql security invoker set search_path=public as $$ declare n int;begin
if not exists(select 1 from drvn_admins where user_id=p_actor) then raise exception 'Admin required';end if;
update drvn_email_queue set status='pending',locked_until=null,last_error='' where id=p_id and status='failed' and attempts<5;
get diagnostics n=row_count;
if n=0 then raise exception 'Only failed messages with fewer than five attempts can be retried';end if;
insert into drvn_audit(actor,action,subject) values(p_actor,'email_retry_requested',p_id);return true;end $$;
-- Do not automatically resend an SMTP delivery whose outcome is unknown.
create or replace function public.drvn_claim_emails() returns setof public.drvn_email_queue language plpgsql security invoker set search_path=public as $$ begin
update drvn_email_queue set status='failed',last_error='Delivery outcome unknown after timeout. Check the sender Sent folder before manually retrying.' where status='sending' and locked_until<now();
return query update drvn_email_queue set status='sending',locked_until=now()+interval '5 minutes',attempts=attempts+1 where id in(select id from drvn_email_queue where status='pending' and attempts<5 order by created_at for update skip locked limit 5) returning *;end $$;
create index if not exists drvn_registrations_created on public.drvn_registrations(created_at desc,id);
create index if not exists drvn_registrations_category on public.drvn_registrations(category_id);
create index if not exists drvn_payments_created on public.drvn_payments(created_at desc,id);
create index if not exists drvn_payments_reference on public.drvn_payments(reference);
create index if not exists drvn_email_queue_created on public.drvn_email_queue(created_at desc,id);
create index if not exists drvn_categories_tournament on public.drvn_categories(tournament_id);
do $$ declare f record;begin for f in select oid::regprocedure sig from pg_proc where pronamespace='public'::regnamespace and proname like 'drvn_%' loop execute format('revoke all on function %s from public,anon,authenticated',f.sig);execute format('grant execute on function %s to service_role',f.sig);end loop;end $$;
commit;
