-- Service Manager – Supabase schema
-- Chạy toàn bộ file này trong Supabase Dashboard → SQL Editor → New query → Run.

-- ============================================================
-- Helpers
-- ============================================================
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

-- ============================================================
-- Tables
-- ============================================================
create table if not exists public.customers (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid() references auth.users on delete cascade,
  name        text not null,
  phone       text,
  email       text,
  zalo        text,
  company     text,
  note        text,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists public.providers (
  id               uuid primary key default gen_random_uuid(),
  owner_id         uuid not null default auth.uid() references auth.users on delete cascade,
  name             text not null,
  website          text,
  support_contact  text,
  note             text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create table if not exists public.services (
  id                 uuid primary key default gen_random_uuid(),
  owner_id           uuid not null default auth.uid() references auth.users on delete cascade,
  type               text not null constraint services_type_check
                     check (type in ('DOMAIN', 'HOSTING', 'VPS', 'OTHER')),
  name               text not null,
  customer_id        uuid references public.customers on delete set null,  -- null = của mình
  provider_id        uuid references public.providers on delete set null,
  parent_vps_id      uuid references public.services on delete set null,   -- hosting tự tạo trên VPS
  start_date         date,
  expiry_date        date not null,
  cycle_months       int not null default 12 check (cycle_months > 0),
  cost_price         numeric(14, 0),
  sell_price         numeric(14, 0),
  notify_days        int not null default 15 check (notify_days >= 0),
  status             text not null default 'ACTIVE' check (status in ('ACTIVE', 'CANCELLED')),
  note               text,
  -- VPS / Hosting
  ip                 text,
  os                 text,
  cpu                int,
  ram_gb             numeric(6, 1),
  disk_gb            int,
  panel              text,
  -- Domain
  nameservers        text,
  linked_hosting_id  uuid references public.services on delete set null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  check (parent_vps_id is null or parent_vps_id <> id)
);

create table if not exists public.accounts (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null default auth.uid() references auth.users on delete cascade,
  kind          text not null default 'OTHER'
                check (kind in ('PORTAL', 'CONTROL_PANEL', 'SSH', 'FTP', 'DATABASE', 'EMAIL', 'OTHER')),
  label         text not null,
  login_url     text,
  username      text,
  password_enc  text,  -- AES-GCM, mã hoá phía app bằng master password
  port          int,
  provider_id   uuid references public.providers on delete set null,
  customer_id   uuid references public.customers on delete set null,
  service_id    uuid references public.services on delete set null,
  note          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create table if not exists public.renewals (
  id             uuid primary key default gen_random_uuid(),
  owner_id       uuid not null default auth.uid() references auth.users on delete cascade,
  service_id     uuid not null references public.services on delete cascade,
  renewed_at     timestamptz not null default now(),
  old_expiry     date not null,
  new_expiry     date not null,
  months         int not null,
  amount         numeric(14, 0),
  customer_paid  boolean not null default false,
  provider_paid  boolean not null default false,
  note           text
);

-- Cấu hình riêng + dữ liệu kiểm tra master password của kho tài khoản
create table if not exists public.user_settings (
  owner_id             uuid primary key default auth.uid() references auth.users on delete cascade,
  vault_salt           text,
  vault_check          text,
  default_notify_days  int not null default 15,
  updated_at           timestamptz not null default now()
);

-- ============================================================
-- Indexes
-- ============================================================
create index if not exists services_owner_expiry_idx on public.services (owner_id, expiry_date);
create index if not exists services_customer_idx     on public.services (customer_id);
create index if not exists services_parent_vps_idx   on public.services (parent_vps_id);
create index if not exists accounts_owner_idx        on public.accounts (owner_id);
create index if not exists renewals_service_idx      on public.renewals (service_id, renewed_at desc);
create index if not exists customers_owner_idx       on public.customers (owner_id);

-- ============================================================
-- updated_at triggers
-- ============================================================
do $$
declare t text;
begin
  foreach t in array array['customers', 'providers', 'services', 'accounts', 'user_settings'] loop
    execute format('drop trigger if exists trg_%1$s_updated_at on public.%1$s', t);
    execute format(
      'create trigger trg_%1$s_updated_at before update on public.%1$s
       for each row execute function public.set_updated_at()', t);
  end loop;
end $$;

-- ============================================================
-- Row Level Security: mỗi user chỉ thấy dữ liệu của mình
-- ============================================================
do $$
declare t text;
begin
  foreach t in array array['customers', 'providers', 'services', 'accounts', 'renewals', 'user_settings'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists owner_all on public.%I', t);
    execute format(
      'create policy owner_all on public.%I for all to authenticated
       using (owner_id = (select auth.uid()))
       with check (owner_id = (select auth.uid()))', t);
  end loop;
end $$;

-- ============================================================
-- RPC: gia hạn dịch vụ (cập nhật hạn + ghi lịch sử trong 1 transaction)
-- hạn mới = hạn cũ + số tháng
-- ============================================================
create or replace function public.renew_service(
  p_service_id     uuid,
  p_months         int,
  p_amount         numeric default null,
  p_customer_paid  boolean default false,
  p_provider_paid  boolean default false,
  p_note           text default null
) returns public.services
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_old  date;
  v_new  date;
  v_row  public.services;
begin
  if p_months is null or p_months <= 0 then
    raise exception 'months must be > 0';
  end if;

  select expiry_date into v_old
  from public.services
  where id = p_service_id
  for update;

  if not found then
    raise exception 'service not found';
  end if;

  v_new := (v_old + make_interval(months => p_months))::date;

  update public.services
     set expiry_date = v_new,
         status = 'ACTIVE'
   where id = p_service_id
  returning * into v_row;

  insert into public.renewals (service_id, old_expiry, new_expiry, months, amount,
                               customer_paid, provider_paid, note)
  values (p_service_id, v_old, v_new, p_months, p_amount,
          p_customer_paid, p_provider_paid, p_note);

  return v_row;
end $$;

revoke execute on function public.renew_service(uuid, int, numeric, boolean, boolean, text) from public, anon;
grant execute on function public.renew_service(uuid, int, numeric, boolean, boolean, text) to authenticated;

-- ============================================================
-- Sổ thu chi (kế toán). Chạy 1 lần trong Supabase → SQL Editor (chạy lại nhiều lần cũng không sao).

create table if not exists public.transactions (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null default auth.uid() references auth.users on delete cascade,
  kind         text not null check (kind in ('IN', 'OUT')),          -- IN = thu từ khách, OUT = chi
  amount       numeric(14, 0) not null check (amount >= 0),
  paid_at      date not null,                                         -- ngày thu / chi tiền
  service_id   uuid references public.services on delete set null,
  customer_id  uuid references public.customers on delete set null,
  period_from  date,                                                  -- kỳ dịch vụ mà khoản tiền này trả cho
  period_to    date,
  source       text not null default 'MANUAL' check (source in ('MANUAL', 'RENEWAL', 'BACKFILL')),
  note         text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists transactions_owner_paid_idx on public.transactions (owner_id, paid_at);
create index if not exists transactions_service_idx    on public.transactions (service_id);

drop trigger if exists trg_transactions_updated_at on public.transactions;
create trigger trg_transactions_updated_at before update on public.transactions
  for each row execute function public.set_updated_at();

alter table public.transactions enable row level security;
drop policy if exists owner_all on public.transactions;
create policy owner_all on public.transactions for all to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));
