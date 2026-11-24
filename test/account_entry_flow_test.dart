import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nashik_salon_booking/main.dart';
import 'package:nashik_salon_booking/models/app_models.dart';
import 'package:nashik_salon_booking/screens/customer/customer_home_screen.dart';
import 'package:nashik_salon_booking/screens/customer/customer_profile_screen.dart';
import 'package:nashik_salon_booking/screens/entry/role_sign_in_screen.dart';
import 'package:nashik_salon_booking/screens/entry/welcome_screen.dart';
import 'package:nashik_salon_booking/screens/partner/partner_hub_screen.dart';
import 'package:nashik_salon_booking/screens/salon/salon_dashboard_screen.dart';
import 'package:nashik_salon_booking/screens/salon/salon_profile_setup_screen.dart';
import 'package:nashik_salon_booking/state/app_state.dart';
import 'package:nashik_salon_booking/state/app_state_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

Future<void> customer(AppState state) async {
  await state.loginCustomerWithPhone(
    name: 'Customer',
    phone: '9876500000',
    verificationId: 'test-verification',
    smsCode: '123456',
  );
  if (state.referralOnboardingRequired) {
    await state.completeReferralOnboarding();
  }
}

Future<void> owner(AppState state) async {
  await state.loginOwnerWithEmail(name: 'Owner', email: 'owner@example.com');
  if (state.referralOnboardingRequired) {
    await state.completeReferralOnboarding();
  }
  await state.updateOwnerSalon(
    name: 'The Style Studio',
    ownerName: 'Owner',
    address: 'Nashik',
    phone: '9000000101',
    openTime: '12:00 AM',
    closeTime: '11:59 PM',
  );
}

Future<void> launch(WidgetTester tester, AppState state) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    AppStateProvider(createAppState: () => state, child: const TrimtimeApp()),
  );
  await tester.pumpAndSettle();
}

Future<void> submitOwnerEmail(WidgetTester tester, String email) async {
  await tester.tap(find.text('Email'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('email-login-field')),
    email,
  );
  await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('email-otp-field')),
    '123456',
  );
  await tester.ensureVisible(
    find.widgetWithText(FilledButton, 'Verify and sign in'),
  );
  await tester.tap(find.widgetWithText(FilledButton, 'Verify and sign in'));
  await tester.pump();
  if (find.byKey(const ValueKey('skip-referral-code')).evaluate().isNotEmpty) {
    await tester.pump(const Duration(milliseconds: 350));
  } else {
    await tester.pumpAndSettle();
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets(
    'signed-out launch shows welcome, including after a cached role choice',
    (tester) async {
      final state = AppState(restoreActiveRole: false);
      await state.selectRole(UserRole.owner);
      await launch(tester, state);
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.text('Book Service'), findsOneWidget);
      expect(find.text('Register Salon'), findsOneWidget);
      expect(find.byType(CustomerHomeScreen), findsNothing);
      expect(find.byType(SalonDashboardScreen), findsNothing);
    },
  );

  testWidgets(
    'welcome choices open separate login flows and back returns to welcome',
    (tester) async {
      await launch(tester, AppState(restoreActiveRole: false));
      await tester.tap(find.byKey(const ValueKey('welcome-book-service')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<RoleSignInScreen>(find.byType(RoleSignInScreen)).role,
        UserRole.customer,
      );
      expect(find.text('Email'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('exit-customer-login')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('welcome-register-salon')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<RoleSignInScreen>(find.byType(RoleSignInScreen)).role,
        UserRole.owner,
      );
      expect(find.byType(CustomerHomeScreen), findsNothing);
      expect(find.textContaining('customer home'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(WelcomeScreen), findsOneWidget);
    },
  );

  testWidgets('returning customer opens discovery with no partner navigation', (
    tester,
  ) async {
    final state = AppState(restoreActiveRole: false);
    await customer(state);
    await launch(tester, state);
    expect(find.byType(CustomerHomeScreen), findsOneWidget);
    expect(find.byType(WelcomeScreen), findsNothing);
    final navigation = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navigation.destinations, hasLength(2));
    expect(find.text('Partner'), findsNothing);
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.byType(CustomerProfileScreen), findsOneWidget);
    expect(find.text('Register Salon'), findsNothing);
  });

  testWidgets('owner restoration waits then opens only the owner dashboard', (
    tester,
  ) async {
    final state = _RestoringState();
    await owner(state);
    // An indeterminate progress indicator deliberately never settles.
    await tester.pumpWidget(
      AppStateProvider(createAppState: () => state, child: const TrimtimeApp()),
    );
    expect(find.text('Opening SalonFe'), findsOneWidget);
    expect(find.byType(WelcomeScreen), findsNothing);
    expect(find.byType(CustomerHomeScreen), findsNothing);
    state.finishRestore();
    await tester.pumpAndSettle();
    expect(find.byType(SalonDashboardScreen), findsOneWidget);
    expect(find.text('The Style Studio'), findsOneWidget);
    expect(find.byType(CustomerHomeScreen), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets(
    'owner sign-in clears welcome history and logout returns to welcome',
    (tester) async {
      final state = AppState(restoreActiveRole: false);
      await owner(state);
      await state.signOutActiveUser();
      await launch(tester, state);
      await tester.tap(find.byKey(const ValueKey('welcome-register-salon')));
      await tester.pumpAndSettle();
      await submitOwnerEmail(tester, 'owner@example.com');
      expect(find.byType(SalonDashboardScreen), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);
      expect(
        Navigator.of(
          tester.element(find.byType(SalonDashboardScreen)),
        ).canPop(),
        isFalse,
      );
      await tester.tap(find.byTooltip('Account menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
      await tester.pumpAndSettle();
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(CustomerHomeScreen), findsNothing);
    },
  );

  testWidgets(
    'new owner finishes referral onboarding before salon registration',
    (tester) async {
      final state = AppState(restoreActiveRole: false);
      await launch(tester, state);
      await tester.tap(find.byKey(const ValueKey('welcome-register-salon')));
      await tester.pumpAndSettle();
      await submitOwnerEmail(tester, 'new-owner@example.com');
      expect(find.text('Do you have a referral code?'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('skip-referral-code')).last);
      await tester.pumpAndSettle();
      expect(find.byType(SalonProfileSetupScreen), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);
      expect(find.byType(CustomerHomeScreen), findsNothing);
      expect(
        Navigator.of(
          tester.element(find.byType(SalonProfileSetupScreen)),
        ).canPop(),
        isFalse,
      );
    },
  );

  testWidgets('customer sign-in and logout never expose partner routes', (
    tester,
  ) async {
    final state = AppState(restoreActiveRole: false);
    await customer(state);
    await state.signOutActiveUser();
    await launch(tester, state);
    await tester.tap(find.byKey(const ValueKey('welcome-book-service')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('phone-login-field')),
      '9876500000',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('phone-otp-field')),
      '123456',
    );
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Verify and sign in'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Verify and sign in'));
    await tester.pumpAndSettle();
    expect(find.byType(CustomerHomeScreen), findsOneWidget);
    expect(find.byType(RoleSignInScreen), findsNothing);
    expect(
      Navigator.of(tester.element(find.byType(CustomerHomeScreen))).canPop(),
      isFalse,
    );
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    final logout = find.byKey(const ValueKey('customer-profile-logout'));
    await tester.scrollUntilVisible(
      logout,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(logout);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(CustomerProfileScreen), findsNothing);
  });

  testWidgets(
    'legacy partner entry redirects a customer to their own account',
    (tester) async {
      final state = AppState(restoreActiveRole: false);
      await customer(state);
      await tester.pumpWidget(
        AppStateProvider(
          createAppState: () => state,
          child: const MaterialApp(home: PartnerHubScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CustomerHomeScreen), findsOneWidget);
      expect(find.byType(RoleSignInScreen), findsNothing);
      expect(find.text('Register Salon'), findsNothing);
    },
  );

  testWidgets('welcome remains usable on a small display with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.4)),
          child: child!,
        ),
        home: const WelcomeScreen(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(
      find.byKey(const ValueKey('welcome-register-salon')),
    );
    await tester.tap(find.byKey(const ValueKey('welcome-register-salon')));
    await tester.pumpAndSettle();
    expect(find.byType(RoleSignInScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _RestoringState extends AppState {
  _RestoringState() : super(restoreActiveRole: false);
  bool restoring = true;
  @override
  bool get isRestoringSession => restoring;
  void finishRestore() {
    restoring = false;
    notifyListeners();
  }
}
