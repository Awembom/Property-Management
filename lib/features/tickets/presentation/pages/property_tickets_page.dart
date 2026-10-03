import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/tickets/data/ticket.dart';
import 'package:rental_app/features/tickets/presentation/widgets/ticket_tile.dart';
import 'package:rental_app/features/tickets/providers/tickets_providers.dart';
import 'package:rental_app/shared/widgets/async_error_view.dart';
import 'package:rental_app/shared/widgets/empty_state.dart';

/// The team's list of tickets for a property, open ones first by default.
class PropertyTicketsPage extends ConsumerStatefulWidget {
  const PropertyTicketsPage({super.key, required this.propertyId});

  final String propertyId;

  @override
  ConsumerState<PropertyTicketsPage> createState() => _PropertyTicketsPageState();
}

class _PropertyTicketsPageState extends ConsumerState<PropertyTicketsPage> {
  /// null = all statuses.
  TicketStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final tickets = ref.watch(propertyTicketsProvider(widget.propertyId));
    return Scaffold(
      appBar: AppBar(title: const Text('Tickets')),
      body: tickets.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AsyncErrorView(
          error: error,
          onRetry: () => ref.invalidate(propertyTicketsProvider(widget.propertyId)),
        ),
        data: (all) {
          final shown = all.where((t) => _filter == null || t.status == _filter).toList();
          return RefreshIndicator(
            onRefresh: () => ref.refresh(propertyTicketsProvider(widget.propertyId).future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final status in [null, ...TicketStatus.values])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(status == null
                                ? 'All (${all.length})'
                                : '${status.label} (${all.where((t) => t.status == status).length})'),
                            selected: _filter == status,
                            onSelected: (_) => setState(() => _filter = status),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (all.isEmpty)
                  const EmptyState(
                    icon: Icons.build_circle_rounded,
                    color: AppColors.accent,
                    title: 'No tickets',
                    message: 'When tenants report an issue in the app, it appears here.',
                  )
                else if (shown.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('Nothing here.', textAlign: TextAlign.center),
                  ),
                for (final ticket in shown)
                  Padding(padding: const EdgeInsets.only(bottom: 10), child: TicketTile(ticket: ticket)),
              ],
            ),
          );
        },
      ),
    );
  }
}
