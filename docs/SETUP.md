# Setup

## Run it locally

Needs Node 20+ and Docker.

```sh
npm install
npm run db:start          # local Supabase: database, login and API; applies migrations and supabase/seed.sql
cp .env.example .env.local # then paste the API URL and anon key that db:start printed
npm run dev               # http://localhost:5173
```

Sign in with `owner@example.com` / `password123` (sample data from `supabase/seed.sql`). `npm run db:reset` wipes the local database and reloads the sample data.

## Put it online

1. Create a project at [supabase.com](https://supabase.com).
2. Apply the schema:
   ```sh
   npx supabase login
   npx supabase link --project-ref <your-project-ref>
   npx supabase db push
   ```
   Do not run `supabase/seed.sql` against the real project; it is sample data.
3. In the Supabase dashboard, open **Authentication → Users** and create a login for each owner and for the admin.
4. In the **SQL editor**, create the business and link the logins. Replace the emails and names:
   ```sql
   with b as (insert into businesses (name) values ('Dreams ''N Grace Taxi') returning id)
   , s as (insert into business_settings (business_id) select id from b)
   , r as (
     insert into boundary_rates (business_id, min_unit_age_years, max_unit_age_years, daily_amount, effective_from)
     select id, 0, 5, 1200, current_date from b
     union all select id, 5, null, 1100, current_date from b
   )
   insert into profiles (id, business_id, role, full_name)
   select u.id, b.id, x.role::user_role, x.full_name
     from b, (values
       ('father@example.com', 'owner', 'Father'),
       ('mother@example.com', 'owner', 'Mother'),
       ('dan@example.com',    'admin', 'Dan')
     ) as x(email, role, full_name)
     join auth.users u on u.email = x.email;
   ```
5. Deploy the frontend (for example on Vercel) with `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` set to the project's values from **Project Settings → API**.
