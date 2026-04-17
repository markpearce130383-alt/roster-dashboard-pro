# Roster Dashboard Pro

Static HTML roster app with Supabase authentication, approved-user access control, and cloud sync.

Important: roster data is shared across approved users. Admins can edit the shared roster, while non-admin accounts are read only.

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

If you already had an older per-user version of this app, run `supabase-setup.sql` again after pulling the latest files so it can create the shared tables and migrate the newest roster data.

## User approval

Users can register in the app, but only approved users can access roster data.
Admins can approve registrations in Supabase by updating the `approved_users` table.

Make the first admin with:

```sql
update public.approved_users
set approved = true,
    is_admin = true,
    approved_at = now()
where email = 'person@example.com';
```

After that, that admin can sign into the app and edit the shared roster for everyone else. Approved non-admin users will see the same roster in read-only mode.

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

## GitHub Pages

This repo includes an `index.html` entry point so it can be published with GitHub Pages.

For GitHub Pages, the live site must be able to load a committed public config file, so put your real Supabase project URL and anon public key into `supabase-config.example.js` before deploying.

Important:

- The Supabase anon key is safe for frontend use.
- Never put the Supabase service role key into any committed file.
- `supabase-config.js` can still stay local-only for your machine and will override the committed example locally.
