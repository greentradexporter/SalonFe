# SalonFe

SalonFe is a Flutter app for discovering salons, sharing salon pages, booking services, and managing a salon's appointments and shop profile. Customers can browse as guests; booking requires sign-in. Salon owners have a separate workspace for requests, live bookings, services, staff, and balances.

This is the original Pritze repository, renamed to SalonFe. The existing Android/iOS application ID (`com.trimtime.app`) and Firebase project (`trimtime-46539`) remain unchanged to preserve installed apps, accounts, and bookings.

## Project structure

| Directory | Purpose |
| --- | --- |
| `lib/` | Customer and salon-owner Flutter application |
| `assets/` | SalonFe branding, service artwork, and shared legal policy content |
| `android/`, `ios/` | Native app configuration and platform integrations |
| `functions/` | Firebase booking, authentication, finance, and public salon-page backend |
| `admin/` | SalonFe Control Center source, synchronized with the published admin website |
| `hosting/` | Public website, Privacy Policy, Terms, and app-link association files |
| `test/` | Flutter regression tests |
| `docs/` | Feature implementation, release, and operational notes |
| `scripts/` | Asset generation, release checks, and cloud maintenance helpers |

## Local development

Use Flutter with Dart 3.11 or newer and Node.js 22 for the backend and admin website.

```sh
 git clone https://github.com/greentradexporter/SalonFe.git
 cd SalonFe
 flutter pub get
 flutter run
```

```sh
 cd functions
 npm ci
 node --test *_logic.test.js
```

```sh
 cd admin
 npm ci
 npm run dev
```

For app checks, run `flutter analyze` and `flutter test`. Admin checks use `npm test` inside `admin/`. Firestore integration tests require the Firebase Emulator Suite; see `functions/package.json` for the emulator command.

Production signing keys, reviewer credentials, local environment files, generated releases, and cloud audit snapshots are excluded from source control. Configure signing and authorized Firebase access separately. Maintenance scripts can change production when their explicit apply/deploy options are used; review their documentation first.

## Branding and release

The brand is **SalonFe**, using coral `#FF7B54`, white, and black. Shared Flutter branding lives in `lib/theme/app_brand.dart` and `lib/theme/app_theme.dart`. Successful and cancelled booking status colours remain green and red.

The current release source is **1.0.31+61**: available on Google Play and submitted to Apple for review with automatic release after approval. See [release notes](docs/salonfe_1_0_31_release.md), [discovery and sharing changes](docs/salonfe_discovery_updates.md), and [admin cloud repair notes](docs/admin_cloud_access_repair.md).

SalonFe Control includes [customer discovery location profiles](docs/admin_customer_location.md) under Customers → Profile, showing the last consent-based approximate snapshot when one is saved.

- [Public website](https://trimtime-46539.web.app)
- [Privacy Policy](https://trimtime-46539.web.app/privacy)
- [Terms & Conditions](https://trimtime-46539.web.app/terms)
- [SalonFe Control Center](https://pritze-control-center.greentradexporter.chatgpt.site/)

Existing hosting addresses and backend field names retain legacy identifiers where changing them would break deployed links or stored data.
