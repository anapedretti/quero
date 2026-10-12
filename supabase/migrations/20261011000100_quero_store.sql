create table if not exists public.quero_products (
  id integer primary key,
  name text not null,
  category text not null,
  price integer not null check (price > 0)
);

do $seed_products$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'quero_products'
      and column_name = 'category_id'
  ) then
    insert into public.quero_products (id, name, category, price, category_id) values
      (1, 'Caneca de outro planeta', 'Casa & aconchego', 120, 'casa-aconchego'),
      (2, 'Meias de domingo', 'Estilo próprio', 85, 'estilo-proprio'),
      (3, 'Vasinho quase zen', 'Casa & aconchego', 160, 'casa-aconchego'),
      (4, 'Fone modo avião', 'Tech & ideias', 240, 'tech-ideias'),
      (5, 'Caderno de grandes planos', 'Papel & pausa', 95, 'papel-pausa'),
      (6, 'Luminária fim de tarde', 'Casa & aconchego', 210, 'casa-aconchego'),
      (7, 'Adesivos muito você', 'Papel & pausa', 55, 'papel-pausa'),
      (8, 'Câmera de boas memórias', 'Tech & ideias', 320, 'tech-ideias')
    on conflict (id) do nothing;
  else
    insert into public.quero_products (id, name, category, price) values
      (1, 'Caneca de outro planeta', 'Casa & aconchego', 120),
      (2, 'Meias de domingo', 'Estilo próprio', 85),
      (3, 'Vasinho quase zen', 'Casa & aconchego', 160),
      (4, 'Fone modo avião', 'Tech & ideias', 240),
      (5, 'Caderno de grandes planos', 'Papel & pausa', 95),
      (6, 'Luminária fim de tarde', 'Casa & aconchego', 210),
      (7, 'Adesivos muito você', 'Papel & pausa', 55),
      (8, 'Câmera de boas memórias', 'Tech & ideias', 320)
    on conflict (id) do nothing;
  end if;
end;
$seed_products$;

create table if not exists public.quero_user_state (
  user_id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '',
  balance integer not null default 0 check (balance >= 0),
  completed_missions text[] not null default '{}',
  cart_product_ids integer[] not null default '{}',
  owned_product_ids integer[] not null default '{}',
  collection_rewards text[] not null default '{}',
  last_ad_reward_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.quero_products enable row level security;
alter table public.quero_user_state enable row level security;

drop policy if exists "Quero catalog is public" on public.quero_products;
create policy "Quero catalog is public"
  on public.quero_products for select
  to anon, authenticated
  using (true);

revoke all on public.quero_products from anon, authenticated;
grant select on public.quero_products to anon, authenticated;
revoke all on public.quero_user_state from anon, authenticated;

create or replace function public.quero_create_user_state()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  insert into public.quero_user_state (user_id, display_name)
  values (
    new.id,
    left(trim(coalesce(new.raw_user_meta_data ->> 'display_name', '')), 24)
  )
  on conflict (user_id) do nothing;
  return new;
end;
$function$;

drop trigger if exists quero_create_user_state on auth.users;
create trigger quero_create_user_state
  after insert on auth.users
  for each row execute function public.quero_create_user_state();

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
    'completed_missions', v_state.completed_missions,
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

create or replace function public.quero_add_to_cart(p_product_id integer)
returns void
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
  if not exists (
    select 1 from public.quero_products where id = p_product_id
  ) then
    raise exception 'Product not found';
  end if;

  select * into v_state
  from public.quero_user_state
  where user_id = auth.uid()
  for update;

  if not found then
    raise exception 'Account state is not initialized';
  end if;
  if p_product_id = any(v_state.owned_product_ids) then
    raise exception 'Product is already in your collection';
  end if;
  if p_product_id = any(v_state.cart_product_ids) then
    raise exception 'Product is already in your cart';
  end if;

  update public.quero_user_state
  set cart_product_ids = array_append(cart_product_ids, p_product_id)
  where user_id = auth.uid();
end;
$function$;

create or replace function public.quero_remove_from_cart(p_product_id integer)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  update public.quero_user_state
  set cart_product_ids = array_remove(cart_product_ids, p_product_id)
  where user_id = auth.uid();
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
  v_reward integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  v_reward := case p_mission_id
    when 'hello' then 50
    when 'profile' then 75
    when 'favorite' then 60
    else null
  end;
  if v_reward is null then
    raise exception 'Mission not found';
  end if;

  select * into v_state
  from public.quero_user_state
  where user_id = auth.uid()
  for update;

  if not found then
    raise exception 'Account state is not initialized';
  end if;
  if p_mission_id = any(v_state.completed_missions) then
    raise exception 'Mission already claimed';
  end if;
  if p_mission_id = 'profile' and v_state.display_name = '' then
    raise exception 'Choose a profile name before claiming this mission';
  end if;
  if p_mission_id = 'favorite' and cardinality(v_state.cart_product_ids) = 0 then
    raise exception 'Add an item to your cart before claiming this mission';
  end if;

  update public.quero_user_state
  set balance = balance + v_reward,
      completed_missions = array_append(completed_missions, p_mission_id)
  where user_id = auth.uid();

  return jsonb_build_object('mission_id', p_mission_id, 'reward', v_reward);
end;
$function$;

create or replace function public.quero_claim_demo_ad()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_state public.quero_user_state%rowtype;
  v_available_at timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into v_state
  from public.quero_user_state
  where user_id = auth.uid()
  for update;

  if not found then
    raise exception 'Account state is not initialized';
  end if;
  v_available_at := v_state.last_ad_reward_at + interval '1 hour';
  if v_state.last_ad_reward_at is not null and now() < v_available_at then
    raise exception 'Demo reward available after %', v_available_at;
  end if;

  update public.quero_user_state
  set balance = balance + 100,
      last_ad_reward_at = now()
  where user_id = auth.uid();

  return jsonb_build_object('reward', 100, 'ad_available_at', now() + interval '1 hour');
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
  v_balance integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into v_state
  from public.quero_user_state
  where user_id = auth.uid()
  for update;

  if not found then
    raise exception 'Account state is not initialized';
  end if;
  if cardinality(v_state.cart_product_ids) = 0 then
    raise exception 'Your cart is empty';
  end if;

  select coalesce(sum(price), 0)::integer, count(*)::integer
  into v_total, v_product_count
  from public.quero_products
  where id = any(v_state.cart_product_ids);

  if v_product_count <> cardinality(v_state.cart_product_ids) then
    raise exception 'Your cart contains an unavailable product';
  end if;
  if v_total > v_state.balance then
    raise exception 'Insufficient virtual coins';
  end if;

  select array_agg(distinct product_id order by product_id)
  into v_owned
  from unnest(v_state.owned_product_ids || v_state.cart_product_ids) as ids(product_id);

  select coalesce(array_agg(category order by category), '{}'::text[])
  into v_new_rewards
  from (
    select category
    from public.quero_products
    group by category
    having bool_and(id = any(v_owned))
  ) as completed_categories
  where not (category = any(v_state.collection_rewards));

  v_reward := cardinality(v_new_rewards) * 100;
  v_balance := v_state.balance - v_total + v_reward;

  update public.quero_user_state
  set balance = v_balance,
      cart_product_ids = '{}',
      owned_product_ids = v_owned,
      collection_rewards = collection_rewards || v_new_rewards
  where user_id = auth.uid();

  return jsonb_build_object(
    'spent', v_total,
    'reward', v_reward,
    'completed_categories', v_new_rewards,
    'balance', v_balance
  );
end;
$function$;

revoke all on function public.quero_create_user_state() from public, anon, authenticated;
revoke all on function public.quero_get_state() from public, anon;
revoke all on function public.quero_add_to_cart(integer) from public, anon;
revoke all on function public.quero_remove_from_cart(integer) from public, anon;
revoke all on function public.quero_claim_mission(text) from public, anon;
revoke all on function public.quero_claim_demo_ad() from public, anon;
revoke all on function public.quero_checkout() from public, anon;

grant execute on function public.quero_get_state() to authenticated;
grant execute on function public.quero_add_to_cart(integer) to authenticated;
grant execute on function public.quero_remove_from_cart(integer) to authenticated;
grant execute on function public.quero_claim_mission(text) to authenticated;
grant execute on function public.quero_claim_demo_ad() to authenticated;
grant execute on function public.quero_checkout() to authenticated;
