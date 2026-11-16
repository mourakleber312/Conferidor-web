-- EXECUTAR UMA ÚNICA VEZ no SQL Editor de um projeto Supabase NOVO.
create extension if not exists pgcrypto;

create table public.households (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 100),
  invite_code text not null unique default encode(gen_random_bytes(12), 'hex'),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);
create table public.household_members (
  household_id uuid not null references public.households(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (household_id, user_id)
);

-- SECURITY DEFINER evita recursão de RLS em consultas de participação.
create or replace function public.is_household_member(p_household uuid)
returns boolean language sql stable security definer
set search_path = '' as $$
  select exists(select 1 from public.household_members
                where household_id = p_household and user_id = (select auth.uid()));
$$;
revoke all on function public.is_household_member(uuid) from public;
grant execute on function public.is_household_member(uuid) to authenticated;

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 100),
  owner_id uuid not null references auth.users(id),
  household_id uuid references public.households(id) on delete cascade,
  created_at timestamptz not null default now()
);
create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  description text not null check (length(trim(description)) between 1 and 300),
  amount numeric(14,2) not null check (amount > 0),
  scope text not null check (scope in ('individual', 'shared')),
  owner_id uuid not null references auth.users(id),
  household_id uuid references public.households(id) on delete cascade,
  category_id uuid references public.categories(id) on delete set null,
  payment_method text not null check (payment_method in ('credito', 'pix', 'dinheiro')),
  purchase_date date not null,
  due_date date not null,
  paid boolean not null default false,
  installment_number integer not null check (installment_number between 1 and 120),
  installment_count integer not null check (installment_count between 1 and 120 and installment_count >= installment_number),
  recurrence_group_id uuid not null,
  recurrence_type text not null check (recurrence_type in ('unica', 'mensal')),
  created_at timestamptz not null default now(),
  constraint scope_household_consistency check (
    (scope = 'individual' and household_id is null) or
    (scope = 'shared' and household_id is not null)
  )
);
create index expenses_due_idx on public.expenses(due_date);
create index expenses_owner_idx on public.expenses(owner_id);
create index expenses_household_idx on public.expenses(household_id);

-- Impede que uma despesa compartilhada aponte para categoria individual
-- e que uma despesa individual use categoria compartilhada.
create or replace function public.validate_expense_category()
returns trigger language plpgsql security definer
set search_path = '' as $$
declare c record;
begin
  if new.category_id is null then return new; end if;
  select owner_id, household_id into c from public.categories where id = new.category_id;
  if not found then raise exception 'Classificação não encontrada'; end if;
  if new.scope = 'individual' and (c.household_id is not null or c.owner_id <> new.owner_id) then
    raise exception 'Classificação não pertence a esta despesa individual';
  end if;
  if new.scope = 'shared' and (c.household_id is distinct from new.household_id) then
    raise exception 'Classificação não pertence ao grupo desta despesa';
  end if;
  return new;
end;
$$;
create trigger validate_expense_category_trigger
before insert or update on public.expenses
for each row execute function public.validate_expense_category();

alter table public.households enable row level security;
alter table public.household_members enable row level security;
alter table public.categories enable row level security;
alter table public.expenses enable row level security;

create policy households_read on public.households for select to authenticated
using (public.is_household_member(id));
create policy members_read on public.household_members for select to authenticated
using (public.is_household_member(household_id));

create policy categories_read on public.categories for select to authenticated
using ((household_id is null and owner_id = (select auth.uid())) or
       (household_id is not null and public.is_household_member(household_id)));
create policy categories_insert on public.categories for insert to authenticated
with check (owner_id = (select auth.uid()) and
  (household_id is null or public.is_household_member(household_id)));
create policy categories_update on public.categories for update to authenticated
using ((household_id is null and owner_id = (select auth.uid())) or
       (household_id is not null and public.is_household_member(household_id)))
with check (owner_id = (select auth.uid()) and
  (household_id is null or public.is_household_member(household_id)));
create policy categories_delete on public.categories for delete to authenticated
using ((household_id is null and owner_id = (select auth.uid())) or
       (household_id is not null and public.is_household_member(household_id)));

create policy expenses_read on public.expenses for select to authenticated
using ((scope = 'individual' and owner_id = (select auth.uid())) or
       (scope = 'shared' and public.is_household_member(household_id)));
create policy expenses_insert on public.expenses for insert to authenticated
with check (owner_id = (select auth.uid()) and
  ((scope = 'individual' and household_id is null) or
   (scope = 'shared' and public.is_household_member(household_id))));
create policy expenses_update on public.expenses for update to authenticated
using ((scope = 'individual' and owner_id = (select auth.uid())) or
       (scope = 'shared' and public.is_household_member(household_id)))
with check (((scope = 'individual' and owner_id = (select auth.uid()) and household_id is null) or
             (scope = 'shared' and public.is_household_member(household_id))));
create policy expenses_delete on public.expenses for delete to authenticated
using ((scope = 'individual' and owner_id = (select auth.uid())) or
       (scope = 'shared' and public.is_household_member(household_id)));

-- Operações de criação e adesão com código; não há inserção pública de membros.
create or replace function public.create_household(p_name text)
returns uuid language plpgsql security definer
set search_path = '' as $$
declare new_id uuid;
begin
  if (select auth.uid()) is null then raise exception 'Faça login'; end if;
  if length(trim(coalesce(p_name, ''))) not between 1 and 100 then raise exception 'Nome inválido'; end if;
  insert into public.households(name, created_by)
  values (trim(p_name), (select auth.uid())) returning id into new_id;
  insert into public.household_members(household_id, user_id) values(new_id, (select auth.uid()));
  return new_id;
end;
$$;
create or replace function public.join_household(p_code text)
returns uuid language plpgsql security definer
set search_path = '' as $$
declare target_id uuid;
begin
  if (select auth.uid()) is null then raise exception 'Faça login'; end if;
  select id into target_id from public.households where invite_code = lower(trim(p_code));
  if target_id is null then raise exception 'Código de convite inválido'; end if;
  insert into public.household_members(household_id, user_id)
  values(target_id, (select auth.uid())) on conflict do nothing;
  return target_id;
end;
$$;
revoke all on function public.create_household(text) from public;
revoke all on function public.join_household(text) from public;
grant execute on function public.create_household(text) to authenticated;
grant execute on function public.join_household(text) to authenticated;

grant select on public.households, public.household_members to authenticated;
grant select, insert, update, delete on public.categories, public.expenses to authenticated;
