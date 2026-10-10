begin;
-- Additive, read-only aggregates: existing rows and relationships are untouched.
create or replace function public.drvn_tournament_summary(p_actor uuid,p_event uuid) returns jsonb
language plpgsql stable security invoker set search_path=public as $$
declare result jsonb;
begin
 if not exists(select 1 from drvn_admins where user_id=p_actor) then raise exception 'Admin required'; end if;
 if p_event is null or not exists(select 1 from drvn_tournaments where id=p_event) then raise exception 'Tournament not found'; end if;
 with entries as (
  select r.*,case when r.status='awaiting_payment' and r.expires_at<now() then 'expired' else r.status end current_status
  from drvn_registrations r join drvn_categories c on c.id=r.category_id where c.tournament_id=p_event
 ), category_totals as (
  select c.id,c.name,c.unit,c.fee_cents,c.capacity,c.active,
   count(r.id) registrations,
   count(r.id) filter(where r.current_status='confirmed') confirmed,
   coalesce(sum(case when r.unit='team' then 2 else 1 end) filter(where r.current_status='confirmed'),0) confirmed_players,
   count(r.id) filter(where r.current_status in('awaiting_payment','under_review','confirmed','correction_requested')) occupied,
   count(r.id) filter(where r.current_status='waitlisted') waitlisted
  from drvn_categories c left join entries r on r.category_id=c.id
  where c.tournament_id=p_event group by c.id
 ), amounts as (
  select coalesce(sum(p.amount_cents) filter(where p.status='verified' and r.payment_status='verified'),0) collections,
   coalesce(sum(p.amount_cents) filter(where p.status='verified' and r.payment_status='refunded'),0) refunds,
   count(*) filter(where p.status='submitted') pending
  from drvn_payments p join entries r on r.id=p.registration_id
 )
 select jsonb_build_object(
  'registrations',(select count(*) from entries),
  'confirmed',(select count(*) from entries where current_status='confirmed'),
  'confirmed_players',(select coalesce(sum(case when unit='team' then 2 else 1 end),0) from entries where current_status='confirmed'),
  'waitlisted',(select count(*) from entries where current_status='waitlisted'),
  'available',(select coalesce(sum(greatest(capacity-occupied,0)),0) from category_totals where active),
  'collections',(select collections from amounts),'refunds',(select refunds from amounts),'pending',(select pending from amounts),
  'categories',coalesce((select jsonb_agg(to_jsonb(c) order by c.name,c.id) from category_totals c),'[]'::jsonb),
  'statuses',coalesce((select jsonb_object_agg(current_status,n) from(select current_status,count(*) n from entries group by current_status) s),'{}'::jsonb)
 ) into result;
 return result;
end $$;
revoke all on function public.drvn_tournament_summary(uuid,uuid) from public,anon,authenticated;
grant execute on function public.drvn_tournament_summary(uuid,uuid) to service_role;
commit;
