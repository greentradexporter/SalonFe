# SalonFe discovery and onboarding update — 24 November 2026

Individual salons use `https://trimtime-46539.web.app/s/<salon-id>`. The native
share sheet is available from each customer salon card and detail page. Android
App Links and iOS Universal Links open that exact salon in the updated app.
The fallback page displays an approved public listing with store links and an
explicit app-opening button. After installing, return to the same shared link;
this does not implement deferred attribution through the stores. Pending,
rejected, suspended and missing listings are unavailable on the public page.
Only allowlisted public listing fields are rendered. Names and photos are
escaped. Existing package identifiers, referral links and sign-in schemes stay.

Customer sign-in has a top Skip button. Guests can browse and follow salon
links; existing booking sign-in checks still apply in the UI and server. An
owner or barber opening a salon link stays in their own account, with a notice.
Service illustrations now distinguish facial masks, spa stones, makeup tools,
waxing, threading, hands, feet and other services without shared raster fallbacks.

Optional discovery permission is explained before the OS request. A one-shot
foreground location is rounded to three decimal places. For guests it stays in
memory; with consent it is saved privately to the signed-in customer's profile.
It never automatically starts arrival sharing. Profile has controls to allow a
fresh location reading or clear the saved location. Declining does not block
browsing or booking. Coordinates are cleared from memory on logout. Firestore
rules restrict writes to the customer and reads to the account owner.

Shop registration/edit stores ISO weekdays (Monday 1 through Sunday 7). Slot
lists exclude closed days and instant bookings are disabled on those days.
Create and reschedule handlers validate the salon's current closed days inside
the booking transaction. Legacy clients omitting the field preserve existing
closed days. Changing a day does not cancel existing bookings. The customer
salon detail lists weekly closed days.

“No referral code” persists an account-scoped choice locally and advances
without waiting for a network call. Its server acknowledgement runs separately,
with a durable pending marker and bounded retry backoff. It resumes after app
restart/foregrounding; cached profile snapshots cannot re-open onboarding while
that choice is pending. Entering an actual code still requires server validation.
The no-code server path no longer reads the unrelated referral document. No
referral CPU, minimum-instance or instance-cap increase was made.

Privacy Policy and Terms are available offline in Profile and partner account
menus. `assets/legal/policies.json` is the shared content source. Run
`python3 scripts/render_legal_policies.py` to render the public pages. Operator
Mayur Muley and support greentradexporter@gmail.com / +91 89996 08278 were
confirmed by the owner. Privacy explains both discovery and arrival sharing.

## Deployment

Seven named Mumbai functions were deployed without deleting four legacy US
functions. The same reviewed source bundle is then applied to those four legacy
handlers by `scripts/deploy_legacy_salon_features.py`, changing only
`buildConfig.source` and verifying that CPU, memory, concurrency, scaling,
identity, secrets and environment stay unchanged. Its snapshots and resumable
progress are in ignored `output/salon-discovery/legacy-deployment/`.

Hosting includes the `/s/**` rewrite, app association files, `/privacy` and
`/terms`. Location privacy and closed-day rules were published. Mobile changes
need a new Android/iOS store release; a debug/simulator build is verification,
not a store submission. This change does not advance store release metadata.

## Verification

Flutter static analysis and focused entry/owner/discovery tests, plus existing
Android/iOS guest booking tests. Node tests cover closed-day boundaries in India,
input validation, safe public HTML, and existing referral/accounting logic.
Firestore emulator tests exercise actual create/reschedule/referral/shop
handlers and private profile access. A real Cutting Edge Plus link returns
HTTP 200 with the salon-specific app link; invalid/missing listings must return
404. Android debug and iOS simulator compilation check native configuration.

An existing booking-workflow source assertion expects the obsolete iOS public
build floor 28; the repository uses 58. That unrelated stale assertion was not
changed or counted as a passing test.

## Final deployment checks

The seven Mumbai deployments and four existing US source updates succeeded.
Live checks returned 200 for Cutting Edge Plus, Privacy and Terms, 404 for a
missing salon, and 401 for unauthenticated booking/referral calls in both regions.
All 21 focused Flutter flow tests, three existing guest booking tests, 16 logic
tests and six Firestore-emulator security/integration tests passed. Static
analysis reported no issues. Final Android debug and iOS simulator compilation succeeded. Location denials are remembered; Profile offers a device-settings shortcut when permission is off.

Firebase resets external Cloud Run settings during source deployment. The
recorded pre-update revisions are in `runtime-baselines.json`. The post-deploy
`scripts/restore_salon_feature_runtime.py` restores their scaling/boost safeguards
without changing CPU or memory: the existing createBooking warm instance and
20-instance cap, reschedule cap 3, admin/profile/referral caps 5, and previously
disabled startup boosting. Shop's existing settings stay unchanged. The new
public share page has zero minimum instances, cap 3 and startup boosting off.
Explicit source options now record the prior regional caps for future deploys.
The referral service remains 0.1666 CPU and concurrency 1.
