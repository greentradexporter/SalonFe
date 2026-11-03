import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native notification resources and payload names stay aligned', () {
    final iosSound = File('ios/Runner/owner_booking_request.wav');
    final androidSound = File(
      'android/app/src/main/res/raw/owner_booking_request.wav',
    );
    expect(iosSound.existsSync(), isTrue);
    expect(androidSound.existsSync(), isTrue);
    _expectValidWaveFile(iosSound);
    _expectValidWaveFile(androidSound);

    // A scheduled booking gets its own tone so the owner can tell it from an
    // instant request by ear, but it rings once: no insistent flag, no
    // full-screen intent, no alarm stream.
    final scheduledSoundAndroid = File(
      'android/app/src/main/res/raw/scheduled_booking_request.wav',
    );
    final scheduledSoundIos = File('ios/Runner/scheduled_booking_request.wav');
    expect(scheduledSoundAndroid.existsSync(), isTrue);
    expect(scheduledSoundIos.existsSync(), isTrue);
    _expectShortWaveFile(scheduledSoundAndroid);
    final androidKeepRule = File(
      'android/app/src/main/res/raw/keep.xml',
    ).readAsStringSync();
    expect(androidKeepRule, contains('@raw/owner_booking_request'));
    expect(androidKeepRule, contains('@raw/scheduled_booking_request'));

    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    expect(project, contains('owner_booking_request.wav in Resources'));

    final appState = File('lib/state/app_state.dart').readAsStringSync();
    expect(
      appState,
      contains("Future<void> firebaseMessagingBackgroundHandler"),
    );
    expect(appState, contains("'ownerAlertV4Tokens'"));
    // The retired generation must still be cleared, or the server rings the
    // device twice: once per channel it is registered for.
    expect(appState, contains("'ownerAlertV3Tokens'"));
    // The owner-alert flag has exactly one owner. The app and the FCM isolate
    // reach it through that accessor so they cannot name different stores.
    expect(appState, contains('OwnerAlertPreferences().isEnabled()'));
    expect(appState, contains('OwnerAlertPreferences().setEnabled(enabled)'));
    expect(appState, isNot(contains('ownerAlertsEnabled')));
    final alertState = File(
      'lib/services/owner_booking_alert_state.dart',
    ).readAsStringSync();
    expect(alertState, contains('class OwnerAlertPreferences'));
    expect(
      RegExp(r"'pritze\.notifications\.ownerAlertsEnabled'")
          .allMatches(alertState)
          .length,
      1,
    );
    // The ring is played natively, on the alarm stream so a phone on silent
    // still rings, and looping until it is answered or times out. A channel
    // sound is the phone's to decide - Xiaomi ships it switched off - so the
    // alert was shown but never heard.
    final ringer = File(
      'android/app/src/main/kotlin/com/example/nashik_salon_booking/'
      'OwnerAlertRinger.kt',
    ).readAsStringSync();
    expect(ringer, contains('AudioAttributes.USAGE_ALARM'));
    expect(ringer, contains('looping = true'));
    expect(ringer, contains('R.raw.owner_booking_request'));
    expect(ringer, contains('R.raw.scheduled_booking_request'));
    // No deadline can make it ring past the server's two-minute window.
    expect(ringer, contains('MAX_RING_MS = 130_000L'));
    // Reads the same flags the Dart side writes, so a signed-out phone or an
    // answered request never rings.
    expect(ringer, contains('"pritze.notifications.ownerAlertsEnabled"'));
    expect(ringer, contains('"pritze.notifications.ownerAlertStopped."'));
    final pushReceiver = File(
      'android/app/src/main/kotlin/com/example/nashik_salon_booking/'
      'OwnerAlertPushReceiver.kt',
    ).readAsStringSync();
    expect(pushReceiver, contains('"stop_owner_booking_alarm"'));
    expect(pushReceiver, contains('OwnerAlertRinger.stop(bookingId)'));
    final manifestRinger = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifestRinger, contains('android:name=".OwnerAlertPushReceiver"'));
    expect(
      manifestRinger,
      contains('android:permission="com.google.android.c2dm.permission.SEND"'),
    );
    // Both booking channels are silent, so the tone is never heard twice.
    expect(
      RegExp(r'playSound: false').allMatches(appState).length,
      greaterThanOrEqualTo(3),
    );
    expect(appState, isNot(contains('AudioAttributesUsage.alarm')));
    // Every way an alert ends in the app also stops the native ring.
    expect(
      RegExp(
        r'Future<void> _cancelOwnerBookingNotifications\([^)]*\) async \{\s*'
        r'(//[^\n]*\n\s*)*await OwnerAlertDeviceSettings\.stopAlertRing\(bookingId\);',
      ).hasMatch(appState),
      isTrue,
    );
    final mainActivityRinger = File(
      'android/app/src/main/kotlin/com/example/nashik_salon_booking/'
      'MainActivity.kt',
    ).readAsStringSync();
    expect(mainActivityRinger, contains('OwnerAlertRinger.stop(bookingId)'));
    // The id now lives in one place, shared with the readiness check so both
    // always mean the same channel.
    expect(appState, contains('ownerBookingRequestChannelId'));
    expect(appState, contains('_legacyOwnerBookingRequestChannelIds'));
    expect(appState, contains("'ownerNotificationsEnabled': isOwnerSession"));
    expect(appState, contains("'appVersion': appVersion"));
    expect(appState, contains("'appBuildNumber': appBuildNumber"));
    // An owner whose stored role still says customer must still be treated as
    // an owner session, and the field the server routes on must be promoted.
    expect(
      appState,
      contains('authoritativeRole == UserRole.owner || '
          '_activeRole == UserRole.owner'),
    );
    expect(appState, contains("if (isOwnerSession) 'activeRole'"));
    final rules = File('firestore.rules').readAsStringSync();
    // The profile allowlist rejects the whole write when a field is missing,
    // which is how sign-out silently failed to de-register a device.
    for (final field in <String>[
      'fcmTokens',
      'ownerAlertV4Tokens',
      'ownerAlertV3Tokens',
      'lastFcmToken',
      'notificationsEnabled',
      'ownerNotificationsEnabled',
      'activeRole',
      'appVersion',
      'appBuildNumber',
      'alertDiagnostics',
    ]) {
      expect(rules, contains("'$field'"), reason: '$field must be writable');
    }
    // Sign-out de-registration: the token read must not gate the write that
    // actually stops delivery.
    expect(appState, contains('performSignOutDeregistration('));
    expect(appState, contains('signOutDeregistrationFields('));
    expect(appState, contains('deleteToken: messaging.deleteToken'));
    final deregistration = File(
      'lib/services/push_deregistration.dart',
    ).readAsStringSync();
    expect(deregistration, contains("'notificationsEnabled': false"));
    expect(deregistration, contains("'ownerNotificationsEnabled': false"));
    expect(
      appState,
      contains("await _sendBookingPush(bookingId, event: 'statusUpdated')"),
    );
    expect(appState, contains('additionalFlags:'));
    expect(appState, contains("'accept_instant_booking'"));
    expect(appState, contains("'reject_instant_booking'"));
    expect(appState, contains('showsUserInterface: true'));
    expect(
      RegExp(r'cancelNotification: true').allMatches(appState).length,
      greaterThanOrEqualTo(2),
    );
    expect(
      appState,
      contains('actions: _ownerInstantBookingNotificationActions'),
    );
    expect(appState, contains("'PRITZE_BOOKING_REQUEST_V2'"));
    expect(appState, contains("'PRITZE_BOOKING_REQUEST'"));
    expect(appState, contains('DarwinNotificationCategory('));
    expect(appState, contains('DarwinNotificationAction.plain('));
    expect(
      appState,
      contains('categoryIdentifier: _ownerBookingRequestDarwinCategory'),
    );
    expect(appState, contains('autoCancel: false'));
    expect(appState, contains('FirebaseMessaging.onMessageOpenedApp.listen'));
    expect(appState, contains('messaging.getInitialMessage()'));
    expect(appState, contains('_applyRemoteCustomerBookingHint(message.data)'));
    // The cross-isolate preferences all live in the alert service now; the
    // app itself no longer reaches for a store of its own.
    expect(alertState, contains('SharedPreferencesAsync('));
    expect(appState, contains('_persistPendingOwnerBookingAction'));
    expect(appState, contains('_cancelOwnerBookingNotifications'));
    expect(appState, contains('_loadServerBooking(bookingId)'));
    expect(appState, contains('onDidReceiveNotificationResponse:'));
    expect(appState, contains('onDidReceiveBackgroundNotificationResponse:'));
    expect(appState, contains('notificationActionBackgroundHandler'));
    expect(appState, contains("httpsCallable('updateBookingStatus')"));
    expect(appState, contains('_prepareBackgroundBookingActionFirebase'));
    expect(appState, contains('FirebaseAppCheck.instance.getToken()'));
    expect(appState, contains('Never restart the continuous alarm'));
    expect(appState, contains('_backgroundBookingActionAuthTimeout'));
    expect(appState, contains('authStateChanges()'));
    final accountActions = File(
      'lib/widgets/account_actions.dart',
    ).readAsStringSync();
    expect(
      accountActions,
      contains('_unreadNotificationBadgeLifetime'),
      reason: 'The app should not surface stale booking history as unread.',
    );
    expect(accountActions, contains('_isCurrentUnreadBookingNotification'));
    expect(appState, contains('getNotificationAppLaunchDetails()'));
    expect(
      appState,
      contains('booking.isInstant && booking.status == BookingStatus.pending'),
    );
    expect(appState, contains("sound: 'owner_booking_request.wav'"));
    expect(
      RegExp(r'requestSoundPermission: false').allMatches(appState).length,
      greaterThanOrEqualTo(2),
    );

    final functions = File('functions/index.js').readAsStringSync();
    expect(functions, contains('"pritze_owner_booking_requests_v4"'));
    expect(functions, contains('"pritze_owner_booking_requests_v3"'));
    expect(functions, contains('"pritze_owner_booking_requests_v2"'));
    expect(functions, contains('"ownerAlertV4Tokens"'));
    expect(functions, contains('"ownerAlertV3Tokens"'));
    // Each generation is addressed on its own token list and excluded from the
    // older ones, so one device receives one alert.
    expect(functions, contains('tokenField: OWNER_ALERT_TOKEN_FIELD'));
    expect(
      functions,
      contains('excludeTokenField: OWNER_ALERT_TOKEN_FIELD'),
    );
    expect(functions, contains('excludeTokenFields: ['));
    // A signed-out device must be refused server side too: FCM token
    // rotation means its older tokens can still be in the list.
    expect(functions, contains('data.notificationsEnabled === false'));
    expect(project, contains('scheduled_booking_request.wav in Resources'));
    expect(appState, contains('_scheduledBookingRequestChannel'));
    expect(appState, contains('scheduledBookingRequestChannelId'));
    expect(functions, contains('"pritze_scheduled_booking_requests_v2"'));
    expect(functions, contains('SCHEDULED_BOOKING_REQUEST_CHANNEL'));
    expect(functions, contains('androidSound: SCHEDULED_BOOKING_REQUEST_SOUND'));
    expect(functions, contains('apnsSound: "scheduled_booking_request.wav"'));
    expect(functions, contains('requireActiveOwnerSession: true'));
    expect(functions, contains('requiredActiveRolesByUser'));
    expect(functions, contains('customerPayableAmount: money('));
    expect(functions, contains('completedAtMillis: adminMillis('));
    expect(
      functions,
      contains('Completion is the customer\'s payment trigger.'),
    );
    expect(functions, contains('!requiredRoles.includes(data.activeRole)'));
    expect(functions, contains('data.ownerNotificationsEnabled !== true'));
    expect(functions, contains('onDocumentCreated'));
    expect(functions, contains('createdBooking?.isInstant !== true'));
    expect(functions, contains('OWNER_ALERT_ATTEMPTS = 10'));
    expect(functions, contains('OWNER_ALERT_REPEAT_DELAY_MS = 15_000'));
    expect(functions, contains('INSTANT_RESPONSE_TIMEOUT_MS'));
    expect(functions, contains('expirePendingInstantBooking'));
    expect(functions, contains('Oops, looks like the salon is busy'));
    expect(functions, contains('androidDataOnly: true'));
    expect(
      functions,
      contains('"apns-priority": message.controlOnly ? "5" : "10"'),
    );
    expect(
      functions,
      contains(
        '"apns-push-type": message.controlOnly ? "background" : "alert"',
      ),
    );
    expect(functions, contains('onDocumentUpdated'));
    expect(functions, contains('stop_owner_booking_alarm'));
    expect(functions, contains('owner booking alert continued'));
    expect(functions, contains('apnsSound: "owner_booking_request.wav"'));
    expect(functions, contains('"PRITZE_BOOKING_REQUEST_V2"'));
    expect(functions, contains('IOS_OWNER_BOOKING_REQUEST_CATEGORY'));
    expect(
      functions,
      contains('apnsCategory: IOS_OWNER_BOOKING_REQUEST_CATEGORY'),
    );
    expect(functions, contains('function logPushDeliveryFailures('));
    expect(functions, contains('console.error("push delivery failed"'));
    expect(functions, contains('androidSound: OWNER_BOOKING_REQUEST_SOUND'));
    expect(functions, contains('exports.sendBookingArrivalReminders'));
    expect(functions, contains('schedule: "every 1 minutes"'));
    expect(functions, contains('"customerArrivalReminderSentAt"'));
    expect(functions, contains('"ownerArrivalReminderSentAt"'));
    final recipientLogic = File(
      'functions/booking_notification_logic.js',
    ).readAsStringSync();
    expect(recipientLogic, contains('after.customerUid'));
    expect(recipientLogic, contains('after.ownerUid'));

    // The battery-optimisation list filters to "Not optimized" by default, so
    // the app the owner is looking for is the one it hides. App info always
    // shows it, and is where Battery > Unrestricted lives on Android 13+.
    final manifestEarly = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/example/nashik_salon_booking/'
      'MainActivity.kt',
    ).readAsStringSync();
    expect(
      mainActivity,
      contains('startSettings(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)'),
    );
    expect(mainActivity, contains('"openNotificationSettings"'));
    // The app-level permission can be granted while this one channel is off,
    // which drops the alert silently; and "Restricted" background is a
    // different switch from the battery-optimisation whitelist, so checking
    // only the whitelist left the warning up after it had been fixed.
    expect(mainActivity, contains('"isAlertChannelBlocked"'));
    expect(mainActivity, contains('"isBackgroundRestricted"'));
    // A data-only alert is withheld from an app Android has restricted, and
    // that state is re-applied without the owner acting. A foreground service
    // is the only thing that keeps the alert working with the app closed.
    expect(mainActivity, contains('"startOwnerAlertService"'));
    expect(mainActivity, contains('"stopOwnerAlertService"'));
    final alertService = File(
      'android/app/src/main/kotlin/com/example/nashik_salon_booking/'
      'OwnerAlertService.kt',
    ).readAsStringSync();
    expect(alertService, contains('startForeground('));
    expect(alertService, contains('START_STICKY'));
    expect(alertService, contains('IMPORTANCE_LOW'));
    // Tapping the permanent notification must bring back the running app.
    // Without CLEAR_TOP it stacked a fresh MainActivity - a second Flutter
    // engine starting from nothing - whenever a settings screen was on top.
    expect(alertService, contains('Intent.FLAG_ACTIVITY_CLEAR_TOP'));
    expect(alertService, contains('Intent.FLAG_ACTIVITY_SINGLE_TOP'));
    // A refused sticky restart must stop the service, not crash the process
    // that also hosts the FCM isolate.
    expect(
      RegExp(
        r'try \{\s*startForeground\(.*?\} catch',
        dotAll: true,
      ).hasMatch(alertService),
      isTrue,
    );
    // The profile listener must not register on every snapshot: registering
    // writes that profile, so it re-triggered itself without end.
    expect(
      RegExp(
        r'_ownerAccount = account;\s*//[^\n]*\n(\s*//[^\n]*\n)*\s*final token = '
        r'_registeredMessagingToken;\s*if \(token == null \|\|\s*'
        r'!isMessagingRegistrationCurrent\(',
      ).hasMatch(appState),
      isTrue,
      reason: 'the owner profile listener must skip a current registration',
    );
    expect(appState, contains('deviceSignature == _reportedDeviceSignature'));
    // The diagnostics-only write must not touch the account-wide stop.
    final diagnosticsWrite = RegExp(
      r'Future<void> _reportAlertDiagnostics\(.*?\n  \}\n',
      dotAll: true,
    ).firstMatch(appState)?.group(0);
    expect(diagnosticsWrite, isNotNull);
    expect(diagnosticsWrite, isNot(contains("'notificationsEnabled'")));
    expect(manifestEarly, contains('FOREGROUND_SERVICE_SPECIAL_USE'));
    expect(manifestEarly, contains('android:foregroundServiceType="specialUse"'));
    expect(manifestEarly, contains('PROPERTY_SPECIAL_USE_FGS_SUBTYPE'));
    expect(appState, contains('OwnerAlertDeviceSettings.startAlertService()'));
    expect(appState, contains('OwnerAlertDeviceSettings.stopAlertService()'));
    // The permanent notification exists only while the salon is actually open
    // for instant bookings, the way a driver app ties it to being online.
    expect(appState, contains('salonOpen: salon?.isOpen ?? false'));
    expect(appState, contains('isInstantBookingEnabledForSalon(salon)'));
    expect(appState, contains('_syncOwnerAlertService()'));
    // The salon loads after the account, so the listener decision has to be
    // revisited when it arrives or it is made once, wrongly, and never again.
    // Matched on structure, not on indentation: the point is that the same
    // handler that marks the list loaded also re-evaluates the alert
    // listener, not where in the file it happens to sit.
    expect(
      RegExp(
        r'_salonsLoaded = true;.*?_syncOwnerBookingAlarm\(\)',
        dotAll: true,
      ).firstMatch(appState)?.group(0),
      isNotNull,
      reason: 'the salon snapshot must re-sync the owner alert listener',
    );
    expect(appState, contains('shouldRunOwnerAlertService('));
    expect(mainActivity, contains('IMPORTANCE_NONE'));
    expect(mainActivity, contains('activity.isBackgroundRestricted'));
    expect(
      mainActivity,
      contains('Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS'),
    );
    final readiness = File(
      'lib/services/owner_alert_readiness.dart',
    ).readAsStringSync();
    expect(readiness, contains('backgroundRestricted'));
    expect(readiness, contains('alertChannelBlocked'));
    // The readiness check must ask about the channel the alert is posted on.
    expect(
      readiness,
      contains("ownerBookingRequestChannelId = 'pritze_owner_booking_requests_v5'"),
    );
    expect(appState, contains('AndroidNotificationChannel(\n  ownerBookingRequestChannelId'));
    expect(
      mainActivity,
      contains('Settings.ACTION_APP_NOTIFICATION_SETTINGS'),
    );
    final dashboard = File(
      'lib/screens/salon/salon_dashboard_screen.dart',
    ).readAsStringSync();
    // Notifications are denied by default on Android 13+, so that blocker
    // needs an action, not just a sentence.
    expect(
      dashboard,
      contains('OwnerAlertBlocker.notificationsDisabled =>\n'
          '        await OwnerAlertDeviceSettings.openNotificationSettings()'),
    );

    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
    expect(manifest, contains('android.permission.USE_FULL_SCREEN_INTENT'));
    // Without these the full-screen intent wakes the phone to the keyguard
    // and the request stays hidden behind it.
    expect(manifest, contains('android:showWhenLocked="true"'));
    expect(manifest, contains('android:turnScreenOn="true"'));
    expect(
      manifest,
      contains('com.google.firebase.messaging.default_notification_channel_id'),
    );
    expect(
      manifest,
      contains(
        'com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver',
      ),
    );

    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(infoPlist, contains('<string>fetch</string>'));
    expect(infoPlist, contains('<string>remote-notification</string>'));
    expect(infoPlist, contains('app-1-3474382418-ios-73bf27d33b1eddec8c498b'));
    expect(infoPlist, contains('<key>NSContactsUsageDescription</key>'));
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(appDelegate, contains('import flutter_local_notifications'));
    expect(
      appDelegate,
      contains('FlutterLocalNotificationsPlugin.setPluginRegistrantCallback'),
    );
    expect(appDelegate, contains('CNContactPickerViewController'));
    expect(
      appDelegate,
      contains('application.registerForRemoteNotifications()'),
    );
    final entitlements = File(
      'ios/Runner/Runner.entitlements',
    ).readAsStringSync();
    expect(entitlements, contains('<key>aps-environment</key>'));
    // No salon owner is on iOS yet, so the owner alert is deliberately an
    // ordinary notification there: iOS cannot loop a sound, and the
    // time-sensitive entitlement would add an App ID capability the archive
    // has to be signed against. The per-message level stays plumbed through
    // so raising it later is a one-line change.
    expect(
      entitlements,
      isNot(contains('usernotifications.time-sensitive')),
      reason: 'adding this needs the App ID capability enabled first',
    );
    expect(appState, contains('interruptionLevel: InterruptionLevel.active'));
    expect(functions, contains('message.apnsInterruptionLevel || "active"'));
    expect(functions, isNot(contains('apnsInterruptionLevel: "')));
  });
}

void _expectValidWaveFile(File file) {
  final bytes = file.readAsBytesSync();
  expect(bytes.length, greaterThan(44));
  expect(ascii.decode(bytes.sublist(0, 4)), 'RIFF');
  expect(ascii.decode(bytes.sublist(8, 12)), 'WAVE');
  final header = ByteData.sublistView(Uint8List.fromList(bytes));
  final channelCount = header.getUint16(22, Endian.little);
  final sampleRate = header.getUint32(24, Endian.little);
  final bitsPerSample = header.getUint16(34, Endian.little);
  final bytesPerSecond = sampleRate * channelCount * (bitsPerSample ~/ 8);
  final durationSeconds = (bytes.length - 44) / bytesPerSecond;
  expect(durationSeconds, greaterThanOrEqualTo(28));
  expect(durationSeconds, lessThan(30));
  expect(bytes.length, lessThan(6 * 1024 * 1024));
}

void _expectShortWaveFile(File file) {
  final bytes = file.readAsBytesSync();
  expect(bytes.length, greaterThan(44));
  expect(ascii.decode(bytes.sublist(0, 4)), 'RIFF');
  expect(ascii.decode(bytes.sublist(8, 12)), 'WAVE');
  final header = ByteData.sublistView(Uint8List.fromList(bytes));
  final channelCount = header.getUint16(22, Endian.little);
  final sampleRate = header.getUint32(24, Endian.little);
  final bitsPerSample = header.getUint16(34, Endian.little);
  final durationSeconds =
      (bytes.length - 44) / (sampleRate * channelCount * (bitsPerSample ~/ 8));
  // One short tone. iOS refuses a notification sound of 30 seconds or more.
  expect(durationSeconds, greaterThan(0.5));
  expect(durationSeconds, lessThan(10));
}
