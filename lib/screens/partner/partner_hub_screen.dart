import 'package:flutter/material.dart';

import '../salon/salon_dashboard_screen.dart';

/// Kept as a compatibility entry for existing route callers. The welcome
/// choice now goes directly to partner authentication, without customer tabs.
class PartnerHubScreen extends StatelessWidget {
  const PartnerHubScreen({super.key});

  @override
  Widget build(BuildContext context) => const SalonDashboardScreen();
}
