import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'screens/entry/account_entry_screen.dart';
import 'services/firebase_bootstrap.dart';
import 'services/referral_link_service.dart';
import 'state/app_state_scope.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'theme/app_brand.dart';
import 'widgets/customer_booking_confirmation_gate.dart';
import 'widgets/ios_owner_booking_request_gate.dart';
import 'widgets/app_update_prompt.dart';
import 'widgets/device_setup_gate.dart';
import 'widgets/salon_link_gate.dart';

export 'screens/entry/account_entry_screen.dart' show AppEntryScreen;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw a native-looking Flutter launch screen immediately. Firebase core is
  // local work, but starting it before `runApp` used to leave iOS showing its
  // static launch screen until all plugin setup had reached Dart.
  runApp(const SalonFeBootstrapApp());
}

class SalonFeBootstrapApp extends StatefulWidget {
  const SalonFeBootstrapApp({super.key});

  @override
  State<SalonFeBootstrapApp> createState() => _SalonFeBootstrapAppState();
}

class _SalonFeBootstrapAppState extends State<SalonFeBootstrapApp> {
  FirebaseBootstrap? _firebase;

  @override
  void initState() {
    super.initState();
    unawaited(_startFirebase());
  }

  Future<void> _startFirebase() async {
    final firebase = await FirebaseBootstrap.initialize();
    if (!mounted) return;
    if (firebase.enabled) {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    }
    setState(() => _firebase = firebase);
  }

  @override
  Widget build(BuildContext context) {
    final firebase = _firebase;
    if (firebase == null) {
      return MaterialApp(
        title: AppBrand.name,
        theme: AppTheme.build(),
        home: const SessionRestoreScreen(),
        debugShowCheckedModeBanner: false,
      );
    }

    if (!firebase.enabled) {
      return FirebaseUnavailableApp(error: firebase.error);
    }

    return AppStateProvider(
      createAppState: () => FirebaseAppState(
        firestore: firebase.firestore!,
        functions: firebase.functions!,
        auth: firebase.auth!,
        messaging: firebase.messaging!,
        storage: firebase.storage!,
      ),
      child: const TrimtimeApp(),
    );
  }
}

class TrimtimeApp extends StatefulWidget {
  const TrimtimeApp({super.key});

  @override
  State<TrimtimeApp> createState() => _TrimtimeAppState();
}

class _TrimtimeAppState extends State<TrimtimeApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // Deep-link discovery is useful for referral onboarding, but asking the
    // operating system for an initial link must never delay the first frame.
    unawaited(ReferralLinkService.initialize());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: AppBrand.name,
      theme: AppTheme.build(),
      // These listeners must outlive individual pages. Several customer and
      // owner navigation flows replace the complete route stack, so placing
      // them in `home` silently disabled popups after the first navigation.
      builder: (context, child) => AppUpdatePrompt(
        navigatorKey: _navigatorKey,
        child: DeviceSetupGate(
          navigatorKey: _navigatorKey,
          child: IosOwnerBookingRequestGate(
            navigatorKey: _navigatorKey,
            child: CustomerBookingConfirmationGate(
              navigatorKey: _navigatorKey,
              child: SalonLinkGate(
                navigatorKey: _navigatorKey,
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
      home: const AppEntryScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class FirebaseUnavailableApp extends StatelessWidget {
  final Object? error;

  const FirebaseUnavailableApp({super.key, this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppBrand.name,
      theme: AppTheme.build(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Firebase is not configured',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  error?.toString() ??
                      'Add Firebase configuration before running the app.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
