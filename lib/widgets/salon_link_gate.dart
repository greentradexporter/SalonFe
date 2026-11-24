import 'dart:async';
import 'package:flutter/material.dart';
import '../services/salon_link_service.dart';
import '../state/app_state_scope.dart';
import '../screens/customer/salon_detail_screen.dart';
import 'brand_header.dart';
import 'customer_location_gate.dart';

class SalonLinkGate extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  const SalonLinkGate({
    super.key,
    required this.navigatorKey,
    required this.child,
  });
  @override
  State<SalonLinkGate> createState() => _SalonLinkGateState();
}

class _SalonLinkGateState extends State<SalonLinkGate> {
  bool _opening = false;
  String? _ownerNotice;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
    valueListenable: SalonLinkService.pendingSalonId,
    builder: (context, id, _) {
      final state = AppStateScope.watch(context);
      if (id != null && !_opening && !state.isRestoringSession) {
        if (state.hasActiveOwnerSession || state.hasActiveBarberSession) {
          if (_ownerNotice != id) {
            _ownerNotice = id;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final context = widget.navigatorKey.currentContext;
              if (context != null && context.mounted) {
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  const SnackBar(
                    content: Text('Open salon links from a customer account.'),
                  ),
                );
              }
            });
          }
        } else if (!state.referralOnboardingRequired) {
          _opening = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final navigator = widget.navigatorKey.currentState;
            if (!mounted || navigator == null) {
              _opening = false;
              return;
            }
            if (!state.hasActiveCustomerSession) state.browseAsGuest();
            unawaited(
              navigator.push(
                MaterialPageRoute<void>(
                  builder: (_) => SharedSalonScreen(salonId: id),
                ),
              ),
            );
            try {
              await SalonLinkService.clear(id);
            } catch (_) {
              // The in-memory intent is already cleared; optional storage must not block navigation.
            } finally {
              _opening = false;
            }
          });
        }
      }
      return widget.child;
    },
  );
}

class SharedSalonScreen extends StatelessWidget {
  final String salonId;
  const SharedSalonScreen({super.key, required this.salonId});
  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.watch(context);
    final salon = state.getSalon(salonId);
    if (salon != null && salon.isApproved) {
      return CustomerLocationGate(child: SalonDetailScreen(salonId: salonId));
    }
    return Scaffold(
      appBar: SalonFeAppBar(title: const Text('Salon')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: !state.salonsLoaded && !state.salonsLoadFailed
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.storefront_outlined, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      state.salonsLoadFailed
                          ? 'Could not load this salon'
                          : 'This salon is not available',
                    ),
                    if (state.salonsLoadFailed)
                      TextButton(
                        onPressed: state.retrySalonsLoad,
                        child: const Text('Try again'),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
