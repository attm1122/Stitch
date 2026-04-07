create extension if not exists pgcrypto;

create table if not exists public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    email text not null unique,
    expensify_email text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.receipts (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.profiles(id) on delete cascade,
    merchant text,
    amount numeric(12, 2),
    currency_code text not null default 'USD',
    purchase_date date,
    status text not null check (status in ('needs_review', 'ready', 'uploaded')) default 'needs_review',
    source text not null check (source in ('camera', 'photo_library', 'files', 'share_sheet')),
    extraction_confidence numeric(5, 2) not null default 0,
    ocr_text text,
    duplicate_fingerprint text,
    duplicate_flag boolean not null default false,
    storage_path text,
    file_name text not null,
    content_type text not null,
    upload_state text not null check (upload_state in ('idle', 'uploading', 'uploaded', 'failed')) default 'idle',
    last_upload_error text,
    uploaded_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists receipts_user_created_at_idx on public.receipts(user_id, created_at desc);
create index if not exists receipts_user_status_idx on public.receipts(user_id, status);
create index if not exists receipts_duplicate_fingerprint_idx on public.receipts(user_id, duplicate_fingerprint);

create table if not exists public.upload_batches (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.profiles(id) on delete cascade,
    state text not null check (state in ('queued', 'uploading', 'partial', 'completed', 'failed')) default 'queued',
    success_count integer not null default 0,
    failure_count integer not null default 0,
    message text,
    created_at timestamptz not null default now(),
    completed_at timestamptz
);

create table if not exists public.expensify_destinations (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null unique references public.profiles(id) on delete cascade,
    expensify_email text not null,
    sender_whitelisted boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.processing_jobs (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.profiles(id) on delete cascade,
    receipt_id uuid references public.receipts(id) on delete cascade,
    job_type text not null check (job_type in ('process_receipt', 'batch_upload')),
    state text not null check (state in ('queued', 'running', 'completed', 'failed')) default 'queued',
    payload jsonb not null default '{}'::jsonb,
    error_message text,
    created_at timestamptz not null default now(),
    completed_at timestamptz
);

create table if not exists public.audit_events (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.profiles(id) on delete cascade,
    receipt_id uuid references public.receipts(id) on delete set null,
    upload_batch_id uuid references public.upload_batches(id) on delete set null,
    event_type text not null,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now()
);

insert into storage.buckets (id, name, public)
values ('receipts', 'receipts', false)
on conflict (id) do nothing;

alter table public.profiles enable row level security;
alter table public.receipts enable row level security;
alter table public.upload_batches enable row level security;
alter table public.expensify_destinations enable row level security;
alter table public.processing_jobs enable row level security;
alter table public.audit_events enable row level security;

create policy "profiles are owner readable"
on public.profiles
for select
using (auth.uid() = id);

create policy "profiles are owner writable"
on public.profiles
for all
using (auth.uid() = id)
with check (auth.uid() = id);

create policy "receipts are owner readable"
on public.receipts
for select
using (auth.uid() = user_id);

create policy "receipts are owner writable"
on public.receipts
for all
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy "upload_batches are owner readable"
on public.upload_batches
for select
using (auth.uid() = user_id);

create policy "upload_batches are owner writable"
on public.upload_batches
for all
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy "expensify_destinations are owner readable"
on public.expensify_destinations
for select
using (auth.uid() = user_id);

create policy "expensify_destinations are owner writable"
on public.expensify_destinations
for all
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy "processing_jobs are owner readable"
on public.processing_jobs
for select
using (auth.uid() = user_id);

create policy "processing_jobs are owner writable"
on public.processing_jobs
for all
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy "audit_events are owner readable"
on public.audit_events
for select
using (auth.uid() = user_id);

create policy "audit_events are owner writable"
on public.audit_events
for all
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

