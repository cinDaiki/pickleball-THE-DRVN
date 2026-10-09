begin;
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
with filtered as(select a.*,a.actor::text actor_email from drvn_audit a where p_query='' or strpos(lower(a.action||' '||coalesce(a.actor::text,'')||' '||a.detail::text),lower(p_query))>0),paged as(select * from filtered order by created_at desc,id desc limit p_size offset (p_page-1)*p_size)
select jsonb_build_object('total',(select count(*) from filtered),'rows',coalesce((select jsonb_agg(to_jsonb(paged)) from paged),'[]')) into result;
else raise exception 'Unknown section';end if;
return result;end $$;
-- Bounded shared-network limits and separate per-player limits.
create function public.drvn_throttle(p_key text,p_max int) returns boolean language plpgsql security invoker set search_path=public as $$ declare n int;begin
if p_max<1 or p_max>3000 then raise exception 'Invalid throttle limit';end if;
insert into drvn_rate_limits(key,hits,until_at) values(p_key,1,now()+interval '1 hour') on conflict(key) do update set hits=case when drvn_rate_limits.until_at<now() then 1 else drvn_rate_limits.hits+1 end,until_at=case when drvn_rate_limits.until_at<now() then now()+interval '1 hour' else drvn_rate_limits.until_at end returning hits into n;return n<=p_max;end $$;
-- Compute availability in Postgres rather than transferring every registration.
create function public.drvn_public_events() returns jsonb language sql security invoker set search_path=public as $$
with occupied as(select category_id,count(*) n from drvn_registrations where status in ('awaiting_payment','under_review','confirmed','correction_requested') and not(status='awaiting_payment' and expires_at<now()) group by category_id)
select coalesce(jsonb_agg(to_jsonb(t)||jsonb_build_object('categories',coalesce((select jsonb_agg(to_jsonb(c)||jsonb_build_object('available',greatest(0,c.capacity-coalesce(o.n,0))) order by c.name,c.id) from drvn_categories c left join occupied o on o.category_id=c.id where c.tournament_id=t.id and c.active),'[]'::jsonb)) order by t.featured desc,t.starts_at,t.id),'[]'::jsonb) from drvn_tournaments t where t.status in ('published','closed','completed','cancelled');
$$;
revoke all on function public.drvn_throttle(text,int),public.drvn_public_events() from public,anon,authenticated;
grant execute on function public.drvn_throttle(text,int),public.drvn_public_events() to service_role;
commit;
