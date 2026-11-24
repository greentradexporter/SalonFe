# SalonFe Apple release — 12 November 2026

Submitted **iOS 1.0.29 (59)** for App Store app **6792811282**, retaining bundle ID `com.trimtime.app` and developer team `A82B2BQ54N`.

App Store Connect confirmed **1 Item Submitted** and **Waiting for Review**. Automatic release after approval is selected, with immediate availability to all existing targeted users. Public availability remains subject to Apple's approval.

The submission includes the SalonFe name/subtitle, the latest customer and salon-owner app changes, the new icon and splash assets, updated description/release notes, six screenshots each for medium iPhone, large iPhone, and iPad 13-inch, and revised reviewer instructions. The old Pritze screenshot selections were replaced in the new version; assets remain recoverable in Apple's Asset Library.

Apple's former “Data Not Collected” declaration was corrected: 16 applicable data types are disclosed for app functionality, linked to user identity, with no advertising tracking. The existing hosted privacy policy and account-deletion request instructions are provided.

The user explicitly authorized sharing the two dedicated demo logins with Apple App Review. Both fixed Firebase test OTP logins and backend role claims were verified. The sample salon remains pending approval and closed. Reviewer credentials are stored in the ignored, owner-readable release file and in private review instructions, not in this document.

Validation: signed archive verified with codesign; version/name/package confirmed from the archive; App Store icon has no alpha channel; screenshot harness analysis clean; eight preview tests passed for each of the three Apple screenshot layouts. Production code had already passed Flutter analysis and 257 tests. Apple's build processing completed successfully and build 59 was selected for the submission.

The local signed IPA is `output/apple-release/SalonFe-1.0.29-59.ipa` (SHA-256 `41be548ee5ea8f8d80090c03987739ce65833952ad05a31a8fe32d3d8faff5ea`). Xcode uploaded the same archive using the existing account and signing profile. Upload succeeded with a non-blocking warning about missing optional objective_c.framework dSYM symbols.

Updated `getIosAppUpdate(asia-south1)` to candidate 59 / 1.0.29, preserving `getIosAppUpdate(us-central1)`. The live endpoint was verified to return currently public build 58 while review is pending. It advances to 59 only when the public App Store lookup serves version 1.0.29. Six iOS update logic tests passed.

Proof: `output/apple-release/apple-submission.jpg`.
