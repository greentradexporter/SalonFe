# SalonFe control center and Google Cloud access repair (12 November 2026)

The Graphix Unisex Salon was approved through the live administrator UI at the
platform owner's explicit request. Both salon and owner approval status were
verified, and Admin activity shows the immutable onboarding approval entry.

An empty Cloud Run IAM policy blocked its Firebase approval callable before
application authentication. Restoring allUsers / roles/run.invoker repaired that
transport layer; unauthenticated application requests still return HTTP 401.

A complete inventory covered 169 Cloud Run functions in asia-south1 and
us-central1, including 142 Firebase-labelled callables. Twenty more callables had
missing public transport permissions. The owner explicitly authorized repairing
all twenty. All 142 callable policies now match their public source declarations.
Scheduled and event handlers were not made public. Existing scheduled job
identities have the required invoker role, including inherited project access.

Use the read-only audit after future deployments:

    python3 scripts/audit_cloud_function_access.py --project trimtime-46539 --output output/cloud-access-audit/check

The optional --probe performs sequential malformed-envelope HTTP checks without
executing business handlers. It warms services and can consume CPU quota.
--repair-public-callables changes only Firebase-labelled callable policies whose
source explicitly declares invoker: public. Review and authorize production
permission changes before using it. Tokens stay in process memory.

The first HTTP sweep exposed quota-related 503 errors and historical failed
revisions in Mumbai. Google declined the requested no-fee CPU quota increases
(100 cores Mumbai / 50 cores US), retaining 20 cores in each region. No extra
instances, reservations, minimums, or larger instance limits were provisioned.
A configuration-only test restored updateCustomerProfileAsAdmin to its existing
source-declared 0.1666 CPU with concurrency 1. A new revision still failed while
startup CPU boosting was enabled. Disabling boost produced a healthy revision
(updatecustomerprofileasadmin-00004-k5h); unauthenticated requests now return 401.
The read-only follow-up plan found 78 other quota-failed Mumbai services: 41 can
restore source-declared fractional CPU and 37 retain their CPU allocation. The
platform owner explicitly approved this 78-service configuration-only repair. Use scripts/repair_cloud_run_capacity.py
without --apply to inspect the exact remaining plan. Registry verification found that the older deployment images had already been
removed, so a runtime-template-only update could not pull them. All 78 exact
archived source generations were verified as available. Recovery uses
scripts/recover_archived_cloud_functions.py with the original inventories and
reviewed 78-service plan. It compares original and Google-copied source archive
MD5 hashes, rebuilds the same source, resolves each fresh registry digest, disables
startup boosting, and verifies service health. It never deploys local source.
Runtime details are stored in output/cloud-access-audit. No quota increase was
granted; no larger instance caps, extra minimum instances or reservations were set.

## Published website

Site: https://pritze-control-center.greentradexporter.chatgpt.site/
Title: SalonFe Control Center
Version: 28
Source commit: 435cd566ba12ef2f8a27f7ae2a9fbcd16d846063
Canonical Sites checkout: admin-site-cleanup/.sites-checkout
Repository source mirror: admin/ (synchronized for the SalonFe GitHub update)

The previous admin checkout diverged from the hosted source. It was preserved;
the supported Sites workflow opened the canonical hosted source in a separate
directory, and published the update with the same Site ID and audience.

All visible Pritze branding, favicon, sign-in copy and CSV filenames now use
SalonFe. Firebase IDs, stored finance field names and business data remain intact.
Live Bookings defaults to current/upcoming active records using the India date,
with an overnight-service grace window. Today and History / all bookings remain
available. Intelligence validates the linked booking's current date/status,
ignores resolved and historical alerts, and limits cancellation patterns to seven
days. Current financial inconsistencies remain visible.

Verification: production build; 13 website tests, including date boundaries,
overnight services and stale-alert regression tests; eight existing backend admin
security tests. Full repository TypeScript checking encounters existing missing
Cloudflare runtime types in db/index.ts and worker/index.ts; no new dashboard type
errors were reported. Live Chrome verification confirmed the SalonFe title,
clean live queue, 415 preserved history records and filtered Intelligence view.

## Final production verification

- All 169 Cloud Run services are Ready and all 169 functions are Active.
- All 142 callable IAM policies match their public transport declarations.
- All 78 archived recoveries are healthy and original/rebuilt archive hashes match.
  Together with the successful canary, 79 quota-failed services were recovered.
- All 20 originally blocked callable endpoints reject anonymous requests through
  Firebase (19 HTTP 401; admin OTP validation HTTP 403), with browser CORS headers.
- Original memory, service identities, timeouts, min/max instance caps and
  environment values/secret versions are preserved. Cloud Run regenerated three
  secret alias names; resolving aliases confirms the same secret resources and
  version 1, without reading or changing any secret value.
- CPU quota remains 20 cores per region. Startup boost was disabled on the 79
  repaired services; source-declared fractional CPU was restored on 42 of them.
- The existing repository cleanup rule deletes images after one day. Its storage
  policy was preserved; archived builds were used rather than a paid capacity or
  retention upgrade.

For future broad deployments, deploy in small batches within regional CPU/write
quotas, then run the read-only IAM audit and inspect service readiness. A runtime
image must still exist before a template-only update; otherwise rebuild the exact
archived source with the recovery helper. Production mutations require review.

Final browser reload restored the existing User 1 session and loaded live data
from all three recovered admin data endpoints. SalonFe branding and the clean
live queue were visible. Graphix salon and owner records were rechecked as approved.
