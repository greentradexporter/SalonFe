# SalonFe branding

The Customer and Salon Owner experiences share the SalonFe display name,
coral `#FF7B54` primary colour, white canvas and black primary text. Green
continues to indicate confirmed/completed bookings; red indicates rejection,
cancellation and errors. Primary filled buttons use black text on coral.

Brand assets and display-name constants live in `lib/theme/app_brand.dart`.
The colour and typography tokens remain in `lib/theme/app_theme.dart`.
`SalonFeAppBar` adds the supplied wordmark after existing page actions;
custom headers use `BrandWordmark`. Booking operations are unchanged. The
subsequent welcome and account-navigation changes are documented in
`salonfe_entry_flow.md`. The salon Home, Bookings, Shop and Balance changes are
documented in `salonfe_owner_changes.md`. Service illustrations use the supplied reference artwork in the
existing category controls.

The supplied full wordmark is used in headers and native splash images. Its
initial S is cropped into a readable launcher mark and a white Android
notification silhouette. Android icons, Android 12 splash configuration,
iPhone/iPad/App Store icon sizes, iOS launch images and Flutter web metadata
are updated. To reproduce assets with the existing Sharp tooling:

```sh
node scripts/generate_salonfe_assets.mjs '/path/to/Salonfe changes photo'
```

## Compatibility

The package/bundle ID remains `com.trimtime.app`. Firebase project configuration,
signing settings, app/store IDs, deep-link URLs, notification channel/category
IDs, preference keys, financial field names and payment reference identifiers
are preserved. Their legacy `pritze` strings are internal compatibility keys,
not customer-facing branding. Existing user/salon names are not rewritten.

## Release boundary

This is a source and build update. Existing installed apps change only after
installing the new build or receiving a store update. The iOS verification
build is unsigned and still requires signing and the normal release process.
Server notification/email copy is updated in the Firebase Functions source;
those edits require a separate production deployment to appear in messages.
No production database migration or admin login permission change is included.

Test logs and rendered widget previews are under the ignored `output/` directory.

## Verification

- Flutter analysis: no issues.
- Flutter regression suite: 239 passed; the four branding checks were also
  rerun after the final button-contrast adjustment.
- Functions tests: 159 passed; 15 emulator-dependent tests skipped.
- Android release APK built and its v2 signature verified. Packaged display
  name: SalonFe; package: `com.trimtime.app`; version: `1.0.28+58`.
- iOS Release build completed without code signing. Packaged display/name:
  SalonFe; bundle: `com.trimtime.app`; version: `1.0.28+58`.

Android test build: `output/salonfe/SalonFe-1.0.28-58.apk`.
iOS unsigned build: `build/ios/Release-iphoneos/Runner.app`.
Visual comparison: `output/salonfe/branding-preview.png` (local test data).

On this machine the native builds were run sequentially to avoid memory
contention. Android's existing 512 MB metadata limit was insufficient; the
successful build used a temporary 1024 MB metadata limit, 2048 MB heap and
two Gradle workers. The successful iOS build used two Xcode jobs. Repository
build settings were not changed.
