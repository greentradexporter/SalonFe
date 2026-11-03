import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nashik_salon_booking/screens/salon/salon_dashboard_screen.dart';
import 'package:nashik_salon_booking/screens/salon/salon_profile_setup_screen.dart';
import 'package:nashik_salon_booking/state/app_state.dart';
import 'package:nashik_salon_booking/state/app_state_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// An owner session whose salon list never arrives. On a real device this is
/// a Firestore listener that cannot connect: it emits neither a snapshot nor
/// an error, so the dashboard used to sit on a spinner that only killing the
/// app could clear.
class _StalledSalonLoadAppState extends AppState {
  bool failed = false;
  bool ownerSalonKnown = false;
  int retries = 0;

  @override
  bool get salonsLoaded => false;

  @override
  bool get ownerSalonResolved => ownerSalonKnown;

  @override
  bool get salonsLoadFailed => failed;

  @override
  void retrySalonsLoad() {
    retries++;
    notifyListeners();
  }
}

Future<_StalledSalonLoadAppState> _ownerSession() async {
  final state = _StalledSalonLoadAppState();
  await state.loginOwnerWithEmail(name: 'Owner', email: 'owner@example.com');
  if (state.referralOnboardingRequired) {
    await state.completeReferralOnboarding();
  }
  return state;
}

Future<void> _pumpDashboard(
  WidgetTester tester,
  _StalledSalonLoadAppState state,
) {
  return tester.pumpWidget(
    AppStateProvider(
      createAppState: () => state,
      child: const MaterialApp(home: SalonDashboardScreen()),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('a salon list that never arrives still spins', (tester) async {
    final state = await _ownerSession();
    await _pumpDashboard(tester, state);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const ValueKey('retry-salon-load')), findsNothing);
  });

  testWidgets('a stalled load becomes a retry, not an endless spinner', (
    tester,
  ) async {
    final state = await _ownerSession();
    await _pumpDashboard(tester, state);
    await tester.pump();

    state.failed = true;
    state.notifyListeners();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Could not load your salon'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('retry-salon-load')));
    await tester.pump();
    expect(state.retries, 1);
  });

  testWidgets('a failed load never falls through to registration', (
    tester,
  ) async {
    // The registration screen replaces the dashboard and cannot be popped, so
    // showing it to an owner who does have a salon traps them there.
    final state = await _ownerSession();
    state.failed = true;
    await _pumpDashboard(tester, state);
    await tester.pump();

    expect(find.byType(SalonProfileSetupScreen), findsNothing);
  });

  testWidgets('the owner salon lookup alone releases the dashboard', (
    tester,
  ) async {
    // The whole-collection listener is the thing that may never deliver. A
    // direct read of this owner's own salon must be enough on its own, or
    // logging in stays hostage to that listener — which is what made a stuck
    // login "fix itself" only after a force quit and reopen.
    final state = await _ownerSession();
    await _pumpDashboard(tester, state);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    state.ownerSalonKnown = true;
    state.notifyListeners();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
