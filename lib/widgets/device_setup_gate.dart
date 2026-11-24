import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/brand_header.dart';
import '../services/owner_alert_readiness.dart';
import '../state/app_state_scope.dart';
import '../theme/app_theme.dart';

/// Preference key for "this install has already been walked through setup".
/// Versioned so a future change to what we ask for can run the walkthrough
/// again without clearing anything else.
const deviceSetupShownPreferenceKey = 'pritze_device_setup_shown_v1';

/// Whether the one-time device walkthrough should run.
///
/// Only once per install, and only when something is actually wrong: a phone
/// that is already set up correctly must never be shown a screen asking it to
/// fix nothing.
bool shouldShowDeviceSetup({
  required bool alreadyShown,
  required Set<OwnerAlertBlocker> blockers,
}) => !alreadyShown && blockers.isNotEmpty;

/// Walks the user through the device settings that silence booking alerts,
/// once, just after install.
///
/// The notification permission itself is a system dialog and is already asked
/// for at startup. The rest cannot be granted from a dialog at all — Android
/// has no API to leave the "Restricted" background state, and the full-screen
/// and channel settings are pages, not prompts — so the most an app can do is
/// take the user straight to each one. Doing it here means an owner is asked
/// while they are setting the app up, rather than discovering a banner weeks
/// later after a booking request went unanswered.
class DeviceSetupGate extends StatefulWidget {
  const DeviceSetupGate({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<DeviceSetupGate> createState() => _DeviceSetupGateState();
}

class _DeviceSetupGateState extends State<DeviceSetupGate> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_maybeRun()));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppStateScope.watch(context);
    if (!_started &&
        !state.isRestoringSession &&
        state.hasActiveOwnerSession &&
        !state.referralOnboardingRequired) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_maybeRun()),
      );
    }
  }

  Future<void> _maybeRun() async {
    if (!mounted || _started) return;
    final state = AppStateScope.read(context);
    // Keep signed-out launches on the welcome screen. This walkthrough is
    // specific to owner booking alerts, so it starts only in an owner session.
    if (state.isRestoringSession ||
        !state.hasActiveOwnerSession ||
        state.referralOnboardingRequired) {
      return;
    }
    _started = true;
    try {
      final preferences = await SharedPreferences.getInstance();
      if (preferences.getBool(deviceSetupShownPreferenceKey) ?? false) {
        return;
      }
      // The startup permission dialog owns the screen first. Asking what is
      // still blocking before the user has answered it would report
      // notifications as denied and send them to a page they do not need, so
      // stand down this launch and come back on the next one. Waiting on a
      // timer instead would be a guess at how long they take to decide.
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
        return;
      }
      final blockers = await _currentBlockers();
      // Recorded whether or not anything is shown, and whether or not the
      // user acts on it. This is a one-time offer, not a nag.
      await preferences.setBool(deviceSetupShownPreferenceKey, true);
      if (!shouldShowDeviceSetup(alreadyShown: false, blockers: blockers)) {
        return;
      }
      final navigator = widget.navigatorKey.currentState;
      if (navigator == null || !navigator.mounted) return;
      if (!mounted) return;
      final latestState = AppStateScope.read(context);
      if (!latestState.hasActiveOwnerSession ||
          latestState.referralOnboardingRequired) {
        return;
      }
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const DeviceSetupScreen(),
          fullscreenDialog: true,
        ),
      );
    } catch (_) {
      // Setup guidance must never be the reason the app fails to start.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<Set<OwnerAlertBlocker>> _currentBlockers() async {
  final settings = await FirebaseMessaging.instance.getNotificationSettings();
  final status = settings.authorizationStatus;
  final readiness = await OwnerAlertDeviceSettings.check(
    notificationsEnabled:
        status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional,
    // Registration happens in the background and is reported separately; this
    // screen covers only what the person in front of the phone can change.
    hasPushToken: true,
  );
  return readiness.blockers;
}

class DeviceSetupScreen extends StatefulWidget {
  const DeviceSetupScreen({super.key});

  @override
  State<DeviceSetupScreen> createState() => _DeviceSetupScreenState();
}

class _DeviceSetupScreenState extends State<DeviceSetupScreen>
    with WidgetsBindingObserver {
  Set<OwnerAlertBlocker> _blockers = <OwnerAlertBlocker>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // They fix each one in system settings and come back, so re-check rather
    // than leaving an item ticked off looking unresolved.
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    try {
      final blockers = await _currentBlockers();
      if (mounted) {
        setState(() {
          _blockers = blockers;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fix(OwnerAlertBlocker blocker) async {
    final opened = switch (blocker) {
      OwnerAlertBlocker.notificationsDisabled =>
        await OwnerAlertDeviceSettings.openNotificationSettings(),
      OwnerAlertBlocker.fullScreenIntentDenied =>
        await OwnerAlertDeviceSettings.openFullScreenIntentSettings(),
      OwnerAlertBlocker.backgroundRestricted =>
        await OwnerAlertDeviceSettings.openBatteryOptimizationSettings(),
      OwnerAlertBlocker.alertChannelBlocked =>
        await OwnerAlertDeviceSettings.openAlertChannelSettings(),
      OwnerAlertBlocker.noPushToken => false,
    };
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Open Settings, find SalonFe, and allow notifications.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = !_loading && _blockers.isEmpty;
    return Scaffold(
      appBar: SalonFeAppBar(
        title: const Text('Set up alerts'),
        actions: [
          TextButton(
            key: const ValueKey('skip-device-setup'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Skip'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          Text(
            done
                ? 'This phone is ready'
                : 'A few settings decide whether this phone can alert you',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            done
                ? 'Booking alerts can reach you. You can change any of this '
                      'later from your profile.'
                : 'Android keeps these switched off by default. You only need '
                      'to do this once, and you can skip anything you do not '
                      'want.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else
            for (final blocker in _blockers)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(ownerAlertBlockerMessage(blocker))),
                      const SizedBox(width: 8),
                      FilledButton(
                        key: ValueKey('setup-fix-${blocker.name}'),
                        onPressed: () => _fix(blocker),
                        child: const Text('Open'),
                      ),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 12),
          FilledButton(
            key: const ValueKey('finish-device-setup'),
            style: FilledButton.styleFrom(
              backgroundColor: done ? AppColors.primary : null,
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(done ? 'Done' : 'Continue anyway'),
          ),
        ],
      ),
    );
  }
}
