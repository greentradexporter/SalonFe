import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nashik_salon_booking/models/app_models.dart';
import 'package:nashik_salon_booking/models/service_catalog.dart';
import 'package:nashik_salon_booking/state/app_state.dart';

void main() {
  test('the saved copy rebuilds exactly the salon it was made from', () {
    // The salon dashboard opens from this copy before Firestore answers, so
    // anything it loses or changes is what the owner sees at startup.
    final services = [
      for (final service in canonicalSalonServices(const []))
        service.name == 'Haircut Men'
            ? service.copyWith(
                price: 180,
                durationMinutes: 40,
                instantBookingEnabled: false,
              )
            : service.name == 'Facial'
            ? service.copyWith(isAvailable: false)
            : service,
    ];
    final salon = Salon(
      id: 'salon-owner-1',
      name: 'New good luck',
      ownerName: 'Owner',
      address: 'Chembur camp',
      directionsUrl: 'https://maps.example/salon',
      phone: '+919000000000',
      email: 'owner@example.com',
      logoUrl: 'https://cdn.example/logo.png',
      photoUrls: const [
        'https://cdn.example/1.jpg',
        'https://cdn.example/2.jpg',
      ],
      distanceLabel: '1.2 km',
      rating: 4.8,
      reviewCount: 8,
      openTime: '9:30 AM',
      closeTime: '10:00 PM',
      isOpen: true,
      instantBookingsEnabled: false,
      instantBookingsPausedDate: '2026-10-30',
      approvalStatus: 'pending',
      services: services,
    );

    // Through JSON, as it is stored on the phone.
    final stored = jsonEncode(ownerSalonCopyData(salon));
    final restored = ownerSalonFromCopy(
      Map<String, dynamic>.from(jsonDecode(stored) as Map),
    );

    expect(restored, isNotNull);
    expect(jsonEncode(ownerSalonCopyData(restored!)), stored);
    expect(restored.id, 'salon-owner-1');
    expect(restored.isOpen, isTrue);
    expect(restored.instantBookingsEnabled, isFalse);
    expect(restored.approvalStatus, 'pending');
    final haircut = restored.services.firstWhere(
      (service) => service.name == 'Haircut Men',
    );
    expect(haircut.price, 180);
    expect(haircut.durationMinutes, 40);
    expect(haircut.instantBookingEnabled, isFalse);
    expect(
      restored.services.firstWhere((s) => s.name == 'Facial').isAvailable,
      isFalse,
    );
  });

  test('a copy without an id is never used', () {
    expect(ownerSalonFromCopy(const {'name': 'Salon'}), isNull);
    expect(ownerSalonFromCopy(const {'id': '  ', 'name': 'Salon'}), isNull);
  });

  test('the dashboard no longer waits on Firestore to open', () {
    final appState = File('lib/state/app_state.dart').readAsStringSync();
    // Restored before the restore screen lifts, for owners only.
    expect(
      RegExp(
        r'if \(localRole == UserRole\.owner\) \{\s*(//[^\n]*\n\s*)*'
        r'await _restoreOwnerSalonCopy\(user\.uid\);',
      ).hasMatch(appState),
      isTrue,
    );
    // Only the server may drop the owner's salon; a cached list may not.
    expect(appState, contains('final keptOwnerSalon = fromServer ? null'));
    // An empty cached list is not an answer, or the owner is sent to
    // registration while their salon is still on its way.
    expect(appState, contains('if (fromServer || parsed.isNotEmpty) {'));
    // A resume restarts only a failed load, never one still in progress.
    expect(appState, contains('if (_salonsLoadFailed && !_salonsLoaded) {'));
    // Signing out leaves nothing for the next person on the phone.
    expect(appState, contains('if (uid != null) _forgetOwnerSalonCopy(uid);'));

    final bootstrap = File(
      'lib/services/firebase_bootstrap.dart',
    ).readAsStringSync();
    // The one-time clear is only for phones carrying a backlog.
    expect(bootstrap, contains('firestoreBacklogDatabaseBytes'));
    expect(bootstrap, contains('needsClear: () async =>'));
  });
}
