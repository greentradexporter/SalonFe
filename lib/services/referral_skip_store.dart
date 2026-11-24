import 'package:shared_preferences/shared_preferences.dart';

/// Account-scoped, durable choice. The server acknowledgement is independent
/// of navigation, so loss of connectivity never holds up "No referral code".
class ReferralSkipStore {
  static String _key(String uid) => 'salonfe.referralSkipped.$uid';
  static String _pendingKey(String uid) => 'salonfe.referralSkipPending.$uid';
  static Future<bool> wasSkipped(String uid) async =>
      (await SharedPreferences.getInstance()).getBool(_key(uid)) ?? false;
  static Future<bool> needsSync(String uid) async =>
      (await SharedPreferences.getInstance()).getBool(_pendingKey(uid)) ??
      false;
  static Future<void> skip(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    // Mark pending first: a crash cannot lose an accepted local choice.
    await prefs.setBool(_pendingKey(uid), true);
    await prefs.setBool(_key(uid), true);
  }

  static Future<void> acknowledge(String uid) async {
    await (await SharedPreferences.getInstance()).remove(_pendingKey(uid));
  }
}
