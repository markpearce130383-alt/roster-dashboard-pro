# Roster Dashboard Pro

Static HTML roster app with Supabase authentication, approved-user access control, and cloud sync.

Important: roster data is shared across approved users. Admins can edit the shared roster, while non-admin accounts are read only.

The app also includes an admin-only `Email roster` panel that can send the current month to an `n8n` workflow through a Netlify function.

## Files

- `Roster Dashboard Pro.html`: main app
- `supabase-setup.sql`: database schema, RLS policies, and approval table
- `supabase-config.example.js`: safe example config for the frontend
- `supabase-config.js`: live local config file with your real Supabase values, ignored by Git
- `netlify/functions/send-roster-email.js`: Netlify proxy that verifies the signed-in admin and forwards roster email requests to `n8n`

## Local setup

1. Create a Supabase project.
2. Run `supabase-setup.sql` in the Supabase SQL editor.
3. Copy `supabase-config.example.js` to `supabase-config.js`.
4. Put your Supabase project URL and anon public key into `supabase-config.js`.
5. Open `Roster Dashboard Pro.html` in a browser or serve the folder locally.

If you already had an older per-user version of this app, run `supabase-setup.sql` again after pulling the latest files so it can create the shared tables and migrate the newest roster data.

## User approval

Users can register in the app, but only approved users can access roster data.
Admins can approve registrations inside the app from the user approvals panel.

Make the first admin with:

```sql
update public.approved_users
set approved = true,
    is_admin = true,
    approved_at = now()
where email = 'person@example.com';
```

After that, that admin can sign into the app, approve other users from the approvals panel, and edit the shared roster for everyone else. Approved non-admin users will see the same roster in read-only mode.

If email confirmation is enabled in Supabase Auth, add your exact live app page URL to Supabase `Authentication` -> `URL Configuration` -> `Redirect URLs`.
For this project, prefer the full app page URL, for example:

- `https://your-site.netlify.app/Roster%20Dashboard%20Pro.html`

instead of relying only on the site root redirect.

When signing up from `localhost` or a home-network testing URL, the app now falls back to Supabase's configured `Site URL` instead of embedding the local address into the confirmation email. Set Supabase `Site URL` to your live app domain so verification links open correctly on phones and other devices.

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

## Netlify email proxy

If you want the app to send a beautifully formatted roster email through `n8n`, deploy this repo on Netlify as well so the browser can call the built-in serverless function without exposing your real `n8n` webhook URL.

The app sends the current month roster to:

- `/.netlify/functions/send-roster-email`

That function:

- verifies the current Supabase session token
- confirms the sender is an approved admin in `approved_users`
- forwards the roster payload to your private `n8n` webhook

Set these Netlify environment variables:

- `SUPABASE_SERVICE_ROLE_KEY`
- `N8N_ROSTER_EMAIL_WEBHOOK_URL`
- `N8N_ROSTER_EMAIL_WEBHOOK_SECRET`
  Optional but recommended. If set, it is sent to `n8n` as `x-roster-webhook-secret`.
- `EMAIL_PROXY_ALLOWED_ORIGIN`
  Optional. Use your live app origin, for example `https://your-site.netlify.app`.

Notes:

- The service role key must only live in Netlify environment variables, never in the frontend.
- `SUPABASE_URL` and `SUPABASE_ANON_KEY` are already public in the committed frontend config for this project, so the Netlify function can reuse those values without storing them as Netlify env vars.
- If you keep using GitHub Pages for the app UI, this Netlify function path will not exist on that domain. The simplest setup is to deploy the same app on Netlify when you want email sending.
- The recipients box supports multiple addresses separated by commas, semicolons, or new lines.

## Email troubleshooting

- Redeploy the Netlify site after adding or changing any environment variable. Function runtime env vars are not updated in old deploys.
- Make sure the env vars are available to Netlify Functions, not only the build UI.
- If Netlify secrets scanning fails because `SUPABASE_URL` or `SUPABASE_ANON_KEY` match values committed in the repo, remove those two env vars from Netlify. They are public values and are not required there for this project.
- Check Netlify Function logs for the returned `stage` values:
  - `env_check`
  - `auth`
  - `admin_check`
  - `payload_validation`
  - `forward_to_n8n`
- If you are using the `n8n` test webhook URL, click `Listen for test event` before sending from the roster app.
- If you are using the `n8n` production webhook URL, the workflow must be activated.
- If `N8N_ROSTER_EMAIL_WEBHOOK_SECRET` is set in Netlify, it must exactly match whatever your `n8n` workflow expects from the `x-roster-webhook-secret` header.
- If Netlify reports success but the email still does not arrive, check the `n8n` execution log and then the SMTP node output.
- If the `n8n` workflow runs but email sending fails, verify your SMTP credentials, server, port, encryption mode, and sender address.
- If the frontend says the user is not an approved admin, confirm the current user row in `approved_users` is both `approved = true` and admin via `is_admin = true`, `admin = true`, or `role = 'admin'`.
