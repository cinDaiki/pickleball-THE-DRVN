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

## Tournament workspaces — 2026-10-10

- Additive summary RPC and authenticated API actions; no table/record migration or deletion.
- Tournaments open Overview, Players, Categories, Registrations, Payments, Photos and Reports. Existing global screens remain available. Saves return to the event workspace.
- Existing frame geometry, sidebar widths, content maximum width, card grids, breakpoints and table scrolling retained. Only scoped workspace navigation styles added; four metric cards remain in place while loading.
- Per-event searches, pagination and exports; wrong-event receipt/review/entry actions rejected when workspace context is supplied. Late responses cannot replace the active event or editor.
- Counts distinguish entries from player places (teams count as two; repeat participants across categories count per entry). Collections exclude recorded refunds. Expired unpaid reservations do not occupy slots.
- Cancelled events remain readable; editor refuses to reopen them accidentally through a default status selection.
- `npm test`: 22 passing, including DOM navigation/race/retry tests and workspace mutation-boundary tests. `npm run check`: passed.
- `tests/tournament-workspace.sql`: passed against Supabase in a rolled-back transaction, with 202 entries in event A and a distinct event B, mixed individual/team entries, payments, refunds, expiration, pagination and authorization checks. This is not a concurrent browser load test.
- Before/after fingerprints of all existing tournament, category, registration and payment rows matched exactly (1 tournament, 2 categories, 1 registration, 1 payment).
- Supabase migration `20261010064719_tournament_workspace_summary` applied; edge function v8 deployed. The prior frontend remains compatible.
- Netlify frontend deployment and visual desktop/mobile acceptance remain pending: the available cloud browser is signed out of Netlify. DOM tests do not prove pixel-level layout or responsive rendering.
- Existing Auth advisor warning remains: leaked-password protection is disabled. Email sender credentials still require separate configuration; this change does not send test messages or enable delivery.
- Live read-only security smoke: all 22 checks passed, including both new endpoints rejecting unauthenticated access. Summary RPC also succeeded under `service_role` (not only the SQL editor owner).
