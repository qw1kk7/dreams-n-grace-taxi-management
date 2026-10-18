-- Local development data only (loaded by `supabase db reset`). Never run against production.
-- Sign in with owner@example.com / password123.

insert into businesses (id, name)
values ('00000000-0000-0000-0000-0000000000b0', 'Dreams ''N Grace Taxi');
insert into business_settings (business_id) values ('00000000-0000-0000-0000-0000000000b0');

insert into boundary_rates (business_id, min_unit_age_years, max_unit_age_years, daily_amount, effective_from) values
  ('00000000-0000-0000-0000-0000000000b0', 0, 5, 1200, '2020-01-01'),
  ('00000000-0000-0000-0000-0000000000b0', 5, null, 1100, '2020-01-01');

-- Owner login for local testing.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  created_at, updated_at, raw_app_meta_data, raw_user_meta_data,
  confirmation_token, recovery_token, email_change_token_new, email_change
) values (
  '00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000a1',
  'authenticated', 'authenticated', 'owner@example.com', crypt('password123', gen_salt('bf')), now(),
  now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''
);
insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
values (
  gen_random_uuid(), '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a1',
  '{"sub":"00000000-0000-0000-0000-0000000000a1","email":"owner@example.com"}', 'email', now(), now(), now()
);
insert into profiles (id, business_id, role, full_name)
values ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b0', 'owner', 'Sample Owner');

-- Sample fleet (made-up names and plates).
insert into vehicles (business_id, plate_number, unit_number, make, model, first_registered_on, registration_expires_on) values
  ('00000000-0000-0000-0000-0000000000b0', 'SMP 1001', '1', 'Toyota', 'Vios', '2023-03-15', '2027-03-15'),
  ('00000000-0000-0000-0000-0000000000b0', 'SMP 1002', '2', 'Toyota', 'Vios', '2019-06-01', '2026-06-01'),
  ('00000000-0000-0000-0000-0000000000b0', 'SMP 1003', '3', 'Hyundai', 'Accent', '2021-11-20', '2026-11-20');

insert into drivers (business_id, full_name, contact_number, hire_date) values
  ('00000000-0000-0000-0000-0000000000b0', 'Juan Sample', '0917 000 0001', '2018-02-01'),
  ('00000000-0000-0000-0000-0000000000b0', 'Pedro Example', '0917 000 0002', '2024-05-10');
