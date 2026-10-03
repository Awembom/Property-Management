import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/tickets/data/ticket.dart';
import 'package:rental_app/shared/utils/dates.dart';
import 'package:rental_app/shared/widgets/app_card.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';
import 'package:rental_app/shared/widgets/status_pill.dart';

/// One ticket in a list: category icon, title, where/when, status.
class TicketTile extends StatelessWidget {
  const TicketTile({super.key, required this.ticket});

  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final where = [
      if (ticket.apartmentName != null) 'Unit ${ticket.apartmentName}',
      if (ticket.tenantName != null) ticket.tenantName!,
      formatDate(ticket.createdAt),
    ].join(' · ');
    return AppCard(
      padding: const EdgeInsets.all(12),
      onTap: ticket.pending
          // Not on the server yet, so there's nothing to open.
          ? () => showMessage(context, 'This issue will be sent when you\'re back online.')
          : () => context.push(AppRoutes.ticket(ticket.id)),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.soft(ticket.status.color)),
            child: Icon(ticket.category.icon, color: ticket.status.color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ticket.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (ticket.pending)
            const StatusPill(label: 'Waiting to send', color: AppColors.muted, icon: Icons.schedule_rounded)
          else
            StatusPill(label: ticket.status.label, color: ticket.status.color, icon: ticket.status.icon),
        ],
      ),
    );
  }
}
