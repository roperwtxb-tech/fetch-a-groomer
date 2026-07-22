-- Fetch A Groomer Grooming Tracker
-- Schema: single-user, no-auth PWA. RLS enabled with permissive anon policies
-- (equivalent to open access, but keeps Supabase security advisories quiet and
-- makes it a one-line change later if a login is ever added).

create extension if not exists "pgcrypto";

-- ============= CLIENTS =============
create table clients (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text,
  email text,
  address text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ============= PETS =============
create table pets (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references clients(id) on delete cascade,
  name text not null,
  breed text,
  size text check (size in ('small','medium','large','xlarge')) default 'medium',
  coat_type text,
  temperament text,
  allergies text,
  medical_notes text,
  vet_name text,
  vet_phone text,
  photo_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index pets_client_id_idx on pets(client_id);

-- ============= SERVICES =============
create table services (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  base_price numeric(10,2) not null default 0,
  price_small numeric(10,2),
  price_medium numeric(10,2),
  price_large numeric(10,2),
  price_xlarge numeric(10,2),
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

-- ============= APPOINTMENT SERIES (for recurring appointments) =============
create table appointment_series (
  id uuid primary key default gen_random_uuid(),
  pet_id uuid not null references pets(id) on delete cascade,
  interval_weeks integer not null,
  notes text,
  created_at timestamptz not null default now()
);

-- ============= APPOINTMENTS =============
create table appointments (
  id uuid primary key default gen_random_uuid(),
  pet_id uuid not null references pets(id) on delete cascade,
  client_id uuid not null references clients(id) on delete cascade,
  series_id uuid references appointment_series(id) on delete set null,
  scheduled_at timestamptz not null,
  duration_minutes integer not null default 60,
  status text not null check (status in ('scheduled','completed','cancelled','no_show')) default 'scheduled',
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index appointments_scheduled_at_idx on appointments(scheduled_at);
create index appointments_pet_id_idx on appointments(pet_id);
create index appointments_client_id_idx on appointments(client_id);
create index appointments_status_idx on appointments(status);

-- ============= APPOINTMENT <-> SERVICES (many to many, price snapshot) =============
create table appointment_services (
  id uuid primary key default gen_random_uuid(),
  appointment_id uuid not null references appointments(id) on delete cascade,
  service_id uuid references services(id) on delete set null,
  service_name text not null, -- snapshot in case service is later renamed/deleted
  price numeric(10,2) not null default 0
);
create index appointment_services_appointment_id_idx on appointment_services(appointment_id);

-- ============= PAYMENTS =============
create table payments (
  id uuid primary key default gen_random_uuid(),
  appointment_id uuid not null references appointments(id) on delete cascade,
  amount numeric(10,2) not null default 0,
  method text check (method in ('cash','check','card','venmo','cashapp','zelle','other')) default 'cash',
  paid boolean not null default false,
  paid_at timestamptz,
  notes text,
  created_at timestamptz not null default now()
);
create index payments_appointment_id_idx on payments(appointment_id);

-- ============= VISIT REPORTS =============
create table visit_reports (
  id uuid primary key default gen_random_uuid(),
  appointment_id uuid not null references appointments(id) on delete cascade unique,
  pet_id uuid not null references pets(id) on delete cascade,
  groomer_notes text,
  matting text,
  skin_issues text,
  behavior_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table visit_report_photos (
  id uuid primary key default gen_random_uuid(),
  visit_report_id uuid not null references visit_reports(id) on delete cascade,
  photo_url text not null,
  kind text check (kind in ('before','after')) default 'before',
  created_at timestamptz not null default now()
);

-- ============= RLS: single-user public app, anon key allowed full access =============
alter table clients enable row level security;
alter table pets enable row level security;
alter table services enable row level security;
alter table appointment_series enable row level security;
alter table appointments enable row level security;
alter table appointment_services enable row level security;
alter table payments enable row level security;
alter table visit_reports enable row level security;
alter table visit_report_photos enable row level security;

create policy "anon full access" on clients for all using (true) with check (true);
create policy "anon full access" on pets for all using (true) with check (true);
create policy "anon full access" on services for all using (true) with check (true);
create policy "anon full access" on appointment_series for all using (true) with check (true);
create policy "anon full access" on appointments for all using (true) with check (true);
create policy "anon full access" on appointment_services for all using (true) with check (true);
create policy "anon full access" on payments for all using (true) with check (true);
create policy "anon full access" on visit_reports for all using (true) with check (true);
create policy "anon full access" on visit_report_photos for all using (true) with check (true);

-- ============= STORAGE: before/after photos =============
insert into storage.buckets (id, name, public)
values ('visit-photos', 'visit-photos', true)
on conflict (id) do nothing;

create policy "public read visit photos" on storage.objects
  for select using (bucket_id = 'visit-photos');
create policy "anon upload visit photos" on storage.objects
  for insert with check (bucket_id = 'visit-photos');
create policy "anon update visit photos" on storage.objects
  for update using (bucket_id = 'visit-photos');
create policy "anon delete visit photos" on storage.objects
  for delete using (bucket_id = 'visit-photos');

-- ============= SEED DEFAULT SERVICES =============
insert into services (name, description, base_price, sort_order) values
  ('Bath & Brush', 'Shampoo, conditioner, blow dry, brush out', 45, 1),
  ('Full Groom', 'Bath, haircut, nail trim, ear cleaning', 75, 2),
  ('Nail Trim', 'Nail trim only', 15, 3),
  ('De-Shedding Treatment', 'Undercoat de-shedding treatment', 30, 4),
  ('Ear Cleaning', 'Ear cleaning & plucking', 10, 5),
  ('Teeth Brushing', 'Teeth brushing add-on', 10, 6),
  ('Sanitary Trim', 'Sanitary/hygiene trim', 15, 7),
  ('Face Trim', 'Face/feet/fanny trim', 15, 8);
