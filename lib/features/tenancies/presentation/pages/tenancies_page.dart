import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/dashboard/data/dashboard.dart';
import 'package:rental_app/features/dashboard/providers/dashboard_providers.dart';
import 'package:rental_app/features/tenancies/data/rent_status.dart';
import 'package:rental_app/features/tenancies/data/tenancy.dart';
import 'package:rental_app/features/tenancies/presentation/widgets/tenancy_row.dart';
import 'package:rental_app/shared/widgets/async_error_view.dart';
import 'package:rental_app/shared/widgets/empty_state.dart';

/// Which tenants the Tenants tab shows.
enum _Filter {
  all('All'),
  overdue('Overdue'),
  dueSoon('Due soon'),
  paid('Paid');

  const _Filter(this.label);
  final String label;

  bool matches(TenancyOverview t) => switch (this) {
        _Filter.all => true,
        _Filter.overdue => t.rentStatus == RentStatus.overdue,
        _Filter.dueSoon => t.rentStatus == RentStatus.dueSoon,
        _Filter.paid => t.rentStatus == RentStatus.paid,
      };
}

/// The Tenants tab: everyone currently renting in my properties, the ones
/// who need attention first. Search by name, unit or property.
class TenanciesPage extends ConsumerStatefulWidget {
  const TenanciesPage({super.key});

  @override
  ConsumerState<TenanciesPage> createState() => _TenanciesPageState();
}

class _TenanciesPageState extends ConsumerState<TenanciesPage> {
  // Local UI state only, so setState is fine.
  String _search = '';
  _Filter _filter = _Filter.all;

  List<TenancyOverview> _shown(Dashboard d) {
    final query = _search.trim().toLowerCase();
    int rank(TenancyOverview t) => switch (t.rentStatus) {
          RentStatus.overdue => 0,
          RentStatus.dueSoon => 1,
          _ => 2,
        };
    return d.active
        .where(_filter.matches)
        .where((t) =>
            query.isEmpty ||
            t.tenantName.toLowerCase().contains(query) ||
            t.apartmentName.toLowerCase().contains(query) ||
            d.propertyName(t.propertyId).toLowerCase().contains(query))
        .toList()
      ..sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        return byRank != 0 ? byRank : a.paidUntil.compareTo(b.paidUntil);
      });
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(dashboardProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Tenants')),
      body: dashboard.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            AsyncErrorView(error: error, onRetry: () => ref.invalidate(dashboardProvider)),
        data: (d) {
          final shown = _shown(d);
          return RefreshIndicator(
            onRefresh: () => ref.refresh(dashboardProvider.future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                TextField(
                  onChanged: (value) => setState(() => _search = value),
                  decoration: const InputDecoration(
                    hintText: 'Search tenant, unit or property',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final filter in _Filter.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(filter.label),
                            selected: _filter == filter,
                            onSelected: (_) => setState(() => _filter = filter),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (d.active.isEmpty)
                  const EmptyState(
                    icon: Icons.people_alt_rounded,
                    color: AppColors.accent,
                    title: 'No tenants yet',
                    message: 'Start a tenancy from an apartment and the tenant appears here.',
                  )
                else if (shown.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('Nobody matches.', textAlign: TextAlign.center),
                  ),
                for (final tenancy in shown)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TenancyRow(tenancy: tenancy, propertyName: d.propertyName(tenancy.propertyId)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
