# Release verification — 10 October 2026 (Philippine time)

## Verified

- 20 non-destructive live HTTP probes pass: all 13 admin actions reject missing authentication; forged tokens, invalid status links and foreign origins are rejected; direct registration reads and admin RPC calls are denied; private receipt listing reveals no files; public calendar works.
- All nine application tables have RLS and deny direct SELECT to anon/authenticated roles. All 14 application database functions deny direct execution to those roles and use invoker security.
- Receipts remain private. Both image buckets cap uploads at 2 MB and restrict MIME types.
- Only the intended organizer retains administrator membership. The disabled dummy login remains disabled and has no admin membership.
- 16 Node tests pass, including HTML escaping, CSV formula protection, validation, status tokens, test-email recipient restrictions, session refresh concurrency, sign-out races, and readable gateway errors.
- The rollback database test covers 200 registrations, eight pages, duplicate retry prevention, no overbooking, and a 201st waitlisted entrant. It leaves no fixture records and sends no emails.
- Activity queries work under the actual service role without granting access to auth.users.

## Polishing included

Consistent responsive admin frames and typography; paged and filtered lists; private payment review; retry states; 30-second client request timeouts; one refresh for concurrent expired-session requests; sign-out remains effective during a pending refresh; idempotent tournament IDs across retries; stronger CSV escaping.

The CSP allows the inspected Netlify public badge script by its exact SHA-256 hash only. It does not allow arbitrary inline scripts. A future Netlify badge script change may require revalidation.

## Deployment and launch requirements

The backend is deployed separately to Supabase. Upload the final ZIP to the existing Netlify project's Deploys page for the client and headers. The ZIP includes all prior frontend fixes.

Email credentials are not authorized yet. Development mode permits only the configured testing inbox. Production confirmation delivery must be configured and verified before promising emails to players.

Supabase reports leaked-password protection disabled. Review https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection before launch; availability depends on the Supabase plan. Use a unique admin password and keep access restricted to the intended organizer.

This is a targeted functional/security review, not an exhaustive penetration test. The 200-player database test is sequential in a transaction, not a simultaneous 200-browser load test. No claim of zero vulnerabilities, unlimited traffic, or zero downtime is made. A signed-in visual walkthrough and final manual GCash/email end-to-end test remain launch checks.

## Reproduction

- `npm test`
- `npm run check`
- `python tests/security-smoke.py` (live read/denial checks, no privileged credentials)
- `tests/capacity-200.sql` (transaction rolls back)
