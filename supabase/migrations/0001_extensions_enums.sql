create extension if not exists pgcrypto;
create extension if not exists pg_trgm with schema extensions;

create type app_role as enum ('super_admin','admin','pharmacist','cashier','store_keeper','accountant');
create type po_status as enum ('draft','ordered','partially_received','received','cancelled');
create type sale_status as enum ('completed','voided','partially_returned','returned');
create type payment_method as enum ('cash','mobile_money','card','bank_transfer');
create type movement_type as enum ('opening','purchase','sale','sale_return','void_restore','adjustment','expired_writeoff','damage');
create type shift_status as enum ('open','closed');
create type rx_status as enum ('pending','dispensed','cancelled');

create or replace function set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;