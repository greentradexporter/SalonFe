import 'package:flutter/material.dart';

import '../../models/app_models.dart';
import '../../state/app_state_scope.dart';
import '../../widgets/customer_location_gate.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth_login_panel.dart';
import '../../widgets/brand_header.dart';
import 'account_entry_screen.dart';

class RoleSignInScreen extends StatelessWidget {
  final UserRole role;

  const RoleSignInScreen({super.key, required this.role})
    : assert(role == UserRole.customer || role == UserRole.owner);

  @override
  Widget build(BuildContext context) {
    final owner = role == UserRole.owner;
    return Scaffold(
      appBar: SalonFeAppBar(
        actions: owner
            ? null
            : [
                TextButton(
                  key: const ValueKey('skip-customer-login'),
                  onPressed: () {
                    AppStateScope.read(context).browseAsGuest();
                    openAccountHome(context);
                  },
                  child: const Text('Skip'),
                ),
              ],
        leading: IconButton(
          key: ValueKey(owner ? 'exit-salon-login' : 'exit-customer-login'),
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back to welcome',
          onPressed: () => openAccountHome(context),
        ),
      ),
      body: CustomerLocationGate(
        enabled: !owner,
        child: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  Icon(
                    owner
                        ? Icons.storefront_rounded
                        : Icons.content_cut_rounded,
                    size: 44,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    owner ? 'Salon partner sign in' : 'Customer sign in',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    owner
                        ? 'Your salon, team & bookings.'
                        : 'Your next salon visit starts here.',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  AuthLoginPanel(
                    role: role,
                    showBranding: false,
                    onLoggedIn: () => openAccountHome(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
