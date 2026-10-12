alter table public.quero_missions
  add column if not exists recurrence text not null default 'once';

alter table public.quero_missions
  drop constraint if exists quero_missions_recurrence_check;
alter table public.quero_missions
  add constraint quero_missions_recurrence_check
  check (recurrence in ('once', 'daily', 'weekly', 'monthly'));

create table if not exists public.quero_mission_claims (
  user_id uuid not null references auth.users (id) on delete cascade,
  mission_id text not null references public.quero_missions (id) on delete cascade,
  recurrence text not null check (recurrence in ('once', 'daily', 'weekly', 'monthly')),
  period_start date not null,
  claimed_at timestamptz not null default now(),
  primary key (user_id, mission_id, recurrence, period_start)
);

alter table public.quero_mission_claims enable row level security;
revoke all on public.quero_mission_claims from public, anon, authenticated;

insert into public.quero_mission_claims (user_id, mission_id, recurrence, period_start)
select distinct s.user_id, legacy.mission_id, 'once', date '0001-01-01'
from public.quero_user_state s
cross join lateral unnest(s.completed_missions) as legacy(mission_id)
join public.quero_missions m on m.id = legacy.mission_id
on conflict do nothing;

create or replace function public.quero_public_catalog()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select jsonb_build_object(
    'categories', coalesce((
      select jsonb_agg(name order by name)
      from public.quero_categories where is_active
    ), '[]'::jsonb),
    'products', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'name', p.name, 'category', c.name, 'price', p.price,
        'emoji', p.emoji, 'color', p.color, 'tag', p.tag, 'description', p.description,
        'is_active', p.is_active
      ) order by p.id)
      from public.quero_products p
      join public.quero_categories c on c.id = p.category_id
      where c.is_active or exists (
        select 1 from public.quero_user_state s
        where p.id = any(s.owned_product_ids)
      )
    ), '[]'::jsonb),
    'missions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id, 'icon', icon, 'title', title, 'detail', detail,
        'reward', reward, 'requirement', requirement, 'recurrence', recurrence
      ) order by title)
      from public.quero_missions where is_active
    ), '[]'::jsonb),
    'settings', jsonb_build_object(
      'collection_reward', (select value from public.quero_admin_settings where key = 'collection_reward'),
      'demo_reward', (select value from public.quero_admin_settings where key = 'demo_reward'),
      'demo_cooldown_minutes', (select value from public.quero_admin_settings where key = 'demo_cooldown_minutes')
    )
  );
$function$;

create or replace function public.quero_admin_get_data()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_is_admin boolean;
begin
  if not public.quero_is_staff() then
    raise exception 'Administrator access required';
  end if;
  v_is_admin := public.quero_is_admin();

  return jsonb_build_object(
    'is_admin', v_is_admin,
    'categories', coalesce((
      select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'is_active', is_active) order by name)
      from public.quero_categories
    ), '[]'::jsonb),
    'products', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'name', p.name, 'category_id', p.category_id, 'category', c.name,
        'price', p.price, 'emoji', p.emoji, 'color', p.color, 'tag', p.tag,
        'description', p.description, 'is_active', p.is_active
      ) order by p.id)
      from public.quero_products p
      join public.quero_categories c on c.id = p.category_id
    ), '[]'::jsonb),
    'missions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id, 'icon', icon, 'title', title, 'detail', detail,
        'reward', reward, 'requirement', requirement, 'recurrence', recurrence,
        'is_active', is_active
      ) order by title)
      from public.quero_missions
    ), '[]'::jsonb),
    'settings', jsonb_build_object(
      'collection_reward', (select value from public.quero_admin_settings where key = 'collection_reward'),
      'demo_reward', (select value from public.quero_admin_settings where key = 'demo_reward'),
      'demo_cooldown_minutes', (select value from public.quero_admin_settings where key = 'demo_cooldown_minutes')
    ),
    'editors', case when v_is_admin then coalesce((
      select jsonb_agg(jsonb_build_object('email', u.email, 'created_at', a.created_at) order by u.email)
      from public.quero_admin_users a
      join auth.users u on u.id = a.user_id
      where a.role = 'editor'
    ), '[]'::jsonb) else '[]'::jsonb end
  );
end;
$function$;

drop function if exists public.quero_admin_save_mission(text, text, text, text, integer, text);

create or replace function public.quero_admin_save_mission(
  p_id text, p_icon text, p_title text, p_detail text, p_reward integer,
  p_requirement text, p_recurrence text
)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_id text := lower(trim(coalesce(p_id, '')));
begin
  if not public.quero_is_staff() then raise exception 'Administrator access required'; end if;
  if v_id !~ '^[a-z0-9]+(-[a-z0-9]+)*$' or length(v_id) > 60 then raise exception 'Invalid mission identifier'; end if;
  if trim(coalesce(p_icon, '')) = '' or length(p_icon) > 16 then raise exception 'Invalid mission icon'; end if;
  if trim(coalesce(p_title, '')) = '' or length(p_title) > 100 then raise exception 'Invalid mission title'; end if;
  if trim(coalesce(p_detail, '')) = '' or length(p_detail) > 240 then raise exception 'Invalid mission description'; end if;
  if p_reward is null or p_reward < 0 or p_reward > 1000000 then raise exception 'Invalid mission reward'; end if;
  if p_requirement is null or p_requirement not in ('open', 'profile', 'cart') then raise exception 'Invalid mission requirement'; end if;
  if p_recurrence is null or p_recurrence not in ('once', 'daily', 'weekly', 'monthly') then raise exception 'Invalid mission recurrence'; end if;
  insert into public.quero_missions (id, icon, title, detail, reward, requirement, recurrence, is_active)
  values (v_id, trim(p_icon), trim(p_title), trim(p_detail), p_reward, p_requirement, p_recurrence, true)
  on conflict (id) do update set icon = excluded.icon, title = excluded.title,
    detail = excluded.detail, reward = excluded.reward,
    requirement = excluded.requirement, recurrence = excluded.recurrence;
  return v_id;
end;
$function$;

create or replace function public.quero_get_state()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_state public.quero_user_state%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  insert into public.quero_user_state (user_id)
  values (auth.uid())
  on conflict (user_id) do nothing;

  select * into v_state
  from public.quero_user_state
  where user_id = auth.uid();

  return jsonb_build_object(
    'display_name', v_state.display_name,
    'balance', v_state.balance,
    'completed_missions', coalesce((
      select array_agg(m.id order by m.id)
      from public.quero_missions m
      where (m.recurrence = 'once' and m.id = any(v_state.completed_missions))
        or exists (
          select 1 from public.quero_mission_claims c
          where c.user_id = auth.uid()
            and c.mission_id = m.id
            and c.recurrence = m.recurrence
            and c.period_start = case m.recurrence
              when 'once' then date '0001-01-01'
              when 'daily' then (now() at time zone 'America/Sao_Paulo')::date
              when 'weekly' then date_trunc('week', now() at time zone 'America/Sao_Paulo')::date
              when 'monthly' then date_trunc('month', now() at time zone 'America/Sao_Paulo')::date
            end
        )
    ), '{}'::text[]),
    'cart_product_ids', v_state.cart_product_ids,
    'owned_product_ids', v_state.owned_product_ids,
    'collection_rewards', v_state.collection_rewards,
    'ad_available_at', case
      when v_state.last_ad_reward_at is null then null
      else v_state.last_ad_reward_at + interval '1 hour'
    end
  );
end;
$function$;

create or replace function public.quero_claim_mission(p_mission_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_state public.quero_user_state%rowtype;
  v_mission public.quero_missions%rowtype;
  v_period_start date;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_mission from public.quero_missions
  where id = p_mission_id and is_active;
  if not found then raise exception 'Mission not found'; end if;

  select * into v_state from public.quero_user_state
  where user_id = auth.uid() for update;
  if not found then raise exception 'Account state is not initialized'; end if;

  v_period_start := case v_mission.recurrence
    when 'once' then date '0001-01-01'
    when 'daily' then (now() at time zone 'America/Sao_Paulo')::date
    when 'weekly' then date_trunc('week', now() at time zone 'America/Sao_Paulo')::date
    when 'monthly' then date_trunc('month', now() at time zone 'America/Sao_Paulo')::date
  end;

  if (v_mission.recurrence = 'once' and p_mission_id = any(v_state.completed_missions))
    or exists (
      select 1 from public.quero_mission_claims c
      where c.user_id = auth.uid()
        and c.mission_id = p_mission_id
        and c.recurrence = v_mission.recurrence
        and c.period_start = v_period_start
    ) then
    raise exception 'Mission already claimed';
  end if;
  if v_mission.requirement = 'profile' and v_state.display_name = '' then
    raise exception 'Choose a profile name before claiming this mission';
  end if;
  if v_mission.requirement = 'cart' and cardinality(v_state.cart_product_ids) = 0 then
    raise exception 'Add an item to your cart before claiming this mission';
  end if;

  insert into public.quero_mission_claims (user_id, mission_id, recurrence, period_start)
  values (auth.uid(), p_mission_id, v_mission.recurrence, v_period_start);

  update public.quero_user_state
  set balance = balance + v_mission.reward,
      completed_missions = case
        when v_mission.recurrence = 'once' then array_append(completed_missions, p_mission_id)
        else completed_missions
      end
  where user_id = auth.uid();

  return jsonb_build_object('mission_id', p_mission_id, 'reward', v_mission.reward);
end;
$function$;

revoke all on function public.quero_public_catalog() from public;
revoke all on function public.quero_admin_get_data() from public, anon, authenticated;
revoke all on function public.quero_admin_save_mission(text, text, text, text, integer, text, text) from public, anon, authenticated;
revoke all on function public.quero_get_state() from public, anon;
revoke all on function public.quero_claim_mission(text) from public, anon;

grant execute on function public.quero_public_catalog() to anon, authenticated;
grant execute on function public.quero_admin_get_data() to authenticated;
grant execute on function public.quero_admin_save_mission(text, text, text, text, integer, text, text) to authenticated;
grant execute on function public.quero_get_state() to authenticated;
grant execute on function public.quero_claim_mission(text) to authenticated;
