begin;

alter table public.quero_products
  add column if not exists offer_price integer;

do $offer_price_constraint$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'quero_products_offer_price_check'
      and conrelid = 'public.quero_products'::regclass
  ) then
    alter table public.quero_products
      add constraint quero_products_offer_price_check
      check (offer_price is null or (offer_price > 0 and offer_price < price));
  end if;
end;
$offer_price_constraint$;

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
        'price', p.price, 'offer_price', p.offer_price,
        'emoji', p.emoji, 'color', p.color, 'tag', p.tag,
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

drop function if exists public.quero_admin_save_product(integer, text, text, integer, text, text, text, text);

create function public.quero_admin_save_product(
  p_id integer, p_name text, p_category_id text, p_price integer, p_offer_price integer,
  p_emoji text, p_color text, p_tag text, p_description text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_id integer;
  v_category_name text;
begin
  if not public.quero_is_staff() then raise exception 'Administrator access required'; end if;
  if trim(coalesce(p_name, '')) = '' or length(p_name) > 100 then raise exception 'Invalid product name'; end if;
  if p_price is null or p_price < 1 or p_price > 1000000 then raise exception 'Invalid product price'; end if;
  if p_offer_price is not null and (p_offer_price < 1 or p_offer_price > 1000000 or p_offer_price >= p_price) then
    raise exception 'Invalid product offer price';
  end if;
  if trim(coalesce(p_emoji, '')) = '' or length(p_emoji) > 16 then raise exception 'Invalid product icon'; end if;
  if p_color !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'Invalid product color'; end if;
  if length(coalesce(p_tag, '')) > 40 or length(coalesce(p_description, '')) > 1000 then raise exception 'Product text is too long'; end if;
  select name into v_category_name from public.quero_categories
  where id = p_category_id and is_active for share;
  if not found then raise exception 'Active category not found'; end if;

  if p_id is null then
    insert into public.quero_products (name, category, category_id, price, offer_price, emoji, color, tag, description, is_active)
    values (trim(p_name), v_category_name, p_category_id, p_price, p_offer_price, trim(p_emoji), p_color, trim(coalesce(p_tag, '')), trim(coalesce(p_description, '')), true)
    returning id into v_id;
  else
    update public.quero_products set
      name = trim(p_name), category = v_category_name, category_id = p_category_id,
      price = p_price, offer_price = p_offer_price, emoji = trim(p_emoji), color = p_color,
      tag = trim(coalesce(p_tag, '')), description = trim(coalesce(p_description, ''))
    where id = p_id
    returning id into v_id;
    if not found then raise exception 'Product not found'; end if;
  end if;
  return v_id;
end;
$function$;

create or replace function public.quero_checkout()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_state public.quero_user_state%rowtype;
  v_total integer;
  v_product_count integer;
  v_owned integer[];
  v_new_rewards text[];
  v_reward integer;
  v_collection_reward integer;
  v_balance integer;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_state from public.quero_user_state
  where user_id = auth.uid() for update;
  if not found then raise exception 'Account state is not initialized'; end if;
  if cardinality(v_state.cart_product_ids) = 0 then raise exception 'Your cart is empty'; end if;

  select coalesce(sum(coalesce(p.offer_price, p.price)), 0)::integer, count(*)::integer
  into v_total, v_product_count
  from public.quero_products p
  where p.id = any(v_state.cart_product_ids) and p.is_active;
  if v_product_count <> cardinality(v_state.cart_product_ids) then
    raise exception 'Your cart contains an unavailable product';
  end if;
  if v_total > v_state.balance then raise exception 'Insufficient virtual coins'; end if;

  select array_agg(distinct product_id order by product_id)
  into v_owned
  from unnest(v_state.owned_product_ids || v_state.cart_product_ids) as ids(product_id);
  select coalesce(array_agg(c.name order by c.name), '{}'::text[])
  into v_new_rewards
  from public.quero_categories c
  where c.is_active
    and exists (select 1 from public.quero_products p where p.category_id = c.id and p.is_active)
    and not (c.name = any(v_state.collection_rewards))
    and not exists (
      select 1 from public.quero_products p
      where p.category_id = c.id and p.is_active and not (p.id = any(v_owned))
    );
  select value into v_collection_reward from public.quero_admin_settings where key = 'collection_reward';
  v_reward := cardinality(v_new_rewards) * v_collection_reward;
  v_balance := v_state.balance - v_total + v_reward;
  update public.quero_user_state
  set balance = v_balance, cart_product_ids = '{}',
      owned_product_ids = v_owned,
      collection_rewards = collection_rewards || v_new_rewards
  where user_id = auth.uid();
  return jsonb_build_object(
    'spent', v_total, 'reward', v_reward,
    'completed_categories', v_new_rewards, 'balance', v_balance
  );
end;
$function$;

revoke all on function public.quero_public_catalog() from public;
revoke all on function public.quero_admin_get_data() from public, anon, authenticated;
revoke all on function public.quero_admin_save_product(integer, text, text, integer, integer, text, text, text, text) from public, anon, authenticated;
revoke all on function public.quero_checkout() from public, anon, authenticated;

grant execute on function public.quero_public_catalog() to anon, authenticated;
grant execute on function public.quero_admin_get_data() to authenticated;
grant execute on function public.quero_admin_save_product(integer, text, text, integer, integer, text, text, text, text) to authenticated;
grant execute on function public.quero_checkout() to authenticated;

commit;
