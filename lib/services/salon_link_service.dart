import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SalonLinkService {
  static const host = 'trimtime-46539.web.app';
  static const _key = 'salonfe.pendingSalonLink';
  static final pendingSalonId = ValueNotifier<String?>(null);
  static final _idPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');
  static String? salonIdFromUri(Uri uri) {
    String? id;
    if (uri.scheme == 'https' &&
        uri.host == host &&
        uri.pathSegments.length == 2 &&
        uri.pathSegments.first == 's') {
      id = uri.pathSegments.last;
    } else if (uri.scheme == 'salonfe' &&
        uri.host == 'salon' &&
        uri.pathSegments.length == 1) {
      id = uri.pathSegments.single;
    }
    return id != null && _idPattern.hasMatch(id) ? id : null;
  }

  static Uri linkFor(String salonId) {
    if (!_idPattern.hasMatch(salonId)) throw ArgumentError('Invalid salon ID');
    return Uri.https(host, '/s/$salonId');
  }

  static Future<void> restore() async {
    final id = (await SharedPreferences.getInstance()).getString(_key);
    if (id != null && _idPattern.hasMatch(id) && pendingSalonId.value == null) {
      pendingSalonId.value = id;
    }
  }

  static Future<bool> accept(Uri uri) async {
    final id = salonIdFromUri(uri);
    if (id == null) return false;
    pendingSalonId.value = id;
    await (await SharedPreferences.getInstance()).setString(_key, id);
    return true;
  }

  static Future<void> clear(String salonId) async {
    if (pendingSalonId.value != salonId) return;
    pendingSalonId.value = null;
    await (await SharedPreferences.getInstance()).remove(_key);
  }
}
