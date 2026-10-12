create table if not exists public.quero_categories (
  id text primary key,
  name text not null unique,
  is_active boolean not null default true
);

insert into public.quero_categories (id, name) values
  ('casa-aconchego', 'Casa & aconchego'),
  ('estilo-proprio', 'Estilo próprio'),
  ('tech-ideias', 'Tech & ideias'),
  ('papel-pausa', 'Papel & pausa')
on conflict (id) do nothing;

alter table public.quero_products
  add column if not exists category_id text,
  add column if not exists emoji text not null default '✳',
  add column if not exists color text not null default '#d8f36a',
  add column if not exists tag text not null default 'novidade',
  add column if not exists description text not null default '',
  add column if not exists is_active boolean not null default true;

update public.quero_products
set category_id = case category
  when 'Casa & aconchego' then 'casa-aconchego'
  when 'Estilo próprio' then 'estilo-proprio'
  when 'Tech & ideias' then 'tech-ideias'
  when 'Papel & pausa' then 'papel-pausa'
  else category_id
end
where category_id is null;

update public.quero_products set
  emoji = case id when 1 then '☕' when 2 then '🧦' when 3 then '🪴' when 4 then '🎧'
    when 5 then '📔' when 6 then '💡' when 7 then '🌈' when 8 then '📷' else emoji end,
  color = case id when 1 then '#d2c0ed' when 2 then '#f5b7a6' when 3 then '#c6dda9'
    when 4 then '#e8d279' when 5 then '#a8cbd5' when 6 then '#f0b56e'
    when 7 then '#edb4c9' when 8 then '#a9b9e3' else color end,
  tag = case id when 1 then 'queridinha' when 2 then 'conforto' when 3 then 'novidade'
    when 4 then 'foco total' when 5 then 'página em branco' when 6 then 'luz boa'
    when 7 then 'pequeno mimo' when 8 then 'instante favorito' else tag end,
  description = case id
    when 1 then 'Uma caneca com a dose certa de personalidade para acompanhar cafés demorados, chás quentinhos e ideias que chegam de outra galáxia. Seu pequeno ritual merece uma companheira especial.'
    when 2 then 'Aquele conforto de fim de semana, em qualquer dia da semana. Macias, divertidas e prontas para acompanhar seus passos — até os que dão só da cama ao sofá.'
    when 3 then 'Um lembrete verdinho para respirar fundo e deixar o dia mais leve. Fica bem na mesa, na estante ou naquele cantinho que está pedindo um pouco de vida.'
    when 4 then 'Seu convite para criar uma bolha sonora: uma playlist favorita, um podcast interessante ou simplesmente alguns minutos de silêncio só seus.'
    when 5 then 'Páginas em branco para listas, rabiscos, planos mirabolantes e pensamentos soltos. Não precisa saber por onde começar — é só abrir e deixar acontecer.'
    when 6 then 'Uma luz quentinha para desacelerar quando o dia pede uma pausa. Ideal para leituras, conversas tranquilas ou para transformar qualquer canto em refúgio.'
    when 7 then 'Um punhado de cor para personalizar cadernos, capinhas e tudo que estiver precisando de um toque seu. Pequenos detalhes, grande alegria.'
    when 8 then 'Para guardar os momentos que merecem replay: um passeio inesperado, uma mesa cheia de amigos ou aquela luz bonita no caminho de casa.'
    else description
  end;

alter table public.quero_products alter column category_id set not null;
alter table public.quero_products
  drop constraint if exists quero_products_category_id_fkey;
alter table public.quero_products
  add constraint quero_products_category_id_fkey
  foreign key (category_id) references public.quero_categories (id) on update cascade;

create sequence if not exists public.quero_products_id_seq;
select setval(
  'public.quero_products_id_seq',
  greatest(coalesce((select max(id) from public.quero_products), 0), 1),
  exists (select 1 from public.quero_products)
);
alter table public.quero_products
  alter column id set default nextval('public.quero_products_id_seq');

create table if not exists public.quero_missions (
  id text primary key,
  icon text not null default '✳',
  title text not null,
  detail text not null,
  reward integer not null check (reward between 0 and 1000000),
  requirement text not null default 'open'
    check (requirement in ('open', 'profile', 'cart')),
  is_active boolean not null default true
);

insert into public.quero_missions (id, icon, title, detail, reward, requirement) values
  ('hello', '☀', 'Dar uma olhadinha', 'Explore a lojinha com calma.', 50, 'open'),
  ('profile', '✎', 'Escolher seu nome', 'Entre na brincadeira com um apelido.', 75, 'profile'),
  ('favorite', '♡', 'Escolher um favorito', 'Adicione uma coisinha à sua sacola.', 60, 'cart')
on conflict (id) do nothing;

create table if not exists public.quero_admin_settings (
  key text primary key,
  value integer not null check (value between 0 and 1000000)
);

insert into public.quero_admin_settings (key, value) values
  ('collection_reward', 100),
  ('demo_reward', 100),
  ('demo_cooldown_minutes', 60)
on conflict (key) do nothing;

create table if not exists public.quero_admin_users (
  user_id uuid primary key references auth.users (id) on delete cascade,
  role text not null check (role in ('admin', 'editor')),
  created_at timestamptz not null default now()
);

alter table public.quero_categories enable row level security;
alter table public.quero_missions enable row level security;
alter table public.quero_admin_settings enable row level security;
alter table public.quero_admin_users enable row level security;
revoke all on public.quero_categories, public.quero_missions,
  public.quero_admin_settings, public.quero_admin_users from anon, authenticated;
revoke all on public.quero_products from anon, authenticated;
revoke all on sequence public.quero_products_id_seq from public, anon, authenticated;

create or replace function public.quero_is_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1 from public.quero_admin_users
    where user_id = auth.uid() and role in ('admin', 'editor')
  );
$function$;

create or replace function public.quero_is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1 from public.quero_admin_users
    where user_id = auth.uid() and role = 'admin'
  );
$function$;

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
        'reward', reward, 'requirement', requirement
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
        'reward', reward, 'requirement', requirement, 'is_active', is_active
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

create or replace function public.quero_admin_save_category(p_id text, p_name text)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_id text := lower(trim(coalesce(p_id, '')));
  v_name text := trim(coalesce(p_name, ''));
  v_old_name text;
begin
  if not public.quero_is_staff() then raise exception 'Administrator access required'; end if;
  if v_id !~ '^[a-z0-9]+(-[a-z0-9]+)*$' or length(v_id) > 60 then
    raise exception 'Invalid category identifier';
  end if;
  if v_name = '' or length(v_name) > 80 then raise exception 'Invalid category name'; end if;
  select name into v_old_name from public.quero_categories where id = v_id;
  if found and v_old_name <> v_name then
    update public.quero_user_state
    set collection_rewards = array_replace(collection_rewards, v_old_name, v_name)
    where v_old_name = any(collection_rewards);
  end if;
  insert into public.quero_categories (id, name, is_active)
  values (v_id, v_name, true)
  on conflict (id) do update set name = excluded.name;
  return v_id;
end;
$function$;

create or replace function public.quero_admin_set_category_active(p_id text, p_active boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not public.quero_is_staff() then raise exception 'Administrator access required'; end if;
  perform 1 from public.quero_categories where id = p_id for update;
  if not found then raise exception 'Category not found'; end if;
  if p_active is false and exists (
    select 1 from public.quero_products where category_id = p_id and is_active
  ) then
    raise exception 'Archive or move this category''s products first';
  end if;
  update public.quero_categories set is_active = p_active where id = p_id;
  return true;
end;
$function$;

create or replace function public.quero_admin_save_product(
  p_id integer, p_name text, p_category_id text, p_price integer,
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
  if p_price < 1 or p_price > 1000000 then raise exception 'Invalid product price'; end if;
  if trim(coalesce(p_emoji, '')) = '' or length(p_emoji) > 16 then raise exception 'Invalid product icon'; end if;
  if p_color !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'Invalid product color'; end if;
  if length(coalesce(p_tag, '')) > 40 or length(coalesce(p_description, '')) > 1000 then raise exception 'Product text is too long'; end if;
  select name into v_category_name from public.quero_categories
  where id = p_category_id and is_active for share;
  if not found then raise exception 'Active category not found'; end if;

  if p_id is null then
    insert into public.quero_products (name, category, category_id, price, emoji, color, tag, description, is_active)
    values (trim(p_name), v_category_name, p_category_id, p_price, trim(p_emoji), p_color, trim(coalesce(p_tag, '')), trim(coalesce(p_description, '')), true)
    returning id into v_id;
  else
    update public.quero_products set
      name = trim(p_name), category = v_category_name, category_id = p_category_id,
      price = p_price, emoji = trim(p_emoji), color = p_color,
      tag = trim(coalesce(p_tag, '')), description = trim(coalesce(p_description, ''))
    where id = p_id
    returning id into v_id;
    if not found then raise exception 'Product not found'; end if;
  end if;
  return v_id;
end;
$function$;

create or replace function public.quero_admin_set_product_active(p_id integer, p_active boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not public.quero_is_staff() then raise exception 'Administrator access required'; end if;
  update public.quero_products set is_active = p_active where id = p_id;
  if not found then raise exception 'Product not found'; end if;
  if not p_active then
    update public.quero_user_state
    set cart_product_ids = array_remove(cart_product_ids, p_id)
    where p_id = any(cart_product_ids);
  end if;
  return true;
end;
$function$;

create or replace function public.quero_admin_save_mission(
  p_id text, p_icon text, p_title text, p_detail text, p_reward integer, p_requirement text
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
  if p_reward < 0 or p_reward > 1000000 then raise exception 'Invalid mission reward'; end if;
  if p_requirement not in ('open', 'profile', 'cart') then raise exception 'Invalid mission requirement'; end if;
  insert into public.quero_missions (id, icon, title, detail, reward, requirement, is_active)
  values (v_id, trim(p_icon), trim(p_title), trim(p_detail), p_reward, p_requirement, true)
  on conflict (id) do update set icon = excluded.icon, title = excluded.title,
    detail = excluded.detail, reward = excluded.reward,
    requirement = excluded.requirement;
  return v_id;
end;
$function$;

create or replace function public.quero_admin_set_mission_active(p_id text, p_active boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not public.quero_is_staff() then raise exception 'Administrator access required'; end if;
  update public.quero_missions set is_active = p_active where id = p_id;
  if not found then raise exception 'Mission not found'; end if;
  return true;
end;
$function$;

create or replace function public.quero_admin_update_rules(
  p_collection_reward integer, p_demo_reward integer, p_demo_cooldown_minutes integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not public.quero_is_staff() then raise exception 'Administrator access required'; end if;
  if p_collection_reward not between 0 and 1000000
    or p_demo_reward not between 0 and 1000000
    or p_demo_cooldown_minutes not between 1 and 10080 then
    raise exception 'Invalid points rules';
  end if;
  update public.quero_admin_settings set value = p_collection_reward where key = 'collection_reward';
  update public.quero_admin_settings set value = p_demo_reward where key = 'demo_reward';
  update public.quero_admin_settings set value = p_demo_cooldown_minutes where key = 'demo_cooldown_minutes';
  return true;
end;
$function$;

create or replace function public.quero_admin_set_editor(p_email text, p_enabled boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid;
begin
  if not public.quero_is_admin() then raise exception 'Administrator access required'; end if;
  select id into v_user_id from auth.users where lower(email) = lower(trim(p_email));
  if not found then raise exception 'User account not found'; end if;
  if p_enabled then
    insert into public.quero_admin_users (user_id, role)
    values (v_user_id, 'editor')
    on conflict (user_id) do update set role = 'editor'
    where public.quero_admin_users.role <> 'admin';
    if exists (select 1 from public.quero_admin_users where user_id = v_user_id and role = 'admin') then
      raise exception 'Administrator role cannot be changed to editor';
    end if;
  else
    delete from public.quero_admin_users where user_id = v_user_id and role = 'editor';
  end if;
  return true;
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
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_mission from public.quero_missions
  where id = p_mission_id and is_active;
  if not found then raise exception 'Mission not found'; end if;
  select * into v_state from public.quero_user_state
  where user_id = auth.uid() for update;
  if not found then raise exception 'Account state is not initialized'; end if;
  if p_mission_id = any(v_state.completed_missions) then raise exception 'Mission already claimed'; end if;
  if v_mission.requirement = 'profile' and v_state.display_name = '' then
    raise exception 'Choose a profile name before claiming this mission';
  end if;
  if v_mission.requirement = 'cart' and cardinality(v_state.cart_product_ids) = 0 then
    raise exception 'Add an item to your cart before claiming this mission';
  end if;
  update public.quero_user_state
  set balance = balance + v_mission.reward,
      completed_missions = array_append(completed_missions, p_mission_id)
  where user_id = auth.uid();
  return jsonb_build_object('mission_id', p_mission_id, 'reward', v_mission.reward);
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
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not exists (
    select 1 from public.quero_products p
    join public.quero_categories c on c.id = p.category_id
    where p.id = p_product_id and p.is_active and c.is_active
  ) then
    raise exception 'Product not found';
  end if;
  select * into v_state from public.quero_user_state
  where user_id = auth.uid() for update;
  if not found then raise exception 'Account state is not initialized'; end if;
  if p_product_id = any(v_state.owned_product_ids) then raise exception 'Product is already in your collection'; end if;
  if p_product_id = any(v_state.cart_product_ids) then raise exception 'Product is already in your cart'; end if;
  update public.quero_user_state
  set cart_product_ids = array_append(cart_product_ids, p_product_id)
  where user_id = auth.uid();
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
  v_reward integer;
  v_cooldown integer;
  v_available_at timestamptz;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select value into v_reward from public.quero_admin_settings where key = 'demo_reward';
  select value into v_cooldown from public.quero_admin_settings where key = 'demo_cooldown_minutes';
  select * into v_state from public.quero_user_state
  where user_id = auth.uid() for update;
  if not found then raise exception 'Account state is not initialized'; end if;
  v_available_at := v_state.last_ad_reward_at + make_interval(mins => v_cooldown);
  if v_state.last_ad_reward_at is not null and now() < v_available_at then
    raise exception 'Demo reward available after %', v_available_at;
  end if;
  update public.quero_user_state
  set balance = balance + v_reward, last_ad_reward_at = now()
  where user_id = auth.uid();
  return jsonb_build_object(
    'reward', v_reward,
    'ad_available_at', now() + make_interval(mins => v_cooldown)
  );
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

  select coalesce(sum(p.price), 0)::integer, count(*)::integer
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

revoke all on function public.quero_is_staff() from public, anon, authenticated;
revoke all on function public.quero_is_admin() from public, anon, authenticated;
revoke all on function public.quero_public_catalog() from public;
revoke all on function public.quero_admin_get_data() from public, anon, authenticated;
revoke all on function public.quero_admin_save_category(text, text) from public, anon, authenticated;
revoke all on function public.quero_admin_set_category_active(text, boolean) from public, anon, authenticated;
revoke all on function public.quero_admin_save_product(integer, text, text, integer, text, text, text, text) from public, anon, authenticated;
revoke all on function public.quero_admin_set_product_active(integer, boolean) from public, anon, authenticated;
revoke all on function public.quero_admin_save_mission(text, text, text, text, integer, text) from public, anon, authenticated;
revoke all on function public.quero_admin_set_mission_active(text, boolean) from public, anon, authenticated;
revoke all on function public.quero_admin_update_rules(integer, integer, integer) from public, anon, authenticated;
revoke all on function public.quero_admin_set_editor(text, boolean) from public, anon, authenticated;
revoke all on function public.quero_claim_mission(text) from public, anon;
revoke all on function public.quero_add_to_cart(integer) from public, anon;
revoke all on function public.quero_claim_demo_ad() from public, anon;
revoke all on function public.quero_checkout() from public, anon;

grant execute on function public.quero_public_catalog() to anon, authenticated;
grant execute on function public.quero_admin_get_data() to authenticated;
grant execute on function public.quero_admin_save_category(text, text) to authenticated;
grant execute on function public.quero_admin_set_category_active(text, boolean) to authenticated;
grant execute on function public.quero_admin_save_product(integer, text, text, integer, text, text, text, text) to authenticated;
grant execute on function public.quero_admin_set_product_active(integer, boolean) to authenticated;
grant execute on function public.quero_admin_save_mission(text, text, text, text, integer, text) to authenticated;
grant execute on function public.quero_admin_set_mission_active(text, boolean) to authenticated;
grant execute on function public.quero_admin_update_rules(integer, integer, integer) to authenticated;
grant execute on function public.quero_admin_set_editor(text, boolean) to authenticated;
grant execute on function public.quero_claim_mission(text) to authenticated;
grant execute on function public.quero_add_to_cart(integer) to authenticated;
grant execute on function public.quero_claim_demo_ad() to authenticated;
grant execute on function public.quero_checkout() to authenticated;
