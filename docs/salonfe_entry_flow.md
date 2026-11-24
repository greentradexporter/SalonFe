# SalonFe account entry

The welcome screen appears on every signed-out launch. It is not controlled
by a one-time "seen welcome" flag. The illustration's original footer has
been replaced with wording that reflects signed-in account restoration.

- Book Service opens customer phone/Gmail sign-in.
- Register Salon opens owner phone/email/Gmail sign-in directly.
- Successful login finishes any required referral onboarding and then clears
  the login/choice routes from history.
- Customers open the existing discovery screen with Discover and Profile
  destinations. There is no Partner tab or owner-registration link.
- Owners open their salon dashboard, or shop registration if their account
  does not yet have a salon. Owner pages do not link to customer home.
- Logout and leaving owner registration return to the welcome screen with
  the previous account's navigation history cleared.
- Startup waits for session restoration before choosing a screen. A cached
  role with no authenticated account does not bypass the welcome screen.
- The old partner route delegates to owner entry; an authenticated customer
  reaching it is routed back to their customer account.
- The booking-alert device walkthrough is limited to authenticated owners
  after any required referral onboarding is complete.

The account entry widget is in `lib/screens/entry/account_entry_screen.dart`.
The welcome and role-specific sign-in widgets are beside it. Existing Firebase
identity, OTP, Gmail, role validation and account persistence remain in use;
this change does not alter package IDs, credentials or backend records.

Verification: 249 Flutter tests passed and static analysis reported no issues.
Nine account-flow tests cover the paths above, alongside the existing booking
and notification regression tests. Rendered previews use local test data.

The final owner-walkthrough ordering safeguard was additionally checked with
the account-flow and device-setup suites (12 tests passed). The signed Android
release and unsigned iOS Release builds both succeeded, retaining
`com.trimtime.app` and version `1.0.28+58`.

Latest test APK: `output/salonfe/SalonFe-welcome-1.0.28-58.apk`.
Welcome preview: `output/salonfe/welcome.png`.
Build/test details: `output/salonfe/welcome-verification.json`.
This update has not been published to either app store.
