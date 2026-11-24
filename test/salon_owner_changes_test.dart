import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nashik_salon_booking/models/app_models.dart';
import 'package:nashik_salon_booking/screens/salon/salon_dashboard_screen.dart';
import 'package:nashik_salon_booking/screens/salon/salon_profile_setup_screen.dart';
import 'package:nashik_salon_booking/screens/salon/salon_balance_screen.dart';
import 'package:nashik_salon_booking/state/app_state.dart';
import 'package:nashik_salon_booking/state/app_state_scope.dart';
import 'package:nashik_salon_booking/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

Future<void> signInOwner(AppState state) async {
  await state.loginOwnerWithPhone(
    phone: '9000000333',
    verificationId: 'test-verification',
    smsCode: '123456',
  );
  if (state.referralOnboardingRequired) {
    await state.completeReferralOnboarding();
  }
}

Future<void> saveShop(
  AppState state, {
  List<String> photos = const [],
  List<Barber> barbers = const [],
}) => state.updateOwnerSalon(
  name: 'Style Studio',
  ownerName: 'Owner',
  address: 'Nashik',
  phone: '9000000333',
  openTime: '9:00 AM',
  closeTime: '8:00 PM',
  photoUrls: photos,
  initialBarbers: barbers,
  strictShop: true,
);

class _HistoryState extends AppState {
  @override
  List<Booking> bookingsForSalon(String salonId) => [
    Booking(
      id: 'history',
      salonId: salonId,
      serviceId: 'haircut',
      barberId: '',
      customerName: 'Previous customer',
      customerPhone: '',
      serviceName: 'Haircut',
      start: DateTime.now().subtract(const Duration(days: 1)),
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      status: BookingStatus.completed,
    ),
  ];
}

class _BalanceRetryState extends AppState {
  int attempts = 0;
  @override
  Future<SalonBalanceSummary> loadSalonBalance(String salonId) async {
    if (++attempts == 1) throw StateError('Offline');
    return const SalonBalanceSummary(deposit: 1000, discount: 100, earning: 50);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  test(
    'phone-only owner saves photo and named barber together without an email',
    () async {
      final state = AppState(restoreActiveRole: false);
      await signInOwner(state);
      final barber = state.createOwnerBarberDraft('Sam');
      expect(state.barbersForSalon(state.ownerSalonId), isEmpty);
      await expectLater(saveShop(state, barbers: [barber]), throwsStateError);
      expect(state.ownerSalonOrNull, isNull);
      await expectLater(
        saveShop(state, photos: ['https://example.com/photo.jpg']),
        throwsStateError,
      );
      expect(state.ownerSalonOrNull, isNull);
      expect(state.barbersForSalon(state.ownerSalonId), isEmpty);
      await saveShop(
        state,
        photos: ['https://example.com/photo.jpg'],
        barbers: [barber],
      );
      expect(state.ownerSalon.email, isEmpty);
      expect(state.ownerSalon.photoUrls, ['https://example.com/photo.jpg']);
      expect(state.barbersForSalon(state.ownerSalonId).single.name, 'Sam');
      await expectLater(saveShop(state, photos: []), throwsStateError);
      expect(state.ownerSalon.photoUrls, isNotEmpty);
      await saveShop(state, photos: ['https://example.com/new.jpg']);
      expect(state.ownerSalon.photoUrls.single, 'https://example.com/new.jpg');
      expect(state.barbersForSalon(state.ownerSalonId), hasLength(1));
    },
  );
  testWidgets(
    'Previous bookings stay hidden until opened; Home CTA opens Bookings',
    (tester) async {
      final state = _HistoryState();
      await signInOwner(state);
      await saveShop(
        state,
        photos: ['https://example.com/photo.jpg'],
        barbers: [state.createOwnerBarberDraft('Sam')],
      );
      await tester.pumpWidget(
        AppStateProvider(
          createAppState: () => state,
          child: MaterialApp(
            theme: AppTheme.build(),
            home: const SalonDashboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('owner-view-bookings')),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.byKey(const ValueKey('owner-view-bookings')));
      await tester.pumpAndSettle();
      expect(find.text('Needs Action'), findsOneWidget);
      expect(find.text('Live Bookings'), findsOneWidget);
      expect(find.text('Previous customer'), findsNothing);
      await tester.scrollUntilVisible(
        find.textContaining('Previous bookings'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.textContaining('Previous bookings'));
      await tester.pumpAndSettle();
      expect(find.text('Previous customer'), findsOneWidget);
      await tester.tap(find.textContaining('Previous bookings'));
      await tester.pumpAndSettle();
      expect(find.text('Previous customer'), findsNothing);
    },
  );
  testWidgets(
    'Shop is editable inside dashboard with no email or header pencil',
    (tester) async {
      final state = AppState(restoreActiveRole: false);
      await signInOwner(state);
      await saveShop(
        state,
        photos: ['https://example.com/photo.jpg'],
        barbers: [state.createOwnerBarberDraft('Sam')],
      );
      await tester.pumpWidget(
        AppStateProvider(
          createAppState: () => state,
          child: MaterialApp(
            theme: AppTheme.build(),
            home: const SalonDashboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shop'));
      await tester.pumpAndSettle();
      expect(find.byType(SalonProfileSetupScreen), findsOneWidget);
      expect(find.text('Shop details'), findsOneWidget);
      expect(find.text('Owner email address'), findsNothing);
      expect(find.byTooltip('Edit salon'), findsNothing);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('salon-registration-name-field')),
            )
            .enabled,
        isNot(false),
      );
    },
  );
  testWidgets('Balance offers retry rather than showing false zero values', (
    tester,
  ) async {
    final state = _BalanceRetryState();
    await tester.pumpWidget(
      AppStateProvider(
        createAppState: () => state,
        child: MaterialApp(
          theme: AppTheme.build(),
          home: const SalonBalanceScreen(salonId: 'salon'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not load balance'), findsOneWidget);
    expect(find.text('₹0'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('₹1000'), findsOneWidget);
    expect(find.text('₹850'), findsOneWidget);
    expect(find.text('₹100'), findsOneWidget);
    expect(find.text('₹50'), findsOneWidget);
  });
}
