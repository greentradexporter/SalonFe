# SalonFe 1.0.31 (61)

Release request: 24 November 2026. Android package and iOS bundle ID remain
com.trimtime.app, with existing signing identities, users and backend data.

The update adds Recommended, Nearest and Highest rated sorting next to the
customer listing heading; restores the original detailed service artwork with
distinct Facial and Makeup images; and uses phone-only policy contact without
a personal operator name. Public policy pages were already deployed and verified.
Eleven approved salon pins were verified from their existing public map links.
Cutting place's link opens Chembur station, so that listing retains the missing-pin
fallback instead of an incorrect distance.

Validation before the release: 63 focused application checks, clean Flutter
analysis, and distinct-artwork asset checks. Ten Android/iOS update-version logic
tests passed after the build-number increment. Current customer-home screenshots
rendered at the existing iPhone, iPad and Android store sizes without overflow.

The four existing store update-check endpoints received candidate build 61 in
Mumbai and the legacy US region. Every deployment verified unchanged CPU, memory,
identities, min/max instance caps, environment/secret references and prior startup
boost/scaling safeguards. Android's confirmed-public floor is 60; iOS stays at 59
while the previous iOS update is still waiting for review. Store verification
continues to gate the advertised candidate.

Artifacts, store API snapshots and submission proof are kept in ignored
output/salonfe-release-61/. Signing keys and reviewer credentials are excluded
from source control. Existing approved reviewer accounts are retained.

Status: release preparation in progress. Final store states will be recorded after
signed bundle verification, uploads and submission.
