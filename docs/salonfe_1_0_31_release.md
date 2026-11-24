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
boost/scaling safeguards. Android's confirmed-public floor is 60; live Play Store
verification now advertises 61 from both regions. iOS stays at 59 while 61 awaits
Apple review. Store verification continues to gate the advertised candidate.

Artifacts, store API snapshots and submission proof are kept in ignored
output/salonfe-release-61/. Signing keys and reviewer credentials are excluded
from source control. Existing approved reviewer accounts are retained.

Final status verified on 25 November 2026:

- Android 1.0.31 (61) is available on Google Play, with the full production rollout
  selected. Play Console records publication on 24 November at 10:30 PM. The full
  description and customer-home phone screenshot were updated with the release.
- iOS 1.0.31 (61) is Waiting for Review. Submission ID:
  `9eba812d-610a-4ab0-9e41-a7c485303646`. Build ID:
  `2135a9ad-26b8-4881-83ff-5789d7f1ff72`. The previous pending 1.0.30 submission
  was withdrawn and replaced by this build. Automatic release after approval and
  immediate availability to all users are selected.
- Both existing iPhone screenshot groups and the iPad screenshot group now show
  the current customer-home UI. Store descriptions, release notes and reviewer
  instructions match the update; existing approved demo logins are retained.

The Android bundle signature and iOS archive signature were verified, along with
the version, identifier and updated assets inside each uploaded package.

| Artifact | SHA-256 |
| --- | --- |
| SalonFe-1.0.31-61.aab | `30e3fc2043dd1ddd385421efc060161dbb57bd5e750cecc01ba3eeb2720eb350` |
| SalonFe-1.0.31-61.ipa | `8beccb4f710ea09fe0ab3130b0bdaa57a9f47da61d2be2a120eeb6c05c552f00` |

Store-state proof is saved locally as `android-live.jpg` and
`apple-submitted.jpg` in the ignored release output directory. Apple approval
remains pending; the iOS update is not yet live.
