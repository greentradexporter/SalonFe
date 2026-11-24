import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nashik_salon_booking/models/app_models.dart';
import 'package:nashik_salon_booking/screens/customer/customer_home_screen.dart';
import 'package:nashik_salon_booking/state/app_state.dart';
import 'package:nashik_salon_booking/state/app_state_scope.dart';
import 'package:nashik_salon_booking/utils/salon_sorting.dart';
import 'package:nashik_salon_booking/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Salon salon(
  String id, {
  double? latitude,
  double? longitude,
  double rating = 4,
  int reviews = 5,
  String link = '',
}) => Salon(
  id: id,
  name: id,
  ownerName: '',
  address: '',
  directionsUrl: link,
  latitude: latitude,
  longitude: longitude,
  phone: '',
  logoUrl: '',
  distanceLabel: '',
  rating: rating,
  reviewCount: reviews,
  openTime: '12:00 AM',
  closeTime: '11:59 PM',
  isOpen: true,
  services: const [],
);

class _SortingState extends AppState {
  _SortingState() : super(restoreActiveRole: false);
  @override
  List<Salon> get discoverableSalons => [
    salon('Nearby Studio', latitude: 19.001, longitude: 72, rating: 4.1),
    salon('Top Rated Studio', latitude: 19.1, longitude: 72, rating: 4.9),
  ];
  @override
  bool isSalonBookable(String salonId) => true;
  @override
  bool isSalonCurrentlyOpen(String salonId, {DateTime? now}) => true;
}

void main() {
  test('nearest orders by distance and keeps missing or invalid pins last', () {
    final salons = [
      salon('unknown', rating: 5),
      salon('far', latitude: 19.1, longitude: 72, rating: 5),
      salon('near', latitude: 19.001, longitude: 72, rating: 3),
      salon('invalid', latitude: 200, longitude: 72),
    ];
    final result = sortSalons(
      salons,
      sort: SalonSort.nearest,
      customer: (latitude: 19, longitude: 72),
      availabilityPriority: (_) => 0,
    );
    expect(result.map((s) => s.id), ['near', 'far', 'unknown', 'invalid']);
    expect(
      salonDistanceMeters(salons[2], (latitude: 19, longitude: 72)),
      closeTo(111.2, 1),
    );
  });
  test('highest rated uses review count as a tie breaker', () {
    final result = sortSalons(
      [
        salon('five', rating: 5, reviews: 2),
        salon('popular', rating: 5, reviews: 20),
        salon('four'),
      ],
      sort: SalonSort.highestRated,
      availabilityPriority: (_) => 0,
    );
    expect(result.map((s) => s.id), ['popular', 'five', 'four']);
  });
  test('recommended prioritizes relevant names and then available salons', () {
    final result = sortSalons(
      [salon('Closed', rating: 5), salon('Open', rating: 4)],
      sort: SalonSort.recommended,
      availabilityPriority: (s) => s.id == 'Open' ? 0 : 2,
    );
    expect(result.first.id, 'Open');
    final search = sortSalons(
      [salon('Other', rating: 5), salon('Studio', rating: 4)],
      sort: SalonSort.recommended,
      query: 'studio',
      availabilityPriority: (_) => 0,
    );
    expect(search.first.id, 'Studio');
  });
  test('nearest without customer location uses recommended order', () {
    final result = sortSalons(
      [salon('Closed', rating: 5), salon('Open')],
      sort: SalonSort.nearest,
      availabilityPriority: (s) => s.id == 'Open' ? 0 : 2,
    );
    expect(result.first.id, 'Open');
  });
  test(
    'map parsing uses actual destination pins, not a viewport or route origin',
    () {
      expect(
        salonCoordinates(
          salon('query', link: 'https://www.google.com/maps?q=19.05%2C72.90'),
        ),
        (latitude: 19.05, longitude: 72.9),
      );
      expect(
        salonCoordinates(
          salon(
            'pin',
            link:
                'https://www.google.com/maps/place/Studio/@18,70,15z/data=!3d19.05!4d72.90',
          ),
        ),
        (latitude: 19.05, longitude: 72.9),
      );
      expect(
        salonCoordinates(
          salon(
            'viewport',
            link: 'https://www.google.com/maps/place/Studio/@18,70,15z',
          ),
        ),
        isNull,
      );
      expect(
        salonCoordinates(salon('short', link: 'https://maps.app.goo.gl/abc')),
        isNull,
      );
      expect(
        salonCoordinates(salon('bad', link: 'https://evil.example/?q=19,72')),
        isNull,
      );
      expect(
        salonCoordinates(
          salon('invalid', link: 'https://www.google.com/maps?q=119,72'),
        ),
        isNull,
      );
      expect(
        salonCoordinates(
          salon('malformed', link: 'https://www.google.com/maps?q=%FF'),
        ),
        isNull,
      );
    },
  );
  test('salon coordinates survive local owner cache round trip', () {
    final original = salon('cached', latitude: 19.05, longitude: 72.9);
    final copy = ownerSalonFromCopy(
      Map<String, dynamic>.from(ownerSalonCopyData(original)),
    )!;
    expect(salonCoordinates(copy), salonCoordinates(original));
  });
  test('changing a maps link invalidates its old derived pin', () {
    final data = Map<String, dynamic>.from(
      ownerSalonCopyData(
        salon(
          'moved',
          latitude: 19,
          longitude: 72,
          link: 'https://maps.app.goo.gl/new',
        ),
      ),
    );
    data['mapPinSourceUrl'] = 'https://maps.app.goo.gl/old';
    expect(salonCoordinates(ownerSalonFromCopy(data)!), isNull);
  });
  testWidgets(
    'sort sheet applies highest rated and nearest with an existing location',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preview = Platform.environment['SALONFE_SORT_PREVIEW'];
      final fonts = Platform.environment['SALONFE_PREVIEW_FONT_DIRECTORY'];
      if (preview != null && fonts != null) {
        for (final family in ['Inter', 'Roboto', 'Ahem', 'MaterialIcons']) {
          final file = family == 'MaterialIcons'
              ? 'MaterialIcons-Regular.otf'
              : 'Roboto-Regular.ttf';
          await (FontLoader(family)..addFont(
                Future.value(
                  ByteData.sublistView(File('$fonts/$file').readAsBytesSync()),
                ),
              ))
              .load();
        }
      }
      final state = _SortingState();
      await state.setCustomerDiscoveryLocation(
        latitude: 19,
        longitude: 72,
        accuracyMeters: 100,
      );
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final capture = GlobalKey();
      await tester.pumpWidget(
        AppStateProvider(
          createAppState: () => state,
          child: RepaintBoundary(
            key: capture,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.build(),
              home: const CustomerHomeScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (preview != null) {
        await tester.runAsync(() async {
          for (final image in tester.widgetList<Image>(find.byType(Image))) {
            await precacheImage(image.image, capture.currentContext!);
          }
        });
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('salon-sort-button')));
      await tester.pumpAndSettle();
      expect(find.text('Sort salons'), findsOneWidget);
      expect(find.text('Recommended'), findsNWidgets(2));
      if (preview != null) {
        await tester.runAsync(() async {
          final boundary =
              capture.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File(preview).writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }
      await tester.tap(find.byKey(const ValueKey('salon-sort-highestRated')));
      await tester.pumpAndSettle();
      expect(find.text('Sort salons'), findsNothing);
      expect(find.text('Highest rated'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Top Rated Studio')).dy,
        lessThan(tester.getTopLeft(find.text('Nearby Studio')).dy),
      );
      await tester.tap(find.byKey(const ValueKey('salon-sort-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('salon-sort-nearest')));
      await tester.pumpAndSettle();
      expect(find.text('Nearest'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Nearby Studio')).dy,
        lessThan(tester.getTopLeft(find.text('Top Rated Studio')).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'nearest without permission falls back and keeps browsing available',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        AppStateProvider(
          createAppState: () => _SortingState(),
          child: const MaterialApp(home: CustomerHomeScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('salon-sort-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('salon-sort-nearest')));
      await tester.pumpAndSettle();
      expect(
        find.text('Allow location to sort by nearest. Showing Recommended.'),
        findsOneWidget,
      );
      expect(find.text('Sort'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
