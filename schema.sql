-- Ejecutar en SQL Editor. Compatible con la primera versión; no borra productos.
begin;
create table if not exists public.admins(user_id uuid primary key references auth.users(id) on delete cascade);
alter table public.admins enable row level security;
drop policy if exists "Admin ve su autorización" on public.admins;
create policy "Admin ve su autorización" on public.admins for select to authenticated using(user_id=(select auth.uid()));
revoke all on public.admins from anon, authenticated;
grant select on public.admins to authenticated;
create table if not exists public.products(
 id uuid primary key default gen_random_uuid(), name text not null check(length(name) between 1 and 100),
 brand text not null check(length(brand) between 1 and 80),category text not null,family text not null,
 price integer not null check(price>=0),stock integer not null check(stock>=0),
 volume integer check(volume>0), intensity integer check(intensity between 1 and 5),
 sweetness integer check(sweetness between 1 and 5),freshness integer check(freshness between 1 and 5),
 notes text not null,description text not null,occasion text not null,longevity text not null,
 color text not null default '#9566ac' check(color ~ '^#[0-9a-fA-F]{6}$'),image text not null default '',
 updated_at timestamptz not null default now()
);
alter table public.products add column if not exists updated_at timestamptz not null default now();
alter table public.products alter column volume drop not null;
alter table public.products alter column intensity drop not null;
alter table public.products alter column sweetness drop not null;
alter table public.products alter column freshness drop not null;
alter table public.products drop constraint if exists products_category_check;
alter table public.products add constraint products_category_check check(category in('Femenino','Masculino','Unisex','Por confirmar'));
alter table public.products drop constraint if exists products_family_check;
alter table public.products add constraint products_family_check check(family in('Floral','Amaderada','Cítrica','Ámbar','Gourmand','Acuática','Aromática','Por confirmar'));
alter table public.products drop constraint if exists products_image_check;
alter table public.products add constraint products_image_check check(image='' or image like 'https://%' or image ~ '^imagenes/[a-zA-Z0-9_-]+\.(jpg|png|webp)$');
alter table public.products enable row level security;
grant select on public.products to anon,authenticated;
grant insert,update,delete on public.products to authenticated;
drop policy if exists "Catálogo público" on public.products;
create policy "Catálogo público" on public.products for select using(true);
drop policy if exists "Solo administradores modifican" on public.products;
create policy "Solo administradores modifican" on public.products for all to authenticated
using(exists(select 1 from public.admins where user_id=(select auth.uid())))
with check(exists(select 1 from public.admins where user_id=(select auth.uid())));
create table if not exists public.stock_history(
 id bigint generated always as identity primary key, product_id uuid,product_name text not null,
 old_stock integer,new_stock integer not null,actor_id uuid,actor_email text,created_at timestamptz not null default now()
);
alter table public.stock_history enable row level security;
revoke all on public.stock_history from anon,authenticated;
grant select on public.stock_history to authenticated;
drop policy if exists "Equipo lee movimientos" on public.stock_history;
create policy "Equipo lee movimientos" on public.stock_history for select to authenticated
using(exists(select 1 from public.admins where user_id=(select auth.uid())));
create or replace function public.rr_product_timestamp() returns trigger language plpgsql set search_path='' as $$
begin new.updated_at=clock_timestamp();return new;end;$$;
drop trigger if exists rr_timestamp on public.products;
create trigger rr_timestamp before update on public.products for each row execute function public.rr_product_timestamp();
create or replace function public.rr_stock_audit() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if TG_OP='INSERT' then
 insert into public.stock_history(product_id,product_name,old_stock,new_stock,actor_id,actor_email) values(new.id,new.name,null,new.stock,auth.uid(),auth.jwt()->>'email');
 elsif old.stock is distinct from new.stock then
 insert into public.stock_history(product_id,product_name,old_stock,new_stock,actor_id,actor_email) values(new.id,new.name,old.stock,new.stock,auth.uid(),auth.jwt()->>'email');
 end if;
 return new;
end;$$;
revoke all on function public.rr_stock_audit() from public,anon,authenticated;
revoke all on function public.rr_product_timestamp() from public,anon,authenticated;
drop trigger if exists rr_stock_history on public.products;
create trigger rr_stock_history after insert or update on public.products for each row execute function public.rr_stock_audit();
commit;
-- Autorizar una cuenta creada previamente desde Authentication > Users:
-- insert into public.admins(user_id) values ('UUID-DEL-USUARIO') on conflict do nothing;
-- Retirar acceso (no elimina su cuenta):
-- delete from public.admins where user_id='UUID-DEL-USUARIO';
