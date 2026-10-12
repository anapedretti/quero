begin;

alter table public.quero_categories
  add column emoji text not null default '✳',
  add column color text not null default '#d8f36a',
  add constraint quero_categories_emoji_check check (length(trim(emoji)) between 1 and 16),
  add constraint quero_categories_color_check check (color ~ '^#[0-9A-Fa-f]{6}$');

update public.quero_categories
set emoji = case id
  when 'casa-aconchego' then '🪴'
  when 'estilo-proprio' then '🧦'
  when 'tech-ideias' then '🎧'
  when 'papel-pausa' then '📔'
  else emoji
end,
color = case id
  when 'casa-aconchego' then '#c6dda9'
  when 'estilo-proprio' then '#f5b7a6'
  when 'tech-ideias' then '#e8d279'
  when 'papel-pausa' then '#a8cbd5'
  else color
end;

alter table public.quero_surprise_boxes
  add column color text not null default '#d8f36a',
  add constraint quero_surprise_boxes_color_check check (color ~ '^#[0-9A-Fa-f]{6}$');

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
    'category_details', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id, 'name', name, 'emoji', emoji, 'color', color
      ) order by name)
      from public.quero_categories where is_active
    ), '[]'::jsonb),
    'products', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'name', p.name, 'category', c.name,
        'price', coalesce(p.offer_price, p.price),
        'original_price', case when p.offer_price is not null then p.price else null end,
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
    'surprise_boxes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', b.id, 'name', b.name, 'description', b.description, 'price', b.price,
        'color', b.color, 'category_id', b.category_id, 'category', c.name,
        'min_price', b.min_price, 'max_price', b.max_price,
        'eligible_count', (
          select count(*)::integer
          from public.quero_products p
          join public.quero_categories pc on pc.id = p.category_id and pc.is_active
          where p.is_active
            and (b.category_id is null or p.category_id = b.category_id)
            and (b.min_price is null or coalesce(p.offer_price, p.price) >= b.min_price)
            and (b.max_price is null or coalesce(p.offer_price, p.price) <= b.max_price)
        )
      ) order by b.id)
      from public.quero_surprise_boxes b
      left join public.quero_categories c on c.id = b.category_id
      where b.is_active
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
      select jsonb_agg(jsonb_build_object(
        'id', id, 'name', name, 'emoji', emoji, 'color', color, 'is_active', is_active
      ) order by name)
      from public.quero_categories
    ), '[]'::jsonb),
    'products', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'name', p.name, 'category_id', p.category_id, 'category', c.name,
        'price', p.price, 'offer_price', p.offer_price,
        'emoji', p.emoji, 'color', p.color, 'tag', p.tag,
        'description', p.description, 'is_active', p.is_active
      ) order by p.id)
      from public.quero_products p
      join public.quero_categories c on c.id = p.category_id
    ), '[]'::jsonb),
    'surprise_boxes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', b.id, 'name', b.name, 'description', b.description, 'price', b.price,
        'color', b.color, 'category_id', b.category_id, 'category', c.name,
        'min_price', b.min_price, 'max_price', b.max_price,
        'eligible_count', (
          select count(*)::integer
          from public.quero_products p
          join public.quero_categories pc on pc.id = p.category_id and pc.is_active
          where p.is_active
            and (b.category_id is null or p.category_id = b.category_id)
            and (b.min_price is null or coalesce(p.offer_price, p.price) >= b.min_price)
            and (b.max_price is null or coalesce(p.offer_price, p.price) <= b.max_price)
        ),
        'is_active', b.is_active
      ) order by b.id)
      from public.quero_surprise_boxes b
      left join public.quero_categories c on c.id = b.category_id
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

drop function if exists public.quero_admin_save_category(text, text);

create function public.quero_admin_save_category(p_id text, p_name text, p_emoji text, p_color text)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_id text := lower(trim(coalesce(p_id, '')));
  v_name text := trim(coalesce(p_name, ''));
  v_emoji text := trim(coalesce(p_emoji, ''));
  v_old_name text;
begin
  if not public.quero_is_staff() then raise exception 'Administrator access required'; end if;
  if v_id !~ '^[a-z0-9]+(-[a-z0-9]+)*$' or length(v_id) > 60 then
    raise exception 'Invalid category identifier';
  end if;
  if v_name = '' or length(v_name) > 80 then raise exception 'Invalid category name'; end if;
  if v_emoji = '' or length(v_emoji) > 16 then raise exception 'Invalid category icon'; end if;
  if coalesce(p_color, '') !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'Invalid category color'; end if;
  select name into v_old_name from public.quero_categories where id = v_id;
  if found and v_old_name <> v_name then
    update public.quero_user_state
    set collection_rewards = array_replace(collection_rewards, v_old_name, v_name)
    where v_old_name = any(collection_rewards);
  end if;
  insert into public.quero_categories (id, name, emoji, color, is_active)
  values (v_id, v_name, v_emoji, p_color, true)
  on conflict (id) do update set
    name = excluded.name, emoji = excluded.emoji, color = excluded.color;
  return v_id;
end;
$function$;

drop function if exists public.quero_admin_save_surprise_box(integer, text, text, integer, text, integer, integer);

create function public.quero_admin_save_surprise_box(
  p_id integer, p_name text, p_description text, p_price integer,
  p_category_id text, p_min_price integer, p_max_price integer, p_color text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_id integer;
begin
  if not public.quero_is_staff() then raise exception 'Administrator access required'; end if;
  if trim(coalesce(p_name, '')) = '' or length(p_name) > 100 then raise exception 'Invalid surprise box name'; end if;
  if length(coalesce(p_description, '')) > 500 then raise exception 'Surprise box description is too long'; end if;
  if p_price is null or p_price < 1 or p_price > 1000000 then raise exception 'Invalid surprise box price'; end if;
  if coalesce(p_color, '') !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'Invalid surprise box color'; end if;
  if (p_min_price is null) <> (p_max_price is null)
    or (p_min_price is not null and (p_min_price < 1 or p_max_price < p_min_price or p_max_price > 1000000)) then
    raise exception 'Invalid surprise box price range';
  end if;
  if p_category_id is not null and not exists (
    select 1 from public.quero_categories where id = p_category_id and is_active
  ) then
    raise exception 'Active category not found';
  end if;

  if p_id is null then
    insert into public.quero_surprise_boxes (name, description, price, category_id, min_price, max_price, color)
    values (trim(p_name), trim(coalesce(p_description, '')), p_price, p_category_id, p_min_price, p_max_price, p_color)
    returning id into v_id;
  else
    update public.quero_surprise_boxes set
      name = trim(p_name), description = trim(coalesce(p_description, '')),
      price = p_price, category_id = p_category_id,
      min_price = p_min_price, max_price = p_max_price, color = p_color
    where id = p_id returning id into v_id;
    if not found then raise exception 'Surprise box not found'; end if;
  end if;
  return v_id;
end;
$function$;

revoke all on function public.quero_admin_save_category(text, text, text, text) from public, anon, authenticated;
revoke all on function public.quero_admin_save_surprise_box(integer, text, text, integer, text, integer, integer, text) from public, anon, authenticated;
grant execute on function public.quero_admin_save_category(text, text, text, text) to authenticated;
grant execute on function public.quero_admin_save_surprise_box(integer, text, text, integer, text, integer, integer, text) to authenticated;

commit;
