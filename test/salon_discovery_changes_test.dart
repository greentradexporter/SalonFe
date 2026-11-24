import 'package:nashik_salon_booking/models/app_models.dart';
import 'package:nashik_salon_booking/models/service_catalog.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nashik_salon_booking/main.dart';
import 'package:nashik_salon_booking/screens/customer/customer_home_screen.dart';
import 'package:nashik_salon_booking/screens/customer/salon_detail_screen.dart';
import 'package:nashik_salon_booking/screens/entry/role_sign_in_screen.dart';
import 'package:nashik_salon_booking/screens/legal/legal_screen.dart';
import 'package:nashik_salon_booking/services/referral_skip_store.dart';
import 'package:nashik_salon_booking/services/salon_link_service.dart';
import 'package:nashik_salon_booking/state/app_state.dart';
import 'package:nashik_salon_booking/state/app_state_scope.dart';
import 'package:nashik_salon_booking/widgets/service_illustration.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _ApprovedFixtureState extends AppState {
  _ApprovedFixtureState() : super(restoreActiveRole: false);
  @override
  Salon? getSalon(String salonId) =>
      super.getSalon(salonId)?.copyWith(approvalStatus: 'approved');
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SalonLinkService.pendingSalonId.value = null;
  });
  test(
    'offline no-referral choice persists separately per account until acknowledged',
    () async {
      await ReferralSkipStore.skip('customer-A');
      expect(await ReferralSkipStore.wasSkipped('customer-A'), isTrue);
      expect(await ReferralSkipStore.needsSync('customer-A'), isTrue);
      expect(await ReferralSkipStore.wasSkipped('customer-B'), isFalse);
      await ReferralSkipStore.acknowledge('customer-A');
      expect(await ReferralSkipStore.needsSync('customer-A'), isFalse);
      expect(await ReferralSkipStore.wasSkipped('customer-A'), isTrue);
    },
  );
  test('salon links validate host and ID and round trip safely', () {
    expect(
      SalonLinkService.salonIdFromUri(SalonLinkService.linkFor('salon-123')),
      'salon-123',
    );
    expect(
      SalonLinkService.salonIdFromUri(Uri.parse('salonfe://salon/salon-123')),
      'salon-123',
    );
    for (final url in [
      'https://evil.example/s/salon-123',
      'https://trimtime-46539.web.app/s/%2Fusers',
      'https://trimtime-46539.web.app/r/ABC123',
      'http://trimtime-46539.web.app/s/salon-123',
    ]) {
      expect(SalonLinkService.salonIdFromUri(Uri.parse(url)), isNull);
    }
  });
  test('facial, spa and makeup have distinct relevant art', () {
    expect(serviceArtFor('Facial'), ServiceArt.facial);
    expect(serviceArtFor('Hair Spa'), ServiceArt.spa);
    expect(serviceArtFor('Bridal Makeup'), ServiceArt.makeup);
    expect(serviceArtFor('Pedicure'), ServiceArt.pedicure);
    expect(serviceArtFor('Hair Wash'), ServiceArt.wash);
    final assets = [
      'Facial',
      'Spa',
      'Bridal Makeup',
    ].map((name) => serviceIconAssetForService(name)).toSet();
    expect(assets, hasLength(3));
    for (final asset in assets) {
      expect(File(asset).existsSync(), isTrue, reason: asset);
    }
  });
  testWidgets(
    'customer skips login to browse and a shared link opens the specific salon',
    (tester) async {
      final state = _ApprovedFixtureState();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        AppStateProvider(
          createAppState: () => state,
          child: const TrimtimeApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('welcome-book-service')));
      await tester.pumpAndSettle();
      expect(find.byType(RoleSignInScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('skip-customer-login')));
      await tester.pumpAndSettle();
      expect(find.byType(CustomerHomeScreen), findsOneWidget);
      expect(state.hasActiveCustomerSession, isFalse);
      await state.loginOwnerWithPhone(
        phone: '9000000333',
        verificationId: 'test',
        smsCode: '123456',
      );
      await state.completeReferralOnboarding();
      await state.updateOwnerSalon(
        name: 'Shared Studio',
        email: 'owner@example.com',
        ownerName: 'Owner',
        address: 'Nashik',
        phone: '9000000333',
        openTime: '9:00 AM',
        closeTime: '8:00 PM',
      );
      final salon = state.ownerSalon;
      await state.signOutActiveUser();
      state.browseAsGuest();
      await SalonLinkService.accept(SalonLinkService.linkFor(salon.id));
      await tester.pumpAndSettle();
      expect(find.byType(SalonDetailScreen), findsOneWidget);
      expect(
        tester
            .widget<SalonDetailScreen>(find.byType(SalonDetailScreen))
            .salonId,
        salon.id,
      );
      expect(find.byKey(ValueKey('share-salon-${salon.id}')), findsOneWidget);
      expect(state.hasActiveCustomerSession, isFalse);
    },
  );
  testWidgets('salon links never open the customer app for a signed-in owner', (
    tester,
  ) async {
    final state = _ApprovedFixtureState();
    await state.loginOwnerWithPhone(
      phone: '9000000333',
      verificationId: 'test',
      smsCode: '123456',
    );
    await state.completeReferralOnboarding();
    await SalonLinkService.accept(SalonLinkService.linkFor(state.ownerSalonId));
    await tester.pumpWidget(
      AppStateProvider(createAppState: () => state, child: const TrimtimeApp()),
    );
    await tester.pumpAndSettle();
    expect(state.hasActiveOwnerSession, isTrue);
    expect(find.byType(CustomerHomeScreen), findsNothing);
    expect(find.byType(SalonDetailScreen), findsNothing);
    expect(
      find.text('Open salon links from a customer account.'),
      findsOneWidget,
    );
  });
  test(
    'weekly closed days remove slots and disable instant bookings without changing owner preference',
    () async {
      final state = _ApprovedFixtureState();
      await state.loginOwnerWithPhone(
        phone: '9000000333',
        verificationId: 'test',
        smsCode: '123456',
      );
      if (state.referralOnboardingRequired) {
        await state.completeReferralOnboarding();
      }
      await state.addOwnerService(
        name: 'Haircut',
        category: 'Haircut',
        price: 200,
        durationMinutes: 30,
      );
      final barber = state.createOwnerBarberDraft('Sam');
      await state.updateOwnerSalon(
        name: 'Studio',
        ownerName: 'Owner',
        address: 'Nashik',
        phone: '9000000333',
        openTime: '12:00 AM',
        closeTime: '11:59 PM',
        strictShop: true,
        photoUrls: ['https://example.com/shop.jpg'],
        initialBarbers: [barber],
        closedWeekdays: [1, 2, 3, 4, 5, 6, 7],
      );
      final salon = state.ownerSalon;
      expect(state.isInstantBookingEnabledForSalon(salon), isFalse);
      expect(state.isSalonCurrentlyOpenByClock(salon), isFalse);
      expect(state.slotsForService(salon.id, salon.services.first.id), isEmpty);
    },
  );
  testWidgets(
    'policy is readable offline with phone contact and no personal name',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: const LegalScreen(document: LegalDocument.privacy)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('+91 89996 08278'), findsWidgets);
      expect(find.textContaining('Mayur'), findsNothing);
      expect(find.textContaining('greentradexporter@gmail.com'), findsNothing);
    },
  );
  testWidgets('service artwork preview renders without errors', (tester) async {
    if (const bool.fromEnvironment('CAPTURE_PREVIEW')) {
      final directory = Platform.environment['SALONFE_PREVIEW_FONT_DIRECTORY'];
      if (directory != null) {
        for (final family in ['Inter', 'Ahem', 'Roboto']) {
          await (FontLoader(family)..addFont(
                Future.value(
                  ByteData.sublistView(
                    File('$directory/Roboto-Regular.ttf').readAsBytesSync(),
                  ),
                ),
              ))
              .load();
        }
      }
    }
    tester.view.physicalSize = const Size(800, 880);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: Scaffold(
            backgroundColor: Colors.white,
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: GridView.count(
                crossAxisCount: 4,
                childAspectRatio: 1,
                children: [
                  for (final label in [
                    'Haircut',
                    'Beard',
                    'Facial',
                    'Spa',
                    'Makeup',
                    'Manicure',
                    'Pedicure',
                    'Threading',
                    'Waxing',
                    'Hair Wash',
                    'Hair Color',
                    'Massage',
                  ])
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ServiceIllustration(category: label, size: 88),
                        const SizedBox(height: 12),
                        Text(label),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('CAPTURE_PREVIEW')) {
      await tester.runAsync(() async {
        for (final image in tester.widgetList<Image>(find.byType(Image))) {
          await precacheImage(image.image, key.currentContext!);
        }
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('output/salon-discovery').create(recursive: true);
        await File(
          'output/salon-discovery/service-art.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
      });
    }
  });
}
