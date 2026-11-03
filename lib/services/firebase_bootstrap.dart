import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'owner_alert_readiness.dart';

const firebaseFunctionsRegion = 'asia-south1';

/// Set once this install's local Firestore data has been cleared. Versioned so
/// a future clear can run again without touching anything else.
const firestoreCacheResetPreferenceKey = 'pritze.firestoreCacheReset.v1';

/// Above this, Firestore's database on a phone is carrying saved-up writes
/// from the old loop. A healthy one is a few megabytes: the salons, the
/// owner's bookings and the profile.
const firestoreBacklogDatabaseBytes = 5 * 1024 * 1024;

/// Clears this phone's local Firestore data, once per install, and only on a
/// phone that needs it.
///
/// Builds before 54 rewrote the owner's profile in a loop, and while the phone
/// had no usable connection - weak signal, or background data cut by the
/// battery manager - those writes were saved on the phone instead, often
/// thousands of them. Updating does not remove them: Firestore uploads every
/// saved write first, re-reading all the remaining ones for each, so the
/// upload takes hours and holds up every other request, including loading the
/// salon. That is the "Could not load your salon" seen on some phones. The
/// saved writes are only stale token registrations, which the app writes
/// again after startup, and the cache refills from the server.
///
/// Clearing has a cost, though: the next start has nothing saved and must
/// wait for the server for everything. Build 56 cleared every phone, and the
/// first open after updating then hit the salon dashboard's time limit on
/// slower phones. So [needsClear] decides; a phone without a backlog keeps its
/// data. Answered once either way, since no current build can build a backlog.
///
/// Must run before anything touches Firestore. It fails if Firestore has
/// already started in this process, which can only happen when the process
/// outlived an earlier app session; it is then retried on the next launch.
Future<bool> resetFirestoreCacheOnce({
  required Future<SharedPreferences> Function() preferences,
  required Future<void> Function() clearPersistence,
  Future<bool> Function()? needsClear,
  Duration timeout = const Duration(seconds: 10),
}) async {
  try {
    final store = await preferences();
    if (store.getBool(firestoreCacheResetPreferenceKey) ?? false) return false;
    if (needsClear != null && !await needsClear()) {
      await store.setBool(firestoreCacheResetPreferenceKey, true);
      return false;
    }
    await clearPersistence().timeout(timeout);
    await store.setBool(firestoreCacheResetPreferenceKey, true);
    return true;
  } catch (error) {
    if (kDebugMode) debugPrint('Firestore cache reset deferred: $error');
    return false;
  }
}

class FirebaseBootstrap {
  final bool enabled;
  final FirebaseFirestore? firestore;
  final FirebaseFunctions? functions;
  final FirebaseAuth? auth;
  final FirebaseMessaging? messaging;
  final FirebaseStorage? storage;
  final Object? error;

  const FirebaseBootstrap._({
    required this.enabled,
    this.firestore,
    this.functions,
    this.auth,
    this.messaging,
    this.storage,
    this.error,
  });

  static Future<FirebaseBootstrap> initialize() async {
    try {
      await Firebase.initializeApp();
    } catch (error) {
      return FirebaseBootstrap._(enabled: false, error: error);
    }

    // Before the first Firestore use, which follows as soon as this returns.
    if (!kIsWeb) {
      await resetFirestoreCacheOnce(
        preferences: SharedPreferences.getInstance,
        clearPersistence: FirebaseFirestore.instance.clearPersistence,
        // Unknown size (not Android, or no answer) means no clear.
        needsClear: () async =>
            (await OwnerAlertDeviceSettings.firestoreDatabaseBytes() ?? 0) >
            firestoreBacklogDatabaseBytes,
      );
    }

    // App Check and the debug-only phone-auth preference are platform setup,
    // not prerequisites for drawing the first usable frame. Start them now
    // and let them finish while the user sees the locally restored home.
    unawaited(_configurePlatformServices());

    return FirebaseBootstrap._(
      enabled: true,
      firestore: FirebaseFirestore.instance,
      functions: FirebaseFunctions.instanceFor(region: firebaseFunctionsRegion),
      auth: FirebaseAuth.instance,
      messaging: FirebaseMessaging.instance,
      storage: FirebaseStorage.instance,
    );
  }

  static Future<void> _configurePlatformServices() async {
    try {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: kReleaseMode
            ? const AndroidPlayIntegrityProvider()
            : const AndroidDebugProvider(),
        providerApple: kReleaseMode
            ? const AppleAppAttestWithDeviceCheckFallbackProvider()
            : const AppleDebugProvider(),
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Firebase App Check activation failed: $error');
      }
    }

    if (kDebugMode && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await FirebaseAuth.instance.setSettings(forceRecaptchaFlow: true);
      } catch (error) {
        debugPrint('Firebase Auth debug reCAPTCHA fallback failed: $error');
      }
    }
  }
}
