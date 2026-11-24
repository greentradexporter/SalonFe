import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../../widgets/brand_header.dart';
import '../../models/app_models.dart';
import '../../services/owner_alert_readiness.dart';
import '../../state/app_state.dart';
import '../../state/app_state_scope.dart';
import '../../theme/app_theme.dart';
import '../../utils/url_launcher_utils.dart';
import '../../widgets/app_error_dialog.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/account_actions.dart';
import '../../widgets/booking_extra_services.dart';
import '../entry/account_entry_screen.dart';
import '../entry/role_sign_in_screen.dart';
import 'salon_profile_setup_screen.dart';
import 'salon_balance_screen.dart';

class SalonDashboardScreen extends StatefulWidget {
  const SalonDashboardScreen({super.key});

  @override
  State<SalonDashboardScreen> createState() => _SalonDashboardScreenState();
}

class _SalonDashboardScreenState extends State<SalonDashboardScreen> {
  final GlobalKey<_OwnerBookingsState> _bookingsKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final appState = AppStateScope.watch(context);
    if (appState.hasActiveCustomerSession || appState.hasActiveBarberSession) {
      return const AppEntryScreen();
    }
    final salon = appState.ownerSalon;

    if (!appState.hasActiveOwnerSession) {
      return const _OwnerLoginGate();
    }
    if (appState.ownerSalonOrNull == null) {
      // Before the salon is known, "no salon in the list" is indistinguishable
      // from "this owner has no salon". Registration replaces the dashboard
      // and has nothing to pop back to, so never show it on a guess.
      // `ownerSalonResolved` is the direct per-owner read and is the one that
      // normally answers; the full list is only a second opinion.
      final known = appState.ownerSalonResolved || appState.salonsLoaded;
      if (!known) {
        if (appState.salonsLoadFailed) {
          // Never fall through to registration on a failed load: an owner who
          // does have a salon would be trapped on a screen they cannot leave.
          return _SalonLoadFailed(onRetry: appState.retrySalonsLoad);
        }
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return const SalonProfileSetupScreen();
    }
    return DefaultTabController(
      length: 3,
      child: Builder(
        builder: (dashboardContext) {
          final pendingNavigation = appState
              .takePendingNotificationNavigation();
          if (pendingNavigation != null) {
            _openNotificationDestination(
              dashboardContext,
              pendingNavigation.destination,
              bookingId: pendingNavigation.bookingId,
            );
          }
          return Scaffold(
            appBar: SalonFeAppBar(
              title: Text(
                salon.name.trim().isEmpty ? 'Salon dashboard' : salon.name,
              ),
              actions: [
                AccountOverflowMenu(
                  role: UserRole.owner,
                  canLogout: true,
                  onBalanceOpened: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SalonBalanceScreen(salonId: salon.id),
                    ),
                  ),
                  onNotificationOpened: (destination, {bookingId}) =>
                      _openNotificationDestination(
                        dashboardContext,
                        destination,
                        bookingId: bookingId,
                      ),
                  onLoggedOut: () async {
                    if (context.mounted) openAccountHome(context);
                  },
                ),
                const SizedBox(width: 8),
              ],
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Home'),
                  Tab(text: 'Bookings'),
                  Tab(text: 'Shop'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _OwnerRefresh(child: _OwnerOverview(salon: salon)),
                _OwnerRefresh(
                  child: _OwnerBookings(key: _bookingsKey, salonId: salon.id),
                ),
                const SalonProfileSetupScreen(embedded: true),
              ],
            ),
          );
        },
      ),
    );
  }

  int _dashboardTabFor(AppNotificationDestination destination) {
    return switch (destination) {
      AppNotificationDestination.overview => 0,
      AppNotificationDestination.bookings => 1,
      AppNotificationDestination.team => 2,
    };
  }

  void _openNotificationDestination(
    BuildContext dashboardContext,
    AppNotificationDestination destination, {
    String? bookingId,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!dashboardContext.mounted) {
        return;
      }
      DefaultTabController.of(
        dashboardContext,
      ).animateTo(_dashboardTabFor(destination));
      if (destination != AppNotificationDestination.bookings) {
        return;
      }
      _revealBookingWhenReady(bookingId?.trim() ?? '');
    });
  }

  void _revealBookingWhenReady(String bookingId, [int attempt = 0]) {
    final bookingsState = _bookingsKey.currentState;
    if (bookingsState != null) {
      bookingsState.showBooking(bookingId);
      return;
    }
    if (attempt >= 5 || !mounted) {
      return;
    }
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      if (mounted) {
        _revealBookingWhenReady(bookingId, attempt + 1);
      }
    });
  }
}

class _OwnerRefresh extends StatelessWidget {
  final Widget child;

  const _OwnerRefresh({required this.child});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => AppStateScope.read(context).refresh(),
      child: child,
    );
  }
}

class SalonRevenueDetailsScreen extends StatefulWidget {
  final String salonId;

  const SalonRevenueDetailsScreen({super.key, required this.salonId});

  @override
  State<SalonRevenueDetailsScreen> createState() =>
      _SalonRevenueDetailsScreenState();
}

class _SalonRevenueDetailsScreenState extends State<SalonRevenueDetailsScreen> {
  _RevenueRangePreset _preset = _RevenueRangePreset.thisMonth;
  DateTimeRange? _customRange;

  @override
  Widget build(BuildContext context) {
    final appState = AppStateScope.watch(context);
    final salon = appState.getSalon(widget.salonId);
    final completedBookings = appState
        .bookingsForSalon(widget.salonId)
        .where((booking) => booking.status == BookingStatus.completed)
        .toList(growable: false);
    final range = _selectedRange();
    final rangeBookings = completedBookings
        .where((booking) => range.contains(_bookingRevenueDate(booking)))
        .toList(growable: false);
    final totals = _RevenueTotals.fromBookings(rangeBookings);
    final weekly = _recentWeeklyRanges()
        .map(
          (item) => _RevenuePeriodSummary(
            label: item.label,
            totals: _RevenueTotals.fromBookings(
              completedBookings
                  .where(
                    (booking) => item.contains(_bookingRevenueDate(booking)),
                  )
                  .toList(growable: false),
            ),
          ),
        )
        .toList(growable: false);
    final monthly = _recentMonthlyRanges()
        .map(
          (item) => _RevenuePeriodSummary(
            label: item.label,
            totals: _RevenueTotals.fromBookings(
              completedBookings
                  .where(
                    (booking) => item.contains(_bookingRevenueDate(booking)),
                  )
                  .toList(growable: false),
            ),
          ),
        )
        .toList(growable: false);
    final serviceRows = _serviceRevenueRows(appState, rangeBookings);
    final barberRows = _barberRevenueRows(appState, rangeBookings);

    return Scaffold(
      appBar: SalonFeAppBar(title: const Text('Revenue details')),
      body: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
        children: [
          AppHeroHeader(
            eyebrow: salon == null
                ? 'Salon revenue'
                : 'Revenue at ${salon.displayName}',
            title: _money(totals.totalEarning),
            subtitle:
                '${totals.completedBookings} completed appointments · ${range.label}',
            icon: Icons.query_stats_outlined,
          ),
          const SizedBox(height: 14),
          _RevenueRangePicker(
            selected: _preset,
            rangeLabel: range.label,
            onSelected: (preset) async {
              if (preset == _RevenueRangePreset.custom) {
                await _pickCustomRange();
                return;
              }
              setState(() => _preset = preset);
            },
          ),
          const SizedBox(height: 14),
          GridView.count(
            shrinkWrap: true,
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.45,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _MetricCard(
                icon: Icons.payments_outlined,
                label: 'Salon earning',
                value: _money(totals.totalEarning),
                color: AppColors.success,
              ),
              _MetricCard(
                icon: Icons.receipt_long_outlined,
                label: 'Bookings',
                value: '${totals.completedBookings}',
                color: AppColors.primary,
              ),
              _MetricCard(
                icon: Icons.point_of_sale_outlined,
                label: 'Counter collection',
                value: _money(totals.customerCollection),
                color: AppColors.primaryDark,
              ),
              _MetricCard(
                icon: Icons.timeline_outlined,
                label: 'Avg order',
                value: _money(totals.averageOrderValue),
                color: AppColors.primary,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SalonEarningBreakdown(
            serviceValue: totals.serviceValue,
            customerCollection: totals.customerCollection,
            pritzeEarning: totals.pritzeContribution,
            discountSupport: totals.discountSupport,
            proinReimbursement: totals.proinReimbursement,
            totalEarning: totals.totalEarning,
          ),
          const SizedBox(height: 18),
          const SectionHeader(title: 'Week by week'),
          const SizedBox(height: 10),
          _RevenuePeriodCard(periods: weekly),
          const SizedBox(height: 18),
          const SectionHeader(title: 'Month by month'),
          const SizedBox(height: 10),
          _RevenuePeriodCard(periods: monthly),
          const SizedBox(height: 18),
          const SectionHeader(title: 'Revenue by service'),
          const SizedBox(height: 10),
          _RevenueRankedCard(
            emptyText: 'Completed service revenue will appear here.',
            rows: serviceRows,
          ),
          const SizedBox(height: 18),
          const SectionHeader(title: 'Revenue by barber'),
          const SizedBox(height: 10),
          _RevenueRankedCard(
            emptyText: 'Completed barber revenue will appear here.',
            rows: barberRows,
          ),
          const SizedBox(height: 18),
          const SectionHeader(title: 'Discount and Proin impact'),
          const SizedBox(height: 10),
          GlassCard(
            child: Column(
              children: [
                _EarningLine(
                  label: 'Customer discounts',
                  amount: totals.customerDiscount,
                  color: AppColors.danger,
                ),
                const SizedBox(height: 9),
                _EarningLine(
                  label: 'SalonFe discount support',
                  amount: totals.discountSupport,
                  color: AppColors.success,
                ),
                const SizedBox(height: 9),
                _EarningLine(
                  label: 'Reward reimbursement',
                  amount: totals.proinReimbursement,
                  color: AppColors.success,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1),
                ),
                _EarningLine(
                  label: 'Total SalonFe contribution',
                  amount: totals.pritzeContribution,
                  emphasized: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final initial =
        _customRange ??
        DateTimeRange(
          start: _startOfDay(now.subtract(const Duration(days: 6))),
          end: _startOfDay(now).add(const Duration(days: 1)),
        );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(
        start: _startOfDay(initial.start),
        end: _startOfDay(initial.end),
      ),
    );
    if (!mounted || picked == null) {
      return;
    }
    setState(() {
      _preset = _RevenueRangePreset.custom;
      _customRange = DateTimeRange(
        start: _startOfDay(picked.start),
        end: _startOfDay(picked.end).add(const Duration(days: 1)),
      );
    });
  }

  _RevenueDateRange _selectedRange() {
    final now = DateTime.now();
    final today = _startOfDay(now);
    return switch (_preset) {
      _RevenueRangePreset.today => _RevenueDateRange(
        label: 'Today',
        start: today,
        end: today.add(const Duration(days: 1)),
      ),
      _RevenueRangePreset.thisWeek => _RevenueDateRange(
        label: 'This week',
        start: _startOfWeek(now),
        end: _startOfWeek(now).add(const Duration(days: 7)),
      ),
      _RevenueRangePreset.thisMonth => _RevenueDateRange(
        label: 'This month',
        start: DateTime(now.year, now.month),
        end: DateTime(now.year, now.month + 1),
      ),
      _RevenueRangePreset.lastMonth => _RevenueDateRange(
        label: 'Last month',
        start: DateTime(now.year, now.month - 1),
        end: DateTime(now.year, now.month),
      ),
      _RevenueRangePreset.custom => _customRevenueRange(now),
    };
  }

  _RevenueDateRange _customRevenueRange(DateTime now) {
    final range =
        _customRange ??
        DateTimeRange(
          start: _startOfDay(now.subtract(const Duration(days: 6))),
          end: _startOfDay(now).add(const Duration(days: 1)),
        );
    return _RevenueDateRange(
      label:
          '${_shortDate(range.start)} – ${_shortDate(range.end.subtract(const Duration(days: 1)))}',
      start: range.start,
      end: range.end,
    );
  }
}

class _OwnerOverview extends StatelessWidget {
  final Salon salon;
  const _OwnerOverview({required this.salon});

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.watch(context);
    final entries =
        state
            .serviceRevenue(salon.id)
            .entries
            .where((e) => e.value > 0)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Total earnings',
                value: '₹${state.totalCollection(salon.id)}',
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                icon: Icons.today_outlined,
                label: 'Today’s earnings',
                value: '₹${state.dailyCollection(salon.id)}',
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        if (!salon.isApproved) ...[
          const SizedBox(height: 16),
          _SalonApprovalBanner(salon: salon),
        ],
        if (!state.isSalonSetupComplete(salon.id)) ...[
          const SizedBox(height: 16),
          _OwnerSetupBanner(salon: salon),
        ],
        const SizedBox(height: 16),
        const _OwnerAlertReadinessBanner(),
        _InstantBookingControl(salon: salon),
        const SizedBox(height: 24),
        const SectionHeader(title: 'Top services'),
        const SizedBox(height: 12),
        if (entries.isEmpty)
          const GlassCard(child: Text('Completed services appear here.'))
        else
          GlassCard(
            child: Column(
              children: [
                for (final entry in entries.take(8))
                  _ProgressRow(
                    label:
                        state.getService(salon.id, entry.key)?.name ??
                        'Booked service',
                    value: '₹${entry.value}',
                  ),
              ],
            ),
          ),
        const SizedBox(height: 24),
        FilledButton.icon(
          key: const ValueKey('owner-view-bookings'),
          onPressed: () => DefaultTabController.of(context).animateTo(1),
          icon: const Icon(Icons.calendar_month_outlined),
          label: const Text('View bookings'),
        ),
      ],
    );
  }
}

class _OwnerBookings extends StatefulWidget {
  final String salonId;
  const _OwnerBookings({super.key, required this.salonId});
  @override
  State<_OwnerBookings> createState() => _OwnerBookingsState();
}

class _OwnerBookingsState extends State<_OwnerBookings> {
  bool _historyExpanded = false;
  String? _highlightedId;
  late final Timer _clock;

  void showBooking(String? bookingId) {
    if (bookingId == null || bookingId.trim().isEmpty || !mounted) return;
    final state = AppStateScope.read(context);
    final booking = state
        .bookingsForSalon(widget.salonId)
        .where((b) => b.id == bookingId)
        .firstOrNull;
    if (booking == null) return;
    final bucket = state.salonBookingBucket(booking);
    setState(() {
      _highlightedId = bookingId;
      if (bucket == SalonBookingBucket.history ||
          bucket == SalonBookingBucket.cancelled) {
        _historyExpanded = true;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.watch(context);
    final now = DateTime.now();
    final all = state.bookingsForSalon(widget.salonId);
    List<Booking> section(
      Set<SalonBookingBucket> buckets, {
      bool reverse = false,
    }) {
      return all
          .where((b) => buckets.contains(state.salonBookingBucket(b, now: now)))
          .toList()
        ..sort((a, b) {
          if (a.id == _highlightedId) return -1;
          if (b.id == _highlightedId) return 1;
          return reverse
              ? b.start.compareTo(a.start)
              : a.start.compareTo(b.start);
        });
    }

    final requests = section({SalonBookingBucket.requests});
    final live = section({
      SalonBookingBucket.upcoming,
      SalonBookingBucket.active,
    });
    final history = section({
      SalonBookingBucket.history,
      SalonBookingBucket.cancelled,
    }, reverse: true);
    final today = all.where((b) => _isSameDay(b.start, now)).length;
    Widget card(Booking booking) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _OwnerBookingCard(
        booking: booking,
        bucket: state.salonBookingBucket(booking, now: now),
        outcome: state.salonBookingOutcome(booking, now: now),
        now: now,
        onBookingChanged: () {
          if (mounted) setState(() {});
        },
      ),
    );
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 28),
      children: [
        const Text(
          'All Bookings',
          style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            AppPill(label: 'Today · $today', color: AppColors.primaryDark),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'All appointments in one place',
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const SectionHeader(title: 'Needs Action'),
        const SizedBox(height: 12),
        if (requests.isEmpty)
          const _BookingSectionEmpty(
            icon: Icons.task_alt_rounded,
            text: 'No new requests',
          )
        else
          ...requests.map(card),
        const SizedBox(height: 20),
        const SectionHeader(title: 'Live Bookings'),
        const SizedBox(height: 12),
        if (live.isEmpty)
          const _BookingSectionEmpty(
            icon: Icons.event_available_outlined,
            text: 'No current bookings',
          )
        else
          ...live.map(card),
        const SizedBox(height: 18),
        ExpansionTile(
          key: ValueKey('owner-previous-bookings-$_historyExpanded'),
          initiallyExpanded: _historyExpanded,
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          title: Text(
            'Previous bookings (${history.length})',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          onExpansionChanged: (value) =>
              setState(() => _historyExpanded = value),
          children: _historyExpanded
              ? [
                  if (history.isEmpty)
                    const _BookingSectionEmpty(
                      icon: Icons.history,
                      text: 'No previous bookings',
                    )
                  else
                    ...history.map(card),
                ]
              : const [],
        ),
      ],
    );
  }
}

class _BookingSectionEmpty extends StatelessWidget {
  final IconData icon;
  final String text;
  const _BookingSectionEmpty({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Row(
      children: [
        Icon(icon, color: AppColors.muted, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: const TextStyle(color: AppColors.muted)),
        ),
      ],
    ),
  );
}

class _InstantBookingControl extends StatelessWidget {
  final Salon salon;

  const _InstantBookingControl({required this.salon});

  @override
  Widget build(BuildContext context) {
    final appState = AppStateScope.watch(context);
    final enabled = appState.isInstantBookingEnabled(salon.id);
    final isOpen = appState.isSalonCurrentlyOpen(salon.id);
    final color = enabled ? AppColors.primary : AppColors.muted;
    final status = enabled ? (isOpen ? 'On now' : 'On for opening') : 'Off';

    return GlassCard(
      color: enabled ? AppColors.primarySoft.withAlpha(92) : Colors.white,
      child: Row(
        children: [
          SoftIconBox(icon: Icons.bolt_outlined, color: color, size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Instant bookings',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AppPill(label: status, color: color),
                    AppPill(
                      label: isOpen ? 'Open' : 'Closed',
                      color: isOpen ? AppColors.primary : AppColors.muted,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (appState.isInstantBookingSaving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 13),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            )
          else
            Switch(
              key: const ValueKey('instant-booking-availability-switch'),
              value: enabled,
              activeThumbColor: AppColors.primary,
              onChanged: (value) async {
                try {
                  await appState.setOwnerInstantBookingEnabled(value);
                } catch (error) {
                  if (!context.mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        friendlyErrorMessage(
                          error,
                          fallback:
                              'Instant booking availability could not be updated. Try again.',
                        ),
                      ),
                    ),
                  );
                }
              },
            ),
        ],
      ),
    );
  }
}

class _OwnerBookingCard extends StatelessWidget {
  final Booking booking;
  final SalonBookingBucket bucket;
  final String outcome;
  final DateTime now;
  final VoidCallback onBookingChanged;
  const _OwnerBookingCard({
    required this.booking,
    required this.bucket,
    required this.outcome,
    required this.now,
    required this.onBookingChanged,
  });

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.watch(context);
    final service = state.getService(booking.salonId, booking.serviceId);
    final barber = state.getBarber(booking.barberId);
    final pending =
        booking.status == BookingStatus.pending &&
        bucket == SalonBookingBucket.requests;
    final live =
        bucket == SalonBookingBucket.upcoming ||
        bucket == SalonBookingBucket.active;
    final end = booking.start.add(Duration(minutes: booking.durationMinutes));
    final canStart =
        booking.status == BookingStatus.confirmed &&
        live &&
        (booking.isInstant || _isSameDay(now, booking.start)) &&
        now.isBefore(end);
    final accepted = booking.status == BookingStatus.confirmed;
    final progress = booking.status == BookingStatus.inProgress;
    final color = accepted || booking.status == BookingStatus.completed
        ? AppColors.success
        : (booking.status == BookingStatus.cancelled ||
              booking.status == BookingStatus.rejected)
        ? AppColors.danger
        : AppColors.primaryDark;
    final status = pending
        ? 'New Request'
        : accepted
        ? 'Accepted'
        : progress
        ? 'In Progress'
        : outcome;
    Widget action(
      BookingStatus status,
      String label,
      bool primary, {
      bool enabled = true,
    }) => _StatusButton(
      key: ValueKey('${booking.id}-${status.name}'),
      label: label,
      status: status,
      booking: booking,
      isPrimary: primary,
      enabled: enabled,
      onBookingChanged: onBookingChanged,
    );
    return Container(
      key: ValueKey('owner-booking-${booking.id}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: pending ? AppColors.primary : AppColors.line,
          width: pending ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  booking.customerName,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: _BookingStatusPill(
                  label: status,
                  color: color,
                  accepted: accepted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${booking.resolvedServiceName(service)} · ${barber?.name ?? 'Any barber'}',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${state.formatTime(booking.start)} · ₹${booking.customerPayableAmount}',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (!_isSameDay(now, booking.start))
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          state.formatDate(booking.start),
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (booking.customerPhone.trim().isNotEmpty)
                IconButton(
                  tooltip: 'Call customer',
                  icon: const Icon(Icons.call_outlined),
                  onPressed: () => UrlLauncherUtils.makePhoneCall(
                    context,
                    booking.customerPhone,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          if (pending)
            Row(
              children: [
                Expanded(
                  child: action(BookingStatus.rejected, 'Reject', false),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: action(BookingStatus.confirmed, 'Accept', true),
                ),
              ],
            )
          else ...[
            _SalonBookingTimeline(status: booking.status),
            if (accepted && live) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: action(
                  BookingStatus.inProgress,
                  'Start Service',
                  false,
                  enabled: canStart,
                ),
              ),
            ],
            if (progress) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: action(
                  BookingStatus.completed,
                  'Complete Service',
                  true,
                ),
              ),
            ],
          ],
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            title: const Text(
              'Booking details',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            children: [
              if (booking.isInstant && accepted)
                Text(
                  'Arrive by ${state.formatTime(booking.salonArrivalDeadline)}',
                  style: const TextStyle(color: AppColors.primaryDark),
                ),
              if (booking.cancellationReason.isNotEmpty)
                Text(booking.cancellationReason),
              BookingExtraServices(booking: booking),
              if (accepted && now.isBefore(end))
                action(BookingStatus.cancelled, 'Cancel booking', false),
              if (booking.status == BookingStatus.completed)
                OutlinedButton.icon(
                  key: ValueKey('rate-customer-${booking.id}'),
                  onPressed: () => _showCustomerRatingDialog(context),
                  icon: const Icon(Icons.star_outline_rounded),
                  label: const Text('Rate customer'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showCustomerRatingDialog(BuildContext pageContext) async {
    var rating = 5;
    var submitting = false;
    final noteController = TextEditingController();
    await showDialog<void>(
      context: pageContext,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Rate ${booking.customerName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'This rating is connected to the completed visit and will appear on the customer profile.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var index = 1; index <= 5; index++)
                    IconButton(
                      onPressed: submitting
                          ? null
                          : () => setDialogState(() => rating = index),
                      icon: Icon(
                        index <= rating
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: AppColors.primary,
                      ),
                      tooltip: '$index stars',
                    ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteController,
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Private visit note (optional)',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(dialogContext),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      setDialogState(() => submitting = true);
                      try {
                        await AppStateScope.read(
                          pageContext,
                        ).submitCustomerRating(
                          bookingId: booking.id,
                          rating: rating,
                          note: noteController.text,
                        );
                        if (!dialogContext.mounted || !pageContext.mounted) {
                          return;
                        }
                        Navigator.pop(dialogContext);
                        ScaffoldMessenger.of(pageContext).showSnackBar(
                          const SnackBar(
                            content: Text('Customer rating saved.'),
                          ),
                        );
                      } catch (error) {
                        if (!dialogContext.mounted) return;
                        setDialogState(() => submitting = false);
                        ScaffoldMessenger.of(pageContext).showSnackBar(
                          SnackBar(
                            content: Text(
                              friendlyErrorMessage(
                                error,
                                fallback:
                                    'The customer rating could not be saved. Try again.',
                              ),
                            ),
                          ),
                        );
                      }
                    },
              child: Text(submitting ? 'Saving...' : 'Save rating'),
            ),
          ],
        ),
      ),
    );
    noteController.dispose();
  }
}

class _JoinRequestCard extends StatefulWidget {
  final JoinRequest request;

  const _JoinRequestCard({required this.request});

  @override
  State<_JoinRequestCard> createState() => _JoinRequestCardState();
}

class _JoinRequestCardState extends State<_JoinRequestCard> {
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    final appState = AppStateScope.watch(context);
    final request = widget.request;
    final serviceNames = request.serviceIds
        .map((id) => appState.getService(request.salonId, id)?.name)
        .whereType<String>()
        .toList();
    final serviceSummary = serviceNames.isEmpty
        ? 'General grooming'
        : '${serviceNames.take(3).join(', ')}${serviceNames.length > 3 ? ' +${serviceNames.length - 3} more' : ''}';

    return GlassCard(
      color: AppColors.primarySoft.withAlpha(55),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.primaryDark.withAlpha(20),
                foregroundColor: AppColors.primaryDark,
                child: Text(
                  request.barberName.characters.first.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.barberName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      request.speciality,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const AppPill(
                icon: Icons.schedule,
                label: 'Pending',
                color: AppColors.primary,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(210),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              children: [
                _SmallDetail(
                  icon: Icons.workspace_premium_outlined,
                  label: '${request.experienceYears} years experience',
                ),
                _SmallDetail(icon: Icons.content_cut, label: serviceSummary),
                _SmallDetail(
                  icon: Icons.phone_outlined,
                  label: request.barberPhone,
                ),
                if (request.barberEmail.isNotEmpty)
                  _SmallDetail(
                    icon: Icons.alternate_email,
                    label: request.barberEmail,
                  ),
              ],
            ),
          ),
          if (request.resumeSummary.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              request.resumeSummary,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isProcessing
                      ? null
                      : () => _updateRequest(appState, accept: false),
                  icon: const Icon(Icons.close),
                  label: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _isProcessing
                      ? null
                      : () => _updateRequest(appState, accept: true),
                  icon: _isProcessing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.person_add_alt_1),
                  label: Text(_isProcessing ? 'Saving...' : 'Accept barber'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _updateRequest(AppState appState, {required bool accept}) async {
    setState(() => _isProcessing = true);
    try {
      if (accept) {
        await appState.approveJoinRequest(widget.request.id);
      } else {
        await appState.rejectJoinRequest(widget.request.id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              accept
                  ? 'Barber accepted and added to the team.'
                  : 'Request rejected.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyErrorMessage(
                error,
                fallback: accept
                    ? 'The join request could not be accepted. Try again.'
                    : 'The join request could not be rejected. Try again.',
              ),
            ),
          ),
        );
        setState(() => _isProcessing = false);
      }
    }
  }
}

class _OwnerLoginGate extends StatelessWidget {
  const _OwnerLoginGate();

  @override
  Widget build(BuildContext context) =>
      const RoleSignInScreen(role: UserRole.owner);
}

/// Warns the owner when this phone will not ring for a booking request.
///
/// Every blocker here fails silently: the request is sent, the alert is
/// posted, and the owner simply never hears it. Without this they cannot tell
/// a quiet evening from a phone that has stopped alerting them.
class _OwnerAlertReadinessBanner extends StatefulWidget {
  const _OwnerAlertReadinessBanner();

  @override
  State<_OwnerAlertReadinessBanner> createState() =>
      _OwnerAlertReadinessBannerState();
}

class _OwnerAlertReadinessBannerState extends State<_OwnerAlertReadinessBanner>
    with WidgetsBindingObserver {
  OwnerAlertReadiness? _readiness;

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
    // The owner fixes these in system settings and comes back, so re-check on
    // resume rather than leaving a warning up that they have already resolved.
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    try {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      final status = settings.authorizationStatus;
      final readiness = await OwnerAlertDeviceSettings.check(
        notificationsEnabled:
            status == AuthorizationStatus.authorized ||
            status == AuthorizationStatus.provisional,
        // Token registration is reported separately by the backend; this
        // banner covers what the owner can fix on the device itself.
        hasPushToken: true,
      );
      if (mounted) setState(() => _readiness = readiness);
    } catch (_) {
      // A readiness check must never take the dashboard down with it.
    }
  }

  Future<void> _fix(OwnerAlertBlocker blocker) async {
    final opened = switch (blocker) {
      OwnerAlertBlocker.fullScreenIntentDenied =>
        await OwnerAlertDeviceSettings.openFullScreenIntentSettings(),
      // Without a button here an owner whose notifications are off - the
      // default on Android 13+ - was told what was wrong and given no way
      // to fix it.
      OwnerAlertBlocker.notificationsDisabled =>
        await OwnerAlertDeviceSettings.openNotificationSettings(),
      // Restricted background is set on the same App info screen as battery.
      OwnerAlertBlocker.backgroundRestricted =>
        await OwnerAlertDeviceSettings.openBatteryOptimizationSettings(),
      OwnerAlertBlocker.alertChannelBlocked =>
        await OwnerAlertDeviceSettings.openAlertChannelSettings(),
      _ => false,
    };
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Open Settings, find SalonFe, and allow notifications and '
            'background activity.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final readiness = _readiness;
    if (readiness == null || readiness.isReady) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GlassCard(
        color: readiness.isSilent ? AppColors.primarySoft : AppColors.mint,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SoftIconBox(
                  icon: Icons.notifications_active_outlined,
                  color: AppColors.primary,
                  size: 44,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    readiness.isSilent
                        ? 'Booking requests cannot reach this phone'
                        : 'Booking requests may not ring on this phone',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final blocker in readiness.blockers) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      ownerAlertBlockerMessage(blocker),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                  if (blocker != OwnerAlertBlocker.noPushToken)
                    TextButton(
                      key: ValueKey('fix-owner-alert-${blocker.name}'),
                      onPressed: () => _fix(blocker),
                      child: const Text('Fix'),
                    ),
                ],
              ),
              const SizedBox(height: 4),
            ],
          ],
        ),
      ),
    );
  }
}

class _SalonApprovalBanner extends StatelessWidget {
  final Salon salon;

  const _SalonApprovalBanner({required this.salon});

  @override
  Widget build(BuildContext context) {
    final pending = salon.isPendingApproval;
    final color = pending ? AppColors.primary : AppColors.danger;
    return GlassCard(
      color: pending ? AppColors.primarySoft : AppColors.mint,
      child: Row(
        children: [
          SoftIconBox(
            icon: pending ? Icons.hourglass_top_rounded : Icons.info_outline,
            color: color,
            size: 44,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pending
                      ? 'Salon review in progress'
                      : 'Salon listing needs review',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  pending
                      ? 'Your salon is saved and waiting for SalonFe approval. It is not visible to customers and cannot receive bookings yet.'
                      : 'Your salon is not visible to customers. Please contact SalonFe support if you need help with the review.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.primaryDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OwnerSetupBanner extends StatelessWidget {
  final Salon salon;

  const _OwnerSetupBanner({required this.salon});

  @override
  Widget build(BuildContext context) {
    final appState = AppStateScope.watch(context);
    final missingItems = appState.missingSalonSetupItems(salon.id);
    final opensTeam = _setupActionOpensTeam(missingItems);

    return GlassCard(
      color: AppColors.mint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SoftIconBox(
                icon: Icons.assignment_outlined,
                color: AppColors.primary,
                size: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Complete the remaining salon setup',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('complete-salon-setup-action'),
                onPressed: () => _openRemainingSetup(context, missingItems),
                icon: const Icon(Icons.arrow_forward),
                tooltip: opensTeam
                    ? 'Complete shop setup'
                    : 'Complete salon setup',
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Your salon remains visible to customers. Complete these items so the profile and booking experience are fully ready.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.primaryDark),
          ),
          const SizedBox(height: 12),
          for (final item in missingItems)
            _SetupCheckRow(done: false, label: item),
        ],
      ),
    );
  }

  bool _setupActionOpensTeam(List<String> missingItems) => true;

  void _openRemainingSetup(BuildContext context, List<String> missingItems) {
    final tabs = DefaultTabController.maybeOf(context);
    if (tabs != null) {
      tabs.animateTo(2);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SalonProfileSetupScreen()),
    );
  }
}

class _SetupCheckRow extends StatelessWidget {
  final bool done;
  final String label;

  const _SetupCheckRow({required this.done, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            color: done ? AppColors.success : AppColors.muted,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.primaryDark,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SalonEarningBreakdown extends StatelessWidget {
  final int serviceValue;
  final int customerCollection;
  final int pritzeEarning;
  final int discountSupport;
  final int proinReimbursement;
  final int totalEarning;

  const _SalonEarningBreakdown({
    required this.serviceValue,
    required this.customerCollection,
    required this.pritzeEarning,
    required this.discountSupport,
    required this.proinReimbursement,
    required this.totalEarning,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              SoftIconBox(
                icon: Icons.account_balance_wallet_outlined,
                color: AppColors.primary,
                size: 42,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Earning breakdown',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _EarningLine(label: 'Service value', amount: serviceValue),
          const SizedBox(height: 9),
          _EarningLine(
            label: 'Collected from customers',
            amount: customerCollection,
          ),
          const SizedBox(height: 9),
          _EarningLine(
            label: 'SalonFe earning',
            amount: pritzeEarning,
            color: AppColors.success,
          ),
          if (pritzeEarning > 0) ...[
            const SizedBox(height: 7),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Column(
                children: [
                  _EarningLine(
                    label: 'Discount support',
                    amount: discountSupport,
                    color: AppColors.success,
                  ),
                  const SizedBox(height: 7),
                  _EarningLine(
                    label: 'Reward reimbursement',
                    amount: proinReimbursement,
                    color: AppColors.success,
                  ),
                ],
              ),
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),
          _EarningLine(
            label: 'Total salon earning',
            amount: totalEarning,
            emphasized: true,
          ),
        ],
      ),
    );
  }
}

class _EarningLine extends StatelessWidget {
  final String label;
  final int amount;
  final Color? color;
  final bool emphasized;

  const _EarningLine({
    required this.label,
    required this.amount,
    this.color,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: color ?? AppColors.ink,
              fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
        Text(
          '₹$amount',
          style: TextStyle(
            color: color ?? AppColors.ink,
            fontSize: emphasized ? 19 : 14,
            fontWeight: emphasized ? FontWeight.w800 : FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

enum _RevenueRangePreset { today, thisWeek, thisMonth, lastMonth, custom }

class _RevenueRangePicker extends StatelessWidget {
  final _RevenueRangePreset selected;
  final String rangeLabel;
  final ValueChanged<_RevenueRangePreset> onSelected;

  const _RevenueRangePicker({
    required this.selected,
    required this.rangeLabel,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rangeLabel,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final preset in _RevenueRangePreset.values) ...[
                  ChoiceChip(
                    selected: selected == preset,
                    label: Text(_revenuePresetLabel(preset)),
                    onSelected: (_) => onSelected(preset),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RevenueDateRange {
  final String label;
  final DateTime start;
  final DateTime end;

  const _RevenueDateRange({
    required this.label,
    required this.start,
    required this.end,
  });

  bool contains(DateTime value) =>
      !value.isBefore(start) && value.isBefore(end);
}

class _RevenueTotals {
  final int completedBookings;
  final int serviceValue;
  final int customerCollection;
  final int customerDiscount;
  final int discountSupport;
  final int proinReimbursement;
  final int pritzeContribution;
  final int totalEarning;

  const _RevenueTotals({
    required this.completedBookings,
    required this.serviceValue,
    required this.customerCollection,
    required this.customerDiscount,
    required this.discountSupport,
    required this.proinReimbursement,
    required this.pritzeContribution,
    required this.totalEarning,
  });

  factory _RevenueTotals.fromBookings(List<Booking> bookings) {
    return _RevenueTotals(
      completedBookings: bookings.length,
      serviceValue: bookings.fold(
        0,
        (total, booking) => total + _bookingOriginalValue(booking),
      ),
      customerCollection: bookings.fold(
        0,
        (total, booking) => total + booking.customerPayableAmount,
      ),
      customerDiscount: bookings.fold(
        0,
        (total, booking) => total + booking.discountAmount,
      ),
      discountSupport: bookings.fold(
        0,
        (total, booking) => total + booking.pritzePayoutAmount,
      ),
      proinReimbursement: bookings.fold(
        0,
        (total, booking) => total + booking.proinRedeemedAmount,
      ),
      pritzeContribution: bookings.fold(
        0,
        (total, booking) => total + booking.totalPritzeContribution,
      ),
      totalEarning: bookings.fold(
        0,
        (total, booking) => total + booking.salonTotalEarning,
      ),
    );
  }

  int get averageOrderValue =>
      completedBookings == 0 ? 0 : (totalEarning / completedBookings).round();
}

class _RevenuePeriodSummary {
  final String label;
  final _RevenueTotals totals;

  const _RevenuePeriodSummary({required this.label, required this.totals});
}

class _RevenuePeriodCard extends StatelessWidget {
  final List<_RevenuePeriodSummary> periods;

  const _RevenuePeriodCard({required this.periods});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        children: [
          for (var index = 0; index < periods.length; index++) ...[
            _RevenuePeriodRow(summary: periods[index]),
            if (index != periods.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1),
              ),
          ],
        ],
      ),
    );
  }
}

class _RevenuePeriodRow extends StatelessWidget {
  final _RevenuePeriodSummary summary;

  const _RevenuePeriodRow({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                summary.label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(
                '${summary.totals.completedBookings} completed · ${_money(summary.totals.customerCollection)} counter',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        Text(
          _money(summary.totals.totalEarning),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _RevenueRankedRow {
  final String label;
  final int amount;
  final int count;

  const _RevenueRankedRow({
    required this.label,
    required this.amount,
    required this.count,
  });
}

class _RevenueRankedCard extends StatelessWidget {
  final String emptyText;
  final List<_RevenueRankedRow> rows;

  const _RevenueRankedCard({required this.emptyText, required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return GlassCard(child: Text(emptyText));
    }
    final maxAmount = rows
        .map((row) => row.amount)
        .fold<int>(0, (max, amount) => amount > max ? amount : max);
    return GlassCard(
      child: Column(
        children: [
          for (var index = 0; index < rows.take(10).length; index++) ...[
            _RevenueRankedTile(row: rows[index], maxAmount: maxAmount),
            if (index != rows.take(10).length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1),
              ),
          ],
        ],
      ),
    );
  }
}

class _RevenueRankedTile extends StatelessWidget {
  final _RevenueRankedRow row;
  final int maxAmount;

  const _RevenueRankedTile({required this.row, required this.maxAmount});

  @override
  Widget build(BuildContext context) {
    final fraction = maxAmount <= 0 ? 0.0 : row.amount / maxAmount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                row.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              _money(row.amount),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 5),
        LinearProgressIndicator(
          value: fraction.clamp(0.0, 1.0),
          minHeight: 6,
          borderRadius: BorderRadius.circular(99),
          backgroundColor: AppColors.canvas,
          color: AppColors.primary,
        ),
        const SizedBox(height: 5),
        Text(
          '${row.count} completed',
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      ],
    );
  }
}

DateTime _bookingRevenueDate(Booking booking) =>
    booking.completedAt ?? booking.start;

int _bookingOriginalValue(Booking booking) {
  final breakdownTotal = booking.servicePriceBreakdown.values.fold<int>(
    0,
    (total, price) => total + price,
  );
  return breakdownTotal > 0 ? breakdownTotal : booking.servicePrice;
}

List<_RevenueRankedRow> _serviceRevenueRows(
  AppState appState,
  List<Booking> bookings,
) {
  final amounts = <String, int>{};
  final counts = <String, int>{};
  for (final booking in bookings) {
    final breakdown = booking.servicePriceBreakdown.isNotEmpty
        ? booking.servicePriceBreakdown
        : <String, int>{booking.serviceId: booking.servicePrice};
    final originalTotal = breakdown.values.fold<int>(
      0,
      (total, price) => total + price,
    );
    if (originalTotal <= 0 || booking.salonTotalEarning <= 0) {
      continue;
    }
    var assigned = 0;
    final entries = breakdown.entries.toList(growable: false);
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      final amount = index == entries.length - 1
          ? booking.salonTotalEarning - assigned
          : (booking.salonTotalEarning * entry.value / originalTotal).floor();
      assigned += amount;
      final serviceName =
          appState.getService(booking.salonId, entry.key)?.name ??
          (entries.length == 1
              ? booking.resolvedServiceName()
              : 'Booked service');
      amounts[serviceName] = (amounts[serviceName] ?? 0) + amount;
      counts[serviceName] = (counts[serviceName] ?? 0) + 1;
    }
  }
  return amounts.entries
      .map(
        (entry) => _RevenueRankedRow(
          label: entry.key,
          amount: entry.value,
          count: counts[entry.key] ?? 0,
        ),
      )
      .toList(growable: false)
    ..sort((left, right) => right.amount.compareTo(left.amount));
}

List<_RevenueRankedRow> _barberRevenueRows(
  AppState appState,
  List<Booking> bookings,
) {
  final amounts = <String, int>{};
  final counts = <String, int>{};
  for (final booking in bookings) {
    if (booking.salonTotalEarning <= 0) {
      continue;
    }
    final barberName = booking.barberId.trim().isEmpty
        ? 'Any available barber'
        : appState.getBarber(booking.barberId)?.name ?? 'Former team member';
    amounts[barberName] =
        (amounts[barberName] ?? 0) + booking.salonTotalEarning;
    counts[barberName] = (counts[barberName] ?? 0) + 1;
  }
  return amounts.entries
      .map(
        (entry) => _RevenueRankedRow(
          label: entry.key,
          amount: entry.value,
          count: counts[entry.key] ?? 0,
        ),
      )
      .toList(growable: false)
    ..sort((left, right) => right.amount.compareTo(left.amount));
}

List<_RevenueDateRange> _recentWeeklyRanges() {
  final currentWeekStart = _startOfWeek(DateTime.now());
  return List.generate(8, (index) {
    final start = currentWeekStart.subtract(Duration(days: index * 7));
    final end = start.add(const Duration(days: 7));
    return _RevenueDateRange(
      label: index == 0
          ? 'This week'
          : '${_shortDate(start)} – ${_shortDate(end.subtract(const Duration(days: 1)))}',
      start: start,
      end: end,
    );
  });
}

List<_RevenueDateRange> _recentMonthlyRanges() {
  final now = DateTime.now();
  return List.generate(6, (index) {
    final start = DateTime(now.year, now.month - index);
    final end = DateTime(now.year, now.month - index + 1);
    return _RevenueDateRange(
      label: index == 0 ? 'This month' : _monthYear(start),
      start: start,
      end: end,
    );
  });
}

DateTime _startOfDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime _startOfWeek(DateTime value) {
  final day = _startOfDay(value);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

String _revenuePresetLabel(_RevenueRangePreset preset) => switch (preset) {
  _RevenueRangePreset.today => 'Today',
  _RevenueRangePreset.thisWeek => 'This week',
  _RevenueRangePreset.thisMonth => 'This month',
  _RevenueRangePreset.lastMonth => 'Last month',
  _RevenueRangePreset.custom => 'Custom',
};

String _money(int amount) => '₹$amount';

String _shortDate(DateTime date) => '${date.day} ${_monthName(date.month)}';

String _monthYear(DateTime date) => '${_monthName(date.month)} ${date.year}';

String _monthName(int month) => const [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
][month.clamp(1, 12) - 1];

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SoftIconBox(icon: icon, color: color, size: 40),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  final String label;
  final String value;

  const _ProgressRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallDetail extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SmallDetail({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusButton extends StatefulWidget {
  final String label;
  final BookingStatus status;
  final Booking booking;
  final bool isPrimary;
  final bool enabled;
  final VoidCallback? onBookingChanged;

  const _StatusButton({
    super.key,
    required this.label,
    required this.status,
    required this.booking,
    this.isPrimary = false,
    this.enabled = true,
    this.onBookingChanged,
  });

  @override
  State<_StatusButton> createState() => _StatusButtonState();
}

class _StatusButtonState extends State<_StatusButton> {
  bool _submitted = false;

  @override
  Widget build(BuildContext context) {
    final appState = AppStateScope.watch(context);
    final onPressed =
        !widget.enabled ||
            _submitted ||
            widget.booking.status == widget.status ||
            appState.isBookingStatusUpdatePending(widget.booking.id)
        ? null
        : () {
            setState(() => _submitted = true);
            final isInstantDecision =
                widget.booking.isInstant &&
                widget.booking.status == BookingStatus.pending &&
                (widget.status == BookingStatus.confirmed ||
                    widget.status == BookingStatus.rejected);
            if (isInstantDecision) {
              appState.silenceOwnerBookingAlert(widget.booking.id);
            }
            final update = appState.updateBookingStatus(
              widget.booking.id,
              widget.status,
              cancelledBy: widget.status == BookingStatus.cancelled
                  ? 'salon'
                  : null,
            );
            widget.onBookingChanged?.call();
            unawaited(
              update
                  .then((_) {
                    widget.onBookingChanged?.call();
                    if (!context.mounted) {
                      return;
                    }
                    if (widget.status != BookingStatus.completed) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Service completed. ₹${widget.booking.salonTotalEarning} total earning added, including ₹${widget.booking.totalPritzeContribution} from SalonFe.',
                        ),
                      ),
                    );
                  })
                  .catchError((Object error) {
                    widget.onBookingChanged?.call();
                    if (!context.mounted) {
                      return;
                    }
                    setState(() => _submitted = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          friendlyErrorMessage(
                            error,
                            fallback:
                                'The booking status could not be updated. Try again.',
                          ),
                        ),
                      ),
                    );
                  }),
            );
          };
    final actionLabel = _submitted
        ? _pendingLabel(widget.status)
        : widget.label;
    final actionIcon = _submitted
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : null;
    if (widget.isPrimary) {
      return FilledButton(
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [?actionIcon, Text(actionLabel)],
        ),
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor:
            widget.status == BookingStatus.rejected ||
                widget.status == BookingStatus.cancelled
            ? AppColors.danger
            : AppColors.ink,
        side: BorderSide(
          color: widget.status == BookingStatus.rejected
              ? AppColors.line
              : AppColors.primary,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [?actionIcon, Text(actionLabel)],
      ),
    );
  }

  String _pendingLabel(BookingStatus status) => switch (status) {
    BookingStatus.confirmed => 'Accepting...',
    BookingStatus.rejected => 'Rejecting...',
    BookingStatus.cancelled => 'Cancelling...',
    BookingStatus.inProgress => 'Starting...',
    BookingStatus.completed => 'Completing...',
    BookingStatus.pending => 'Updating...',
  };
}

class _SalonLoadFailed extends StatelessWidget {
  const _SalonLoadFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SalonFeAppBar(title: const Text('Salon dashboard')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 40),
              const SizedBox(height: 12),
              Text(
                'Could not load your salon',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Check your internet connection and try again.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const ValueKey('retry-salon-load'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SalonBookingTimeline extends StatelessWidget {
  final BookingStatus status;
  const _SalonBookingTimeline({required this.status});
  @override
  Widget build(BuildContext context) {
    final step = switch (status) {
      BookingStatus.confirmed => 2,
      BookingStatus.inProgress => 3,
      BookingStatus.completed => 4,
      _ => 1,
    };
    final color = status == BookingStatus.inProgress
        ? AppColors.primary
        : AppColors.success;
    const labels = ['Booked', 'Accepted', 'Started', 'Done'];
    return Row(
      children: [
        for (var i = 0; i < 4; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == 3 ? 0 : 3),
              child: Column(
                children: [
                  Container(
                    height: 5,
                    decoration: BoxDecoration(
                      color: i < step ? color : AppColors.line,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 11,
                      color: i < step ? color : AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class _BookingStatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final bool accepted;
  const _BookingStatusPill({
    required this.label,
    required this.color,
    this.accepted = false,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: color.withAlpha(22),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (accepted) ...[
          Icon(Icons.check, size: 17, color: color),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ],
    ),
  );
}
