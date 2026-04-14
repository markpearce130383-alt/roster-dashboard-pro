# Roster Dashboard Pro

Static HTML roster app with Supabase authentication, approved-user access control, and cloud sync.

## Files

- `Roster Dashboard Pro.html`: main app
- `supabase-setup.sql`: database schema, RLS policies, and approval table
- `supabase-config.example.js`: safe example config for the frontend
- `supabase-config.js`: live local config file with your real Supabase values, ignored by Git

## Local setup

1. Create a Supabase project.
2. Run `supabase-setup.sql` in the Supabase SQL editor.
3. Copy `supabase-config.example.js` to `supabase-config.js`.
4. Put your Supabase project URL and anon public key into `supabase-config.js`.
5. Open `Roster Dashboard Pro.html` in a browser or serve the folder locally.

## User approval

Users can register in the app, but only approved users can access roster data.
Admins can approve registrations inside the app.

Make the first admin with:

```sql
update public.approved_users
set approved = true,
    is_admin = true,
    approved_at = now()
where email = 'person@example.com';
```

After that, that admin can sign into the app and approve other users from the approvals panel.

## Security notes

- The frontend uses the Supabase anon public key only.
- Never put the Supabase service role key in this project.
- `supabase-config.js` is ignored by Git so your live project settings stay local.
- Access control is enforced by Supabase Row Level Security and the `approved_users` table.

## GitHub prep

Files safe to commit:

- `Roster Dashboard Pro.html`
- `supabase-setup.sql`
- `supabase-config.example.js`
- `README.md`
- `.gitignore`

File that should stay out of Git:

- `supabase-config.js`
