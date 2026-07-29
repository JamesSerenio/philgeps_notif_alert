-- Secure registration endpoint for browser/mobile notification tokens.
-- The app can register its own token without exposing device_tokens for
-- public SELECT access. The backend service role can continue reading it.

create or replace function public.register_device_token(
  p_token text,
  p_platform text,
  p_device_key text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if nullif(trim(p_token), '') is null
     or nullif(trim(p_device_key), '') is null then
    raise exception 'Token and device key are required';
  end if;

  insert into public.device_tokens (token, platform, device_key)
  values (p_token, coalesce(nullif(trim(p_platform), ''), 'unknown'), p_device_key)
  on conflict (device_key) do update
  set token = excluded.token,
      platform = excluded.platform;
end;
$$;

revoke all on function public.register_device_token(text, text, text)
from public;

grant execute on function public.register_device_token(text, text, text)
to anon, authenticated;
