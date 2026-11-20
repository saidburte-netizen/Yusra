insert into branches (name, code) values ('Yusra Pharmacy - Main Branch', 'MAIN')
on conflict (code) do nothing;

insert into app_settings (key, value) values
  ('pharmacy_name', to_jsonb('Yusra Pharmacy'::text)),
  ('tagline', to_jsonb('Care made easy'::text)),
  ('currency', to_jsonb('ETB'::text)),
  ('vat_rate', to_jsonb(0.15::numeric)),
  ('low_stock_default', to_jsonb(10)),
  ('expiry_alert_days', to_jsonb(90)),
  ('max_cashier_discount_pct', to_jsonb(5)),
  ('receipt_footer', to_jsonb('Thank you for choosing Yusra Pharmacy. Get well soon.'::text)),
  ('address', to_jsonb(''::text)),
  ('phone', to_jsonb(''::text)),
  ('tin', to_jsonb(''::text)),
  ('license_no', to_jsonb(''::text))
on conflict (key) do nothing;

insert into categories (name) values
  ('Antibiotics'), ('Pain and fever'), ('Antimalarials'), ('Vitamins and supplements'),
  ('Heart and blood pressure'), ('Diabetes'), ('Respiratory and allergy'), ('Stomach and digestion'),
  ('Skin care'), ('Mother and baby'), ('Medical supplies'), ('Personal care')
on conflict (name) do nothing;update profiles
set role = 'super_admin',
    full_name = 'Yusra',
    branch_id = (select id from branches where code = 'MAIN')
where email = 'PUT-THE-EMAIL-HERE';select relname as table_name, relrowsecurity as rls_on
from pg_class
where relnamespace = 'public'::regnamespace and relkind = 'r'
order by relname;