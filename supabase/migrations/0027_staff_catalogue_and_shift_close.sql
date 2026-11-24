-- Store keepers create medicines (and their categories) from the Add stock /
-- Opening stock pickers, so the catalogue write policies must match the client
-- permission matrix and the picker affordance.
drop policy if exists rls_categories_write on categories;
create policy rls_categories_write on categories for all to authenticated
using (has_role('super_admin', 'admin', 'pharmacist', 'store_keeper'))
with check (has_role('super_admin', 'admin', 'pharmacist', 'store_keeper'));

drop policy if exists rls_medicines_write on medicines;
create policy rls_medicines_write on medicines for all to authenticated
using (has_role('super_admin', 'admin', 'pharmacist', 'store_keeper'))
with check (has_role('super_admin', 'admin', 'pharmacist', 'store_keeper'));

-- close_shift already allows an owning cashier in its SECURITY DEFINER body;
-- no SQL change is needed here. The client row-action fix lives in
-- lib/features/shifts/screens/shifts_screen.dart.
