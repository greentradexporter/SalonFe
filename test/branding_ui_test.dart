import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nashik_salon_booking/screens/customer/customer_home_screen.dart';
import 'package:nashik_salon_booking/screens/entry/welcome_screen.dart';
import 'package:nashik_salon_booking/screens/salon/salon_dashboard_screen.dart';
import 'package:nashik_salon_booking/state/app_state.dart';
import 'package:nashik_salon_booking/models/app_models.dart';
import 'package:nashik_salon_booking/state/app_state_scope.dart';
import 'package:nashik_salon_booking/theme/app_theme.dart';
import 'package:nashik_salon_booking/widgets/brand_header.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('branded narrow headers keep back and menu actions usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var actionCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.4)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: SalonFeAppBar(
                      title: const Text('A salon with a long display name'),
                      actions: [
                        IconButton(
                          tooltip: 'Page actions',
                          onPressed: () => actionCount++,
                          icon: const Icon(Icons.more_vert),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(BrandWordmark), findsOneWidget);
    await tester.tap(find.byTooltip('Page actions'));
    expect(actionCount, 1);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
  });

  for (final preview in [
    'welcome',
    'owner-dashboard',
    'owner-bookings',
    'owner-shop',
    'owner-balance',
    'customer-home',
    'owner-login',
  ]) {
    testWidgets(
      '$preview renders the shared brand without overflow',
      (tester) async {
        final tabletAssets =
            Platform.environment['SALONFE_TABLET_ASSETS'] == '1';
        final appleDevice = Platform.environment['SALONFE_APPLE_ASSETS'];
        tester.view.physicalSize = appleDevice == 'iphone'
            ? const Size(440, 956)
            : appleDevice == 'iphone-medium'
            ? const Size(402, 874)
            : appleDevice == 'ipad'
            ? const Size(1032, 1376)
            : tabletAssets
            ? const Size(1080, 1920)
            : Platform.environment['SALONFE_PLAY_ASSETS'] == '1'
            ? const Size(432, 768)
            : const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final capture = Platform.environment['SALONFE_CAPTURE_PREVIEWS'] == '1';
        if (capture) {
          final directory =
              Platform.environment['SALONFE_PREVIEW_FONT_DIRECTORY'];
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
            await (FontLoader('MaterialIcons')..addFont(
                  Future.value(
                    ByteData.sublistView(
                      File(
                        '$directory/MaterialIcons-Regular.otf',
                      ).readAsBytesSync(),
                    ),
                  ),
                ))
                .load();
          }
        }
        final state = _OwnerPreviewState();
        if ((preview.startsWith('owner-') && preview != 'owner-login') ||
            preview == 'customer-home') {
          await state.loginOwnerWithEmail(
            name: 'Salon owner',
            email: 'preview@example.com',
          );
          if (state.referralOnboardingRequired) {
            await state.completeReferralOnboarding();
          }
          await state.updateOwnerSalon(
            name: 'The Style Studio',
            ownerName: 'Salon owner',
            address: 'College Road, Nashik',
            phone: '9000000101',
            openTime: '12:00 AM',
            closeTime: '11:59 PM',
          );
          await state.addOwnerService(
            name: 'Haircut Men',
            category: 'Hair',
            price: 250,
            durationMinutes: 30,
          );
        }
        if ((preview.startsWith('owner-') && preview != 'owner-login') ||
            preview == 'customer-home') {
          await state.addOwnerBarber(
            name: 'Ritesh',
            speciality: 'Haircut specialist',
            experienceYears: 3,
            resumeSummary: '',
            serviceIds: state.ownerSalon.services
                .map((service) => service.id)
                .toList(),
          );
        }
        if (preview == 'customer-home') await state.signOutActiveUser();
        final baseTheme = AppTheme.build();
        // Tests use Ahem where native Android/iOS resolve a platform font. Give
        // those standalone component styles the same loaded preview face.
        ButtonStyle? previewStyle(ButtonStyle? style) => style?.copyWith(
          textStyle: WidgetStatePropertyAll(
            style.textStyle?.resolve({})?.copyWith(fontFamily: 'Inter'),
          ),
        );
        final previewTheme = capture
            ? baseTheme.copyWith(
                appBarTheme: baseTheme.appBarTheme.copyWith(
                  titleTextStyle: baseTheme.appBarTheme.titleTextStyle
                      ?.copyWith(fontFamily: 'Inter'),
                ),
                filledButtonTheme: FilledButtonThemeData(
                  style: previewStyle(baseTheme.filledButtonTheme.style),
                ),
                outlinedButtonTheme: OutlinedButtonThemeData(
                  style: previewStyle(baseTheme.outlinedButtonTheme.style),
                ),
                textButtonTheme: TextButtonThemeData(
                  style: previewStyle(baseTheme.textButtonTheme.style),
                ),
                segmentedButtonTheme: SegmentedButtonThemeData(
                  style: previewStyle(baseTheme.segmentedButtonTheme.style),
                ),
              )
            : baseTheme;
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          AppStateProvider(
            createAppState: () => state,
            child: RepaintBoundary(
              key: boundaryKey,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: previewTheme,
                home: preview == 'welcome'
                    ? const WelcomeScreen()
                    : preview == 'customer-home'
                    ? const CustomerHomeScreen()
                    : const SalonDashboardScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (preview == 'owner-bookings' || preview == 'owner-shop') {
          await tester.tap(
            find.text(preview == 'owner-bookings' ? 'Bookings' : 'Shop'),
          );
          await tester.pumpAndSettle();
        }
        if (preview == 'owner-balance') {
          await tester.tap(find.byTooltip('Account menu'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Balance'));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        expect(find.byType(BrandWordmark), findsOneWidget);
        if (capture) {
          final logo = find.descendant(
            of: find.byType(BrandWordmark),
            matching: find.byType(RawImage),
          );
          for (var attempt = 0; attempt < 20; attempt++) {
            await tester.runAsync(() async {
              await Future<void>.delayed(const Duration(milliseconds: 50));
            });
            await tester.pump();
            if (logo.evaluate().isNotEmpty &&
                tester.widget<RawImage>(logo).image != null) {
              break;
            }
          }
          expect(tester.widget<RawImage>(logo).image, isNotNull);
          await tester.pumpAndSettle();
          if (preview == 'owner-balance') {
            // Ensure a newly pushed route has painted its shared image asset.
            await tester.pump(const Duration(milliseconds: 100));
          }
          final customOutput =
              Platform.environment['SALONFE_PREVIEW_OUTPUT_DIRECTORY'];
          if (customOutput != null) {
            await tester.runAsync(() async {
              final boundary =
                  boundaryKey.currentContext!.findRenderObject()
                      as RenderRepaintBoundary;
              final image = await boundary.toImage(pixelRatio: appleDevice == 'ipad' ? 2 : 3);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                Directory('test').absolute.uri
                    .resolve('$customOutput/$appleDevice-$preview.png')
                    .toFilePath(),
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          } else {
            await expectLater(
              find.byKey(boundaryKey),
              matchesGoldenFile(
                appleDevice != null
                    ? '../output/apple-release/$appleDevice-$preview-source.png'
                    : tabletAssets
                    ? '../output/play-release/tablet-$preview.png'
                    : Platform.environment['SALONFE_PLAY_ASSETS'] == '1'
                    ? '../output/play-release/$preview.png'
                    : '../output/salonfe/$preview.png',
              ),
            );
          }
        }
      },
      variant: TargetPlatformVariant({
        Platform.environment['SALONFE_APPLE_ASSETS'] != null
            ? TargetPlatform.iOS
            : TargetPlatform.android,
      }),
    );
  }
}

class _OwnerPreviewState extends AppState {
  _OwnerPreviewState() : super(restoreActiveRole: false);
  @override
  List<Booking> bookingsForSalon(String salonId) {
    if (ownerSalonOrNull == null) return [];
    final service = ownerSalon.services.first;
    final barber = barbersForSalon(salonId).firstOrNull;
    final now = DateTime.now();
    return [
      for (final entry in [
        ('request', 'Rahul', BookingStatus.pending, 399),
        ('accepted', 'Amit', BookingStatus.confirmed, 199),
        ('progress', 'Priya', BookingStatus.inProgress, 799),
        ('complete', 'Sneha', BookingStatus.completed, 399),
      ])
        Booking(
          id: entry.$1,
          salonId: salonId,
          serviceId: service.id,
          barberId: barber?.id ?? '',
          customerName: entry.$2,
          customerPhone: '+919000000001',
          start: now,
          createdAt: now,
          status: entry.$3,
          serviceName: entry.$1 == 'progress'
              ? 'Hair Spa'
              : entry.$1 == 'accepted'
              ? 'Beard Trim'
              : 'Haircut',
          servicePrice: entry.$4,
          isInstant: true,
        ),
    ];
  }

  @override
  Future<SalonBalanceSummary> loadSalonBalance(String salonId) async =>
      const SalonBalanceSummary(deposit: 10000, discount: 1200, earning: 600);
}
