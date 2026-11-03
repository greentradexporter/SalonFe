import 'package:flutter_test/flutter_test.dart';
import 'package:nashik_salon_booking/services/owner_alert_readiness.dart';
import 'package:nashik_salon_booking/widgets/device_setup_gate.dart';

void main() {
  test('setup runs once, and only when something is actually wrong', () {
    expect(
      shouldShowDeviceSetup(
        alreadyShown: false,
        blockers: {OwnerAlertBlocker.backgroundRestricted},
      ),
      isTrue,
    );
    // A healthy phone must never be shown a screen asking it to fix nothing.
    expect(
      shouldShowDeviceSetup(alreadyShown: false, blockers: const {}),
      isFalse,
    );
    // One-time offer, not a nag.
    expect(
      shouldShowDeviceSetup(
        alreadyShown: true,
        blockers: {OwnerAlertBlocker.backgroundRestricted},
      ),
      isFalse,
    );
  });

  test('being merely battery-optimised is not reported as a problem', () {
    // Every Android app is "Optimised" by default and high-priority messages
    // still arrive. Treating it as a blocker raised a warning on healthy
    // phones that could not be cleared by doing what it asked, which read as
    // the setting switching itself back off.
    final names = OwnerAlertBlocker.values.map((b) => b.name).toList();
    expect(names, isNot(contains('batteryOptimised')));
  });

  test('the restricted-background message names the setting to change', () {
    final message = ownerAlertBlockerMessage(
      OwnerAlertBlocker.backgroundRestricted,
    );
    expect(message, contains('Restricted'));
    expect(message, contains('Unrestricted'));
    // Ambiguity here is the whole bug: the old copy told owners to "choose
    // Unrestricted" without saying what it was currently set to.
    expect(message, contains('Battery'));
  });
}
