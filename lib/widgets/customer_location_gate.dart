import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../state/app_state_scope.dart';

/// A one-shot, foreground discovery location; arrival sharing is separate.
class CustomerLocationGate extends StatefulWidget {
  final Widget child;
  final bool enabled;
  const CustomerLocationGate({
    super.key,
    required this.child,
    this.enabled = true,
  });
  static bool _started = false;
  static const _askedKey = 'salonfe.discoveryLocation.asked';
  static const _consentKey = 'salonfe.discoveryLocation.consent';

  static Future<void> request(
    BuildContext context, {
    bool force = false,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    if (!context.mounted) return;
    final state = AppStateScope.read(context);
    if (!state.usesFirebase) return;
    if (state.hasActiveOwnerSession || state.hasActiveBarberSession) return;
    final asked = preferences.getBool(_askedKey) ?? false;
    var consent = preferences.getBool(_consentKey) ?? false;
    if (force || !asked) {
      final allow = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Use your location?'),
          content: const Text(
            'Allow SalonFe to use your location while the app is open for salon discovery. When signed in, an approximate location is saved privately to your account. You can still browse without it. Sharing your journey with a salon is a separate choice.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Allow location'),
            ),
          ],
        ),
      );
      await preferences.setBool(_askedKey, true);
      consent = allow == true;
      await preferences.setBool(_consentKey, consent);
    }
    if (!consent) {
      await state.clearCustomerDiscoveryLocation();
      return;
    }
    if (!context.mounted) return;
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        await preferences.setBool(_consentKey, false);
        await state.clearCustomerDiscoveryLocation();
        if (force && context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: const Text(
                'Location permission is off. You can enable it in device settings.',
              ),
              action: SnackBarAction(
                label: 'Settings',
                onPressed: () => Geolocator.openAppSettings(),
              ),
            ),
          );
        }
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (force && context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(
              content: Text(
                'Turn on device location services, then try again.',
              ),
            ),
          );
        }
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );
      await state.setCustomerDiscoveryLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
      );
    } catch (_) {
      // Optional discovery must never block browsing, login or booking.
    }
  }

  static Future<void> clear(BuildContext context) async {
    final state = AppStateScope.read(context);
    await (await SharedPreferences.getInstance()).setBool(_consentKey, false);
    await state.clearCustomerDiscoveryLocation();
  }

  @override
  State<CustomerLocationGate> createState() => _CustomerLocationGateState();
}

class _CustomerLocationGateState extends State<CustomerLocationGate> {
  String? _savedFor;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.enabled) return;
    if (!CustomerLocationGate._started) {
      CustomerLocationGate._started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(CustomerLocationGate.request(context));
      });
    }
    final state = AppStateScope.watch(context);
    final uid = state.customerAccount?.id;
    final latitude = state.customerDiscoveryLatitude;
    final longitude = state.customerDiscoveryLongitude;
    final accuracy = state.customerDiscoveryAccuracy ?? 100;
    if (state.hasActiveCustomerSession &&
        uid != _savedFor &&
        latitude != null &&
        longitude != null) {
      _savedFor = uid;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            state.hasActiveCustomerSession &&
            state.customerAccount?.id == uid &&
            state.customerDiscoveryLatitude != null) {
          unawaited(
            state
                .setCustomerDiscoveryLocation(
                  latitude: latitude,
                  longitude: longitude,
                  accuracyMeters: accuracy,
                )
                .catchError((_) {}),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
