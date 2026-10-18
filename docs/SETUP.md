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
   Or, without the CLI: open the **SQL editor** and run each file in `supabase/migrations/` in name order.
   Do not run `supabase/seed.sql` against the real project; it is sample data.
3. In the Supabase dashboard, open **Authentication → Users** and create a login for each owner and for the admin (**Add user → Create new user**, tick **Auto confirm user**). Check each email carefully: step 4 links people by email, so a typo leaves that person without a profile.
4. In the **SQL editor**, create the business and link the logins. Replace the emails and names, and run this **once only** (running it again creates a second business):
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
5. Check that every login has a role and a name. A row with empty `role` needs the insert from "Add a login later" below:
   ```sql
   select u.email, p.role, p.full_name from auth.users u left join profiles p on p.id = u.id;
   ```
6. Deploy the frontend on Vercel: **Add New → Project**, pick this repository, and under **Environment Variables** add `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` with the values from Supabase **Project Settings → API**. The values are read when the app is built, so after changing them, redeploy (**Deployments → ⋯ → Redeploy**).

The anon key is safe in the app. Never put the `service_role` key or the database password in the app, the repository or a chat.

## Manage logins

All of these run in the Supabase **SQL editor**.

**Add a login later.** Create the user under **Authentication → Users** (tick **Auto confirm user**), then link it to the business. Use `owner` for an owner and `admin` for the IT admin:

```sql
insert into profiles (id, business_id, role, full_name)
select u.id, (select id from businesses limit 1), 'owner', 'Full Name'
from auth.users u
where u.email = 'their@email.com';
```

**Reset a password.** The app has no "set new password" page yet, so set it directly. The editor shows "No rows returned" even when it worked; sign in to check.

```sql
update auth.users
set encrypted_password = extensions.crypt('NEW-PASSWORD', extensions.gen_salt('bf'))
where email = 'their@email.com';
```

**Check a password or find a mistyped email.** Lists every login and whether the password matches:

```sql
select email, encrypted_password = extensions.crypt('PASSWORD', encrypted_password) as password_ok
from auth.users;
```

**Remove or stop a login.** Deleting a user who has not recorded anything also deletes their profile; add it again as above if you recreate them. Once someone has recorded payments or days, Supabase refuses the delete, because the history keeps who did what. To stop that person from signing in, use **Ban user** on **Authentication → Users**, or change their password.
