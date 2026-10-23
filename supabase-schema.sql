-- BRJ EMPIRE production-oriented member portal schema for Supabase.
-- Run in a NEW Supabase project using SQL Editor. Review business, payment and privacy obligations before launch.
-- Never put the service_role key in browser code.

create extension if not exists pgcrypto;
do $$ begin create type public.app_role as enum ('member','sub_admin','main_admin'); exception when duplicate_object then null; end $$;
do $$ begin create type public.request_status as enum ('pending','approved','rejected','completed'); exception when duplicate_object then null; end $$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  role public.app_role not null default 'member',
  referral_code text unique not null default upper(substr(encode(gen_random_bytes(8),'hex'),1,10)),
  created_at timestamptz not null default now()
);
create table if not exists public.packages (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,
  name text not null,
  amount_inr integer not null check(amount_inr>0),
  duration_days integer not null default 0 check(duration_days>=0),
  description text not null default 'A BRJ EMPIRE service package.',
  features jsonb not null default '["Member support","Request tracking"]'::jsonb,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create table if not exists public.deposit_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  amount_inr integer not null check(amount_inr between 1 and 1000000),
  payment_method text not null default 'upi' check(payment_method='upi'),
  reference_note text not null,
  note text not null default '',
  status public.request_status not null default 'pending',
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create table if not exists public.withdrawal_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  amount_inr integer not null check(amount_inr between 1 and 1000000),
  payout_method text not null check(payout_method in ('upi','bank_transfer')),
  destination_reference text not null,
  status public.request_status not null default 'pending',
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create table if not exists public.package_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  package_id uuid not null references public.packages(id),
  amount_inr integer not null check(amount_inr>0),
  status public.request_status not null default 'pending',
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create table if not exists public.referrals (
  id uuid primary key default gen_random_uuid(),
  referrer_id uuid not null references public.profiles(id) on delete cascade,
  referred_id uuid not null unique references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint no_self_referral check(referrer_id<>referred_id)
);
create table if not exists public.activity_log (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references auth.users(id) on delete set null,
  event_type text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create or replace function public.current_app_role()
returns public.app_role language sql stable security definer set search_path=public
as $$ select role from public.profiles where id=auth.uid() $$;
create or replace function public.is_staff()
returns boolean language sql stable security definer set search_path=public
as $$ select coalesce(public.current_app_role() in ('sub_admin','main_admin'),false) $$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public
as $$
declare ref_code text;
declare ref_profile uuid;
begin
  insert into public.profiles(id,full_name,role)
  values(new.id,coalesce(new.raw_user_meta_data->>'full_name',''),'member')
  on conflict(id) do nothing;
  ref_code := nullif(new.raw_user_meta_data->>'referral_code','');
  if ref_code is not null then
    select id into ref_profile from public.profiles where referral_code=upper(ref_code);
    if ref_profile is not null and ref_profile<>new.id then
      insert into public.referrals(referrer_id,referred_id) values(ref_profile,new.id) on conflict(referred_id) do nothing;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.packages enable row level security;
alter table public.deposit_requests enable row level security;
alter table public.withdrawal_requests enable row level security;
alter table public.package_requests enable row level security;
alter table public.referrals enable row level security;
alter table public.activity_log enable row level security;

drop policy if exists "profile self or staff read" on public.profiles;
create policy "profile self or staff read" on public.profiles for select to authenticated using(id=auth.uid() or public.is_staff());
-- Intentionally no profile update policy: members cannot promote themselves to admin.
drop policy if exists "active packages read" on public.packages;
create policy "active packages read" on public.packages for select to authenticated using(active=true or public.current_app_role()='main_admin');
drop policy if exists "main admin manages packages" on public.packages;
create policy "main admin manages packages" on public.packages for all to authenticated using(public.current_app_role()='main_admin') with check(public.current_app_role()='main_admin');

drop policy if exists "insert own deposits" on public.deposit_requests;
create policy "insert own deposits" on public.deposit_requests for insert to authenticated with check(user_id=auth.uid() and status='pending' and reviewed_by is null and reviewed_at is null);
drop policy if exists "read own or staff deposits" on public.deposit_requests;
create policy "read own or staff deposits" on public.deposit_requests for select to authenticated using(user_id=auth.uid() or public.is_staff());
drop policy if exists "insert own withdrawals" on public.withdrawal_requests;
create policy "insert own withdrawals" on public.withdrawal_requests for insert to authenticated with check(user_id=auth.uid() and status='pending' and reviewed_by is null and reviewed_at is null);
drop policy if exists "read own or staff withdrawals" on public.withdrawal_requests;
create policy "read own or staff withdrawals" on public.withdrawal_requests for select to authenticated using(user_id=auth.uid() or public.is_staff());
drop policy if exists "insert own package requests" on public.package_requests;
create policy "insert own package requests" on public.package_requests for insert to authenticated with check(user_id=auth.uid() and status='pending' and reviewed_by is null and reviewed_at is null);
drop policy if exists "read own or staff package requests" on public.package_requests;
create policy "read own or staff package requests" on public.package_requests for select to authenticated using(user_id=auth.uid() or public.is_staff());
drop policy if exists "read own referral activity or staff" on public.referrals;
create policy "read own referral activity or staff" on public.referrals for select to authenticated using(referrer_id=auth.uid() or public.is_staff());
drop policy if exists "read own activity or staff" on public.activity_log;
create policy "read own activity or staff" on public.activity_log for select to authenticated using(actor_id=auth.uid() or public.is_staff());
drop policy if exists "insert own activity" on public.activity_log;
create policy "insert own activity" on public.activity_log for insert to authenticated with check(actor_id=auth.uid());

-- Staff decisions happen through this function, which changes only the status/reviewer fields.
create or replace function public.review_member_request(p_kind text,p_request_id uuid,p_status public.request_status)
returns boolean language plpgsql security definer set search_path=public
as $$
begin
  if auth.uid() is null or not public.is_staff() then raise exception 'Administrator access required'; end if;
  if p_status not in ('approved','rejected') then raise exception 'Invalid review status'; end if;
  if p_kind='deposit' then
    update public.deposit_requests set status=p_status,reviewed_by=auth.uid(),reviewed_at=now() where id=p_request_id and status='pending';
  elsif p_kind='withdrawal' then
    update public.withdrawal_requests set status=p_status,reviewed_by=auth.uid(),reviewed_at=now() where id=p_request_id and status='pending';
  elsif p_kind='package' then
    update public.package_requests set status=p_status,reviewed_by=auth.uid(),reviewed_at=now() where id=p_request_id and status='pending';
  else raise exception 'Unknown request type'; end if;
  return found;
end $$;
revoke all on function public.review_member_request(text,uuid,public.request_status) from public;
grant execute on function public.review_member_request(text,uuid,public.request_status) to authenticated;

insert into public.packages(slug,name,amount_inr,duration_days,description,features)
values
('bronze','Bronze',500,0,'Entry service package with member support.','["Member support","Request tracking","Account activity"]'::jsonb),
('silver','Silver',1000,0,'Expanded service package with member support.','["Member support","Request tracking","Priority assistance"]'::jsonb),
('gold','Gold',1500,0,'Advanced service package with member support.','["Member support","Request tracking","Account assistance"]'::jsonb)
on conflict(slug) do nothing;

-- After the owner has registered, verify their auth UUID, then run this in SQL Editor:
-- update public.profiles set role='main_admin' where id='OWNER_AUTH_USER_UUID';
-- Promote only verified staff. Example:
-- update public.profiles set role='sub_admin' where id='VERIFIED_STAFF_AUTH_USER_UUID';
-- To attribute referrals on signup, app passes the URL ?ref=CODE as auth metadata.
