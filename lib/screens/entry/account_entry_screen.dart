import 'package:flutter/material.dart';

import '../../models/app_models.dart';
import '../../state/app_state_scope.dart';
import '../../widgets/salonfe_logo.dart';
import '../barber/barber_dashboard_screen.dart';
import '../customer/customer_home_screen.dart';
import '../referrals/referral_onboarding_screen.dart';
import '../salon/salon_dashboard_screen.dart';
import 'welcome_screen.dart';

/// The account, rather than the last visited page, determines the launch home.
class AppEntryScreen extends StatelessWidget {
  const AppEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.watch(context);
    if (state.isRestoringSession) return const SessionRestoreScreen();
    final signedIn =
        state.hasActiveCustomerSession ||
        state.hasActiveOwnerSession ||
        state.hasActiveBarberSession;
    if (!signedIn) {
      return state.isGuestBrowsing
          ? const CustomerHomeScreen()
          : const WelcomeScreen();
    }
    if (state.referralOnboardingRequired) {
      return const ReferralOnboardingScreen();
    }
    return switch (state.activeRole) {
      UserRole.owner => const SalonDashboardScreen(),
      UserRole.barber => const BarberDashboardScreen(),
      UserRole.customer => const CustomerHomeScreen(),
      null => const WelcomeScreen(),
    };
  }
}

/// Clear the previous account's routes after authentication or logout. This
/// also prevents Android Back from returning to the role chooser after login.
void openAccountHome(BuildContext context) {
  ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute<void>(builder: (_) => const AppEntryScreen()),
    (_) => false,
  );
}

class SessionRestoreScreen extends StatelessWidget {
  const SessionRestoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SalonFeLogo(size: 60, shadow: false),
              SizedBox(height: 20),
              SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(height: 12),
              Text(
                'Opening SalonFe',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
