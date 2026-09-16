-- Rememberos Hasta la Médula — admin data schema
-- Run this once in the Supabase project's SQL editor (Dashboard > SQL Editor > New query).

create extension if not exists "pgcrypto";

create table if not exists events (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,
  title text not null,
  subtitle text,
  event_date date not null,
  time_range text,
  venue_name text,
  venue_location text,
  hero_image_url text,
  whatsapp_number text,
  reserved_title text,
  reserved_price numeric,
  reserved_description text,
  status text not null default 'draft' check (status in ('draft', 'active', 'past')),
  ticker_seconds int not null default 34,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- only one event can be the live "active" one shown on the homepage
create unique index if not exists one_active_event on events (status) where status = 'active';

create table if not exists ticket_tramos (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references events(id) on delete cascade,
  position int not null default 0,
  label text not null,
  price numeric,
  status text not null default 'proximamente' check (status in ('disponible', 'agotado', 'proximamente', 'secreto')),
  description text,
  cta_text text not null default 'Comprar ahora',
  created_at timestamptz not null default now()
);

create table if not exists artists (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references events(id) on delete cascade,
  position int not null default 0,
  name text not null,
  genre_tag text,
  badge text,
  confirmed boolean not null default true,
  created_at timestamptz not null default now()
);

create unique index if not exists ticket_tramos_event_position_uidx on ticket_tramos (event_id, position);
create unique index if not exists artists_event_position_uidx on artists (event_id, position);

-- keep updated_at current on events
create or replace function set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists events_set_updated_at on events;
create trigger events_set_updated_at
  before update on events
  for each row execute function set_updated_at();

-- Row Level Security: anyone can read published events/data,
-- only a logged-in admin (Supabase Auth user) can write.
alter table events enable row level security;
alter table ticket_tramos enable row level security;
alter table artists enable row level security;

drop policy if exists "public read events" on events;
create policy "public read events" on events
  for select using (status <> 'draft');

drop policy if exists "admin write events" on events;
create policy "admin write events" on events
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

drop policy if exists "public read tramos" on ticket_tramos;
create policy "public read tramos" on ticket_tramos
  for select using (
    exists (select 1 from events e where e.id = event_id and e.status <> 'draft')
  );

drop policy if exists "admin write tramos" on ticket_tramos;
create policy "admin write tramos" on ticket_tramos
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

drop policy if exists "public read artists" on artists;
create policy "public read artists" on artists
  for select using (
    exists (select 1 from events e where e.id = event_id and e.status <> 'draft')
  );

drop policy if exists "admin write artists" on artists;
create policy "admin write artists" on artists
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

-- storage bucket for event hero photos uploaded from the admin panel
insert into storage.buckets (id, name, public)
values ('event-images', 'event-images', true)
on conflict (id) do nothing;

drop policy if exists "public read event-images" on storage.objects;
create policy "public read event-images" on storage.objects
  for select using (bucket_id = 'event-images');

drop policy if exists "admin write event-images" on storage.objects;
create policy "admin write event-images" on storage.objects
  for insert with check (bucket_id = 'event-images' and auth.role() = 'authenticated');

drop policy if exists "admin update event-images" on storage.objects;
create policy "admin update event-images" on storage.objects
  for update using (bucket_id = 'event-images' and auth.role() = 'authenticated');

drop policy if exists "admin delete event-images" on storage.objects;
create policy "admin delete event-images" on storage.objects
  for delete using (bucket_id = 'event-images' and auth.role() = 'authenticated');

-- seed: the current Tardeo Remember event, so the site has real data from minute one
insert into events (slug, title, subtitle, event_date, time_range, venue_name, venue_location, hero_image_url, whatsapp_number, reserved_title, reserved_price, reserved_description, status, ticker_seconds)
values (
  'tardeo-remember-nov-2026',
  'Tardeo Remember',
  'Old School · Remember Session',
  '2026-11-14',
  '17:00h — 00:00h',
  'Coyote Club',
  'Seseña (Toledo)',
  'uploads/foto-tardeo-limpia.jpg',
  '34640129711',
  '5 personas + botella + 8 refrescos',
  100,
  'Zona reservada con mesa propia. Plazas limitadas: se confirman por orden de reserva.',
  'active',
  34
)
on conflict (slug) do nothing;

insert into ticket_tramos (event_id, position, label, price, status, description, cta_text)
select id, 1, 'Tramo 1', 10, 'disponible', 'Entrada anticipada. Acceso de 17:00h a 00:00h.', 'Comprar ahora'
from events where slug = 'tardeo-remember-nov-2026'
on conflict (event_id, position) do nothing;

insert into ticket_tramos (event_id, position, label, price, status, description, cta_text)
select id, 2, 'Tramo 2', 13, 'disponible', 'Entrada + consumición incluida. Acceso de 17:00h a 00:00h.', 'Comprar ahora'
from events where slug = 'tardeo-remember-nov-2026'
on conflict (event_id, position) do nothing;

insert into ticket_tramos (event_id, position, label, price, status, description, cta_text)
select id, 3, 'Tramo 3', null, 'proximamente', 'Se abrirá cuando el Tramo 2 se agote. Avisamos en Instagram.', 'Muy pronto'
from events where slug = 'tardeo-remember-nov-2026'
on conflict (event_id, position) do nothing;

insert into ticket_tramos (event_id, position, label, price, status, description, cta_text)
select id, 4, 'Tramo 4', null, 'secreto', 'Un nombre que no esperas. Se anuncia días antes del evento.', 'Secreto'
from events where slug = 'tardeo-remember-nov-2026'
on conflict (event_id, position) do nothing;

insert into artists (event_id, position, name, genre_tag, badge, confirmed)
select id, 1, 'Rafa XL', 'Old School', 'Cabeza de cartel', true
from events where slug = 'tardeo-remember-nov-2026'
on conflict (event_id, position) do nothing;

insert into artists (event_id, position, name, genre_tag, badge, confirmed)
select id, 2, 'RTS · Roberts Total Sound', 'Old School', null, true
from events where slug = 'tardeo-remember-nov-2026'
on conflict (event_id, position) do nothing;

insert into artists (event_id, position, name, genre_tag, badge, confirmed)
select id, 3, 'Por confirmar', 'Pronto', null, false
from events where slug = 'tardeo-remember-nov-2026'
on conflict (event_id, position) do nothing;

insert into artists (event_id, position, name, genre_tag, badge, confirmed)
select id, 4, 'Por confirmar', 'Pronto', null, false
from events where slug = 'tardeo-remember-nov-2026'
on conflict (event_id, position) do nothing;
