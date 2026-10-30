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
