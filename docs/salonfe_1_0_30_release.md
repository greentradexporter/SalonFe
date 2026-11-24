# SalonFe 1.0.30 (60) — 24 November 2026

Existing Android package and iOS bundle ID `com.trimtime.app` are preserved.
The release includes salon links and native sharing, distinct service artwork,
optional customer discovery location, guest browsing with sign-in required for
booking, weekly salon closed days enforced by booking endpoints, immediate
no-referral continuation with background acknowledgement, and in-app policies.

Google Play accepted the signed bundle with no device-support losses. Full
production rollout targets the existing country selection. Managed publishing
is off. Submission was confirmed in Publishing overview; the live update-check
endpoint subsequently verified public version code 60.

Apple build 60 processed successfully and was selected for version 1.0.30.
Automatic release after approval and immediate distribution to all existing
users are selected. Existing approved reviewer logins were retained and tested.
The description, release notes and reviewer guidance reflect the new features.
The primary iPhone home screenshot was refreshed with current artwork and the
share control; other existing screenshots remain. Account, pricing and country
settings were retained.

Signed artifacts and release proof are in ignored `output/salonfe-release-60/`.
Android SHA-256: `2e1052135e23ce5fa409f8bb2d0b266ed3d22133f74deff9c931d7304f24bee8`.
iOS SHA-256: `f22a2e50fac40f330e08f2db2a61ae1f79eb2cca2f453d4505b2a06531f60e43`.
Apple build ID: `af220b71-37e3-4d53-8817-ffe5e3180d4e`.

Flutter analysis is clean. Both release builds and signatures were verified.
Ten update-logic tests passed. Existing customer and owner demo OTP sign-in and
role checks passed. The previous feature batch passed focused app-flow,
booking-login, security and backend tests. Current home screenshots rendered
without overflow on iPhone and iPad.

The old 1.5 GB local Gradle heap stalled in repeated full garbage collection.
The build uses a 3 GB heap and 1 GB metaspace. Only the stalled/completed build
daemons for this project were stopped. No cloud CPU or quota increase was made.

Four existing update-check endpoints in Mumbai and the legacy US region received
candidate build 60 metadata. Their CPU, memory, scaling and access settings were
preserved. Public build floors were updated to verified build 59; live store
verification permits build 60 only after publication. Deployment snapshots and
live responses are recorded under `output/salonfe-release-60/backend/` and in
`update-endpoint-verification.json`.

Xcode's stored upload account session failed, so the existing Developer API key
was used through Apple's altool. No keys or roles were created. Upload succeeded
with a non-blocking advisory about a future SDK requirement. Private key material
and reviewer credentials are excluded from this record.

## Final status

Google Play lists 60 (1.0.30) as Available on Google Play, released 24 November 2026 with full rollout. The production update endpoint independently returned verified version code 60.

Apple confirmed 1 Item Submitted and iOS 1.0.30 Waiting for Review. Submission ID: `a028d49d-4a99-4a98-9374-0376d79583eb`. Automatic release after approval remains selected. This confirms submission, not public iOS availability.

Proof: `output/salonfe-release-60/google-play-live.jpg` and `output/salonfe-release-60/apple-submission.jpg`.
