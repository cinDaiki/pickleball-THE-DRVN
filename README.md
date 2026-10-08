# The DRVN — Pickleball Davao

Tournament website, private organizer dashboard, guest registration and manual GCash verification.

## Architecture

- `public/`: responsive static website for Netlify; preserves the four supplied brand photos and reduced-motion-aware animation.
- `supabase/functions/drvn-api/`: authenticated admin API, public registration/status endpoints, private receipt handling, email worker. Uses Supabase-provided server credentials; none are shipped to browsers.
- `supabase/migrations/`: server-only PostgreSQL tables and transactional registration, capacity, payment review, waitlist and cancellation routines.
- `tests/`: input/security unit tests and a rollback-only PostgreSQL workflow test.

The backend project is `nrxlfjtzdwkdvwbmrphx`. API functions perform their own admin authentication using Supabase Auth and an explicit `drvn_admins` allowlist. The edge gateway JWT check is disabled intentionally to allow account-free player registration; every admin action still checks identity and role. Database tables and RPCs are inaccessible to anon/authenticated roles.

## Development

Node 22+: `npm test` and `npm run check`.

`npm run dev` serves `public/` at http://localhost:4173. Open `/admin/login.html` locally (production Netlify supports `/admin/login`). The local UI uses the connected Supabase project; do not submit real/test registrations casually. `tests/database.sql` runs inside a transaction and rolls back every fixture.

## Launch setup

1. Create/invite the intended organizer through Supabase Authentication. The owner chooses their own password. Grant only that user's UUID membership in `public.drvn_admins` using the SQL editor. Never add all authenticated users.
2. Sign in at `/admin/login`, open Settings and save organizer contact email, actual GCash account name/number/QR, reservation duration and refund policy. Paid registrations are blocked until GCash details exist.
3. Set Supabase Edge Function secrets: `SITE_URL=https://shainetesting.netlify.app` and the Gmail test configuration described below. Alternatively select Resend with `EMAIL_PROVIDER=resend`, `RESEND_API_KEY`, `EMAIL_FROM` (verified sending domain), and optional `EMAIL_REPLY_TO`. No email is sent while sending credentials are absent. New workflow events queue messages and process batches in the background. The Emails tab shows pending/sent/failed and supports manual retries/batch processing. Provider acceptance is not a delivery guarantee. Heavy traffic should use a scheduled worker to drain remaining batches.
4. `STATUS_TOKEN_SECRET` is optional before first real registration; otherwise the Supabase service-role key is used for HMAC. Set a dedicated random persistent secret before launch. Changing the secret later changes regenerated email links; preserve it. Existing saved status links remain usable because their hashes are stored.
5. Create real tournaments/categories as drafts, inspect dates (Asia/Manila), fees and capacities, upload approved photos, then publish.
6. Publish the `public/` folder to the existing Netlify project. `_redirects` and `_headers` are included for manual deployments; `netlify.toml` supports Git deployment. No Netlify server secrets or functions are required.

## Payment behavior

Registration locks the category while checking capacity; one team is one slot. Unpaid reservations expire. Proof under review holds an existing reserved slot. Expired entries may submit proof but cannot displace another reservation. Verification requires an exact amount, an available slot and an unused verified reference. Corrections/rejections retain a trace and support resubmission. Admins explicitly record refunds only after actually refunding in GCash; the app never moves money. Event cancellation queues notices and retains payment/refund history.

Receipts are private with admin-only, two-minute signed links. Public event photos are intentionally public. Players use a private random-looking bearer link; they should not forward it. Requests have size/type validation and per-IP throttling; admins use short-lived Supabase sessions held in tab session storage.

## Pending production checks

Before accepting payments: verify the organizer account, actual QR recipient, a real test registration and receipt, delivery to Gmail, correction/rejection/refund workflow, and mobile behavior. No test tournaments or payments are seeded into production. Payment review always requires comparison against GCash's actual transaction history.

## Initial development configuration

The intended organizer account is `xdqwerts@gmail.com`, also used for development email sending. Account creation and password setup must be completed through Supabase’s standard Auth interface. Grant its verified user UUID access in `drvn_admins` after creation. The old `admin@gmail.com` account is a dummy and must remain disabled; do not send recovery emails to it.

GCash test details have been saved in the private database settings. The actual QR image is still required before paid registrations open. Tournament management is in the admin dashboard.

The email worker now defaults to Gmail in test mode, with `xdqwerts@gmail.com` as the sender. Set `GMAIL_APP_PASSWORD` in Supabase function secrets using an authorized Google App Password, never the normal Gmail password. Set `EMAIL_TEST_RECIPIENTS` to an explicit comma-separated list of test inboxes. Until credentials exist, the worker leaves messages queued. By default, only the sender's own inbox is allowed, and all subjects have `[TEST]`. SMTP uses TLS on port 465. Credentials and actual Gmail delivery have not been tested yet. SMTP has no provider-level idempotency guarantee; check the Sent folder before retrying a failure with an uncertain delivery outcome.

For the client handover, replace the sender and credentials and explicitly set `EMAIL_MODE=production`. The Resend path remains available with `EMAIL_PROVIDER=resend`, `RESEND_API_KEY`, and a verified `EMAIL_FROM`. Do not use a gmail.com address as a Resend sender.
