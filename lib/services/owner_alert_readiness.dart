import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _ownerAlertChannel = MethodChannel('com.trimtime.app/owner_alerts');

/// The Android notification channel the booking alert is posted on. Shared so
/// the readiness check asks about the same channel the alert actually uses.
///
/// v5 is silent: the sound is played natively by `OwnerAlertRinger`, because
/// some phones ship app channel sounds switched off and give apps no way to
/// turn them on. The server still names the request v4; that is a routing
/// label, not the channel it is shown on.
const ownerBookingRequestChannelId = 'pritze_owner_booking_requests_v5';

/// Silent for the same reason; the tone is played natively, once.
const scheduledBookingRequestChannelId = 'pritze_scheduled_booking_requests_v2';

/// Why an owner's phone would stay silent for a booking request.
///
/// Each of these fails silently on the device: the server sends the push, the
/// app posts the alert, and the owner still hears nothing. Reporting them is
/// the only way an owner can tell a quiet evening from a broken one.
enum OwnerAlertBlocker {
  /// The system notification permission is off, so nothing is shown at all.
  notificationsDisabled,

  /// No FCM token is registered, so the server cannot reach this device.
  noPushToken,

  /// Android 14+ withheld USE_FULL_SCREEN_INTENT. The alert still arrives but
  /// only as a banner, which a locked phone never surfaces.
  fullScreenIntentDenied,

  /// The app is in Android's "Restricted" background state — the third option
  /// in App info > Battery, below Unrestricted and Optimised.
  ///
  /// This is the only battery setting that actually stops delivery, and it is
  /// never the default: a phone is in this state because somebody chose it.
  /// Being merely "Optimised" is the normal state of every Android app and
  /// does not stop a high-priority message, which is why it is reported in
  /// [OwnerAlertDeviceSettings.diagnostics] but is not a blocker. Raising it
  /// as one told owners to fix something that was never broken, and the
  /// warning could not be cleared by doing what it asked.
  backgroundRestricted,

  /// Notifications are allowed for the app, but the booking-request channel
  /// itself is switched off, so the alert is dropped without a trace.
  alertChannelBlocked,
}

@immutable
class OwnerAlertReadiness {
  const OwnerAlertReadiness(this.blockers);

  final Set<OwnerAlertBlocker> blockers;

  /// True when nothing stands between a booking request and a ringing phone.
  bool get isReady => blockers.isEmpty;

  /// These stop the alert entirely rather than just making it easy to miss.
  bool get isSilent =>
      blockers.contains(OwnerAlertBlocker.notificationsDisabled) ||
      blockers.contains(OwnerAlertBlocker.noPushToken) ||
      // A blocked channel or a restricted app shows nothing at all, so these
      // are silent failures too, not merely easy to miss.
      blockers.contains(OwnerAlertBlocker.alertChannelBlocked) ||
      blockers.contains(OwnerAlertBlocker.backgroundRestricted);
}

class OwnerAlertDeviceSettings {
  const OwnerAlertDeviceSettings._();

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Defaults to "not blocking" whenever the platform cannot answer. A missing
  /// channel must never invent a warning the owner cannot act on.
  static Future<bool> _ask(
    String method, {
    bool fallback = true,
    Map<String, Object?>? arguments,
  }) async {
    if (!_supported) return fallback;
    try {
      return await _ownerAlertChannel.invokeMethod<bool>(method, arguments) ??
          fallback;
    } on MissingPluginException {
      return fallback;
    } on PlatformException {
      return fallback;
    }
  }

  static Future<bool> canUseFullScreenIntent() =>
      _ask('canUseFullScreenIntent');

  static Future<bool> isIgnoringBatteryOptimizations() =>
      _ask('isIgnoringBatteryOptimizations');

  /// True when Android has the app in its "Restricted" background state.
  static Future<bool> isBackgroundRestricted() =>
      _ask('isBackgroundRestricted', fallback: false);

  /// True when the booking-request channel cannot show anything, either
  /// because notifications are off app-wide or because this one channel is.
  static Future<bool> isAlertChannelBlocked() => _ask(
    'isAlertChannelBlocked',
    fallback: false,
    arguments: {'channelId': ownerBookingRequestChannelId},
  );

  /// A snapshot of what this phone is really doing with the alert, written to
  /// the owner's profile so a silent failure can be read remotely. Empty when
  /// the platform cannot answer.
  static Future<Map<String, Object?>> diagnostics() async {
    if (!_supported) return const {};
    try {
      final result = await _ownerAlertChannel.invokeMapMethod<String, Object?>(
        'alertServiceDiagnostics',
        {'channelId': ownerBookingRequestChannelId},
      );
      final error = await _ownerAlertChannel.invokeMethod<String>(
        'lastServiceStartError',
      );
      return {
        ...?result,
        if (error != null && error.isNotEmpty) 'startError': error,
      };
    } on MissingPluginException {
      return const {};
    } on PlatformException {
      return const {};
    }
  }

  /// Keeps the process resident so a data-only booking alert still arrives
  /// with the app closed. Safe to call repeatedly.
  static Future<bool> startAlertService() =>
      _ask('startOwnerAlertService', fallback: false);

  static Future<bool> stopAlertService() =>
      _ask('stopOwnerAlertService', fallback: false);

  /// Size in bytes of Firestore's database on this phone, or null when the
  /// platform cannot say.
  static Future<int?> firestoreDatabaseBytes() async {
    if (!_supported) return null;
    try {
      return await _ownerAlertChannel.invokeMethod<int>(
        'firestoreDatabaseBytes',
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Starts the booking request's ring in native code. Only the main app
  /// engine has this channel; in a background isolate this is a no-op, and
  /// the native push receiver has already started the ring itself.
  static Future<bool> ringAlert(String bookingId, DateTime deadline) => _ask(
    'ringOwnerAlert',
    fallback: false,
    arguments: {
      'bookingId': bookingId,
      'deadlineMillis': deadline.millisecondsSinceEpoch,
    },
  );

  /// Stops the ring for [bookingId], or every ring when it is null.
  static Future<bool> stopAlertRing([String? bookingId]) => _ask(
    'stopOwnerAlertRing',
    fallback: false,
    arguments: {'bookingId': bookingId},
  );

  /// Opens the booking-request channel's own settings page.
  static Future<bool> openAlertChannelSettings() => _ask(
    'openAlertChannelSettings',
    fallback: false,
    arguments: {'channelId': ownerBookingRequestChannelId},
  );

  /// Opens the system screen. Returns false when the device has no such
  /// screen, so the caller can tell the owner where to look instead.
  static Future<bool> openFullScreenIntentSettings() =>
      _ask('openFullScreenIntentSettings', fallback: false);

  static Future<bool> openBatteryOptimizationSettings() =>
      _ask('openBatteryOptimizationSettings', fallback: false);

  /// Opens this app's notification settings. Android 13 and later install with
  /// notifications denied, so this is usually the first thing to turn on.
  static Future<bool> openNotificationSettings() =>
      _ask('openNotificationSettings', fallback: false);

  /// [notificationsEnabled] and [hasPushToken] come from the app's own
  /// messaging state; only the two device settings are asked of the platform.
  static Future<OwnerAlertReadiness> check({
    required bool notificationsEnabled,
    required bool hasPushToken,
  }) async {
    final blockers = <OwnerAlertBlocker>{};
    if (!notificationsEnabled) {
      blockers.add(OwnerAlertBlocker.notificationsDisabled);
    }
    if (!hasPushToken) {
      blockers.add(OwnerAlertBlocker.noPushToken);
    }
    if (_supported) {
      if (!await canUseFullScreenIntent()) {
        blockers.add(OwnerAlertBlocker.fullScreenIntentDenied);
      }
      if (await isBackgroundRestricted()) {
        blockers.add(OwnerAlertBlocker.backgroundRestricted);
      }
      if (await isAlertChannelBlocked()) {
        blockers.add(OwnerAlertBlocker.alertChannelBlocked);
      }
    }
    return OwnerAlertReadiness(blockers);
  }
}

/// Owner-facing wording. Each line names the symptom first, because an owner
/// recognises "requests do not ring" long before they recognise the setting.
String ownerAlertBlockerMessage(OwnerAlertBlocker blocker) {
  return switch (blocker) {
    OwnerAlertBlocker.notificationsDisabled =>
      'Booking requests cannot alert you. Turn on notifications for SalonFe.',
    OwnerAlertBlocker.noPushToken =>
      'This device is not registered for booking alerts. Sign out and sign in '
          'again to reconnect it.',
    OwnerAlertBlocker.fullScreenIntentDenied =>
      'Requests will not show on a locked screen. Allow full screen alerts so '
          'they ring like a call.',
    OwnerAlertBlocker.backgroundRestricted =>
      'This phone is set to "Restricted" for SalonFe, so booking requests '
          'cannot arrive at all. Tap Fix, open Battery, and change '
          'Restricted to Unrestricted.',
    OwnerAlertBlocker.alertChannelBlocked =>
      'Booking request alerts are switched off for this app. Tap Fix and turn '
          'on "Owner booking requests".',
  };
}
