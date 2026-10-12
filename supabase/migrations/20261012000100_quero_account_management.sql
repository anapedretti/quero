create or replace function public.quero_update_profile(p_display_name text)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_display_name text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  v_display_name := left(trim(coalesce(p_display_name, '')), 24);
  if v_display_name = '' then
    raise exception 'Profile name cannot be empty';
  end if;

  update public.quero_user_state
  set display_name = v_display_name
  where user_id = auth.uid();

  if not found then
    raise exception 'Account state is not initialized';
  end if;

  return v_display_name;
end;
$function$;

create or replace function public.quero_cancel_account()
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  delete from auth.users
  where id = auth.uid();

  if not found then
    raise exception 'Account not found';
  end if;

  return true;
end;
$function$;

revoke all on function public.quero_update_profile(text) from public, anon;
revoke all on function public.quero_cancel_account() from public, anon;

grant execute on function public.quero_update_profile(text) to authenticated;
grant execute on function public.quero_cancel_account() to authenticated;
