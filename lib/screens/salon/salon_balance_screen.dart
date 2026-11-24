import 'package:flutter/material.dart';
import '../../models/app_models.dart';
import '../../state/app_state_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/brand_header.dart';
import '../../widgets/app_ui.dart';

class SalonBalanceScreen extends StatefulWidget {
  final String salonId;
  const SalonBalanceScreen({super.key, required this.salonId});
  @override
  State<SalonBalanceScreen> createState() => _SalonBalanceScreenState();
}

class _SalonBalanceScreenState extends State<SalonBalanceScreen> {
  Future<SalonBalanceSummary>? _summary;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _summary ??= AppStateScope.read(context).loadSalonBalance(widget.salonId);
  }

  void _refresh() {
    final summary = AppStateScope.read(
      context,
    ).loadSalonBalance(widget.salonId);
    setState(() {
      _summary = summary;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: SalonFeAppBar(
      title: const Text('Balance'),
      actions: [
        IconButton(
          onPressed: _refresh,
          tooltip: 'Refresh balance',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<SalonBalanceSummary>(
      future: _summary,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 40),
                const SizedBox(height: 12),
                const Text('Could not load balance'),
                TextButton(onPressed: _refresh, child: const Text('Try again')),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final summary = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            _amount(
              'Deposit amount',
              summary.deposit,
              Icons.account_balance_outlined,
            ),
            _amount('Discount', summary.discount, Icons.local_offer_outlined),
            _amount(
              'Balance',
              summary.balance,
              Icons.account_balance_wallet_outlined,
              highlighted: true,
            ),
            _amount(
              'SalonFe earning',
              summary.earning,
              Icons.payments_outlined,
            ),
          ],
        );
      },
    ),
  );
  Widget _amount(
    String label,
    int value,
    IconData icon, {
    bool highlighted = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: GlassCard(
      color: highlighted ? AppColors.primarySoft : Colors.white,
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            '₹$value',
            style: TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w800,
              color: value < 0 ? AppColors.danger : AppColors.ink,
            ),
          ),
        ],
      ),
    ),
  );
}
