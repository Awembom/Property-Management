import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/offline/outbox.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/properties/providers/properties_providers.dart';
import 'package:rental_app/features/tickets/data/ticket.dart';
import 'package:rental_app/features/tickets/data/tickets_repository.dart';
import 'package:rental_app/features/tickets/providers/tickets_providers.dart';
import 'package:rental_app/shared/utils/dates.dart';
import 'package:rental_app/shared/widgets/app_card.dart';
import 'package:rental_app/shared/widgets/async_error_view.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';
import 'package:rental_app/shared/widgets/status_pill.dart';

/// One ticket: the issue, its status (the team can change it) and the
/// conversation between tenant and team.
class TicketPage extends ConsumerStatefulWidget {
  const TicketPage({super.key, required this.ticketId});

  final String ticketId;

  @override
  ConsumerState<TicketPage> createState() => _TicketPageState();
}

class _TicketPageState extends ConsumerState<TicketPage> {
  final _replyController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  void _reload(Ticket ticket) {
    ref.invalidate(ticketProvider(widget.ticketId));
    ref.invalidate(ticketMessagesProvider(widget.ticketId));
    ref.invalidate(propertyTicketsProvider(ticket.propertyId));
    ref.invalidate(tenancyTicketsProvider(ticket.tenancyId));
  }

  Future<void> _send(Ticket ticket) async {
    final body = _replyController.text.trim();
    if (body.isEmpty) return;
    setState(() => _busy = true);
    try {
      // Offline, it waits in the outbox and is sent automatically later.
      final sent = await ref
          .read(outboxProvider.notifier)
          .sendOrQueue(OutboxItem.ticketMessage(ticketId: ticket.id, body: body));
      _replyController.clear();
      if (sent) _reload(ticket);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatus(Ticket ticket, TicketStatus status) async {
    try {
      await ref.read(ticketsRepositoryProvider).setStatus(ticket.id, status);
      _reload(ticket);
      if (mounted) showMessage(context, 'Marked "${status.label}"');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ticketValue = ref.watch(ticketProvider(widget.ticketId));
    final sentMessages = ref.watch(ticketMessagesProvider(widget.ticketId)).value ?? const <TicketMessage>[];
    final pending = ref.watch(pendingMessagesProvider(widget.ticketId));
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Ticket')),
      body: ticketValue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            AsyncErrorView(error: error, onRetry: () => ref.invalidate(ticketProvider(widget.ticketId))),
        data: (ticket) {
          // I'm on the team if the property is one of mine.
          final isStaff = (ref.watch(myPropertiesProvider).value ?? const [])
              .any((p) => p.property.id == ticket.propertyId);
          // Written offline, not sent yet: shown last, marked "waiting".
          final messages = [...sentMessages, for (final item in pending) item.asMessage(fromStaff: isStaff)];
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(ticket.category.icon, color: AppColors.primary),
                              const SizedBox(width: 8),
                              Text(ticket.category.label, style: text.bodySmall),
                              const Spacer(),
                              StatusPill(
                                label: ticket.status.label,
                                color: ticket.status.color,
                                icon: ticket.status.icon,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(ticket.title, style: text.titleMedium),
                          if (ticket.description != null) ...[
                            const SizedBox(height: 6),
                            Text(ticket.description!),
                          ],
                          const SizedBox(height: 10),
                          Text(
                            [
                              if (ticket.apartmentName != null) 'Unit ${ticket.apartmentName}',
                              if (ticket.tenantName != null) ticket.tenantName!,
                              'reported ${formatDate(ticket.createdAt)}',
                            ].join(' · '),
                            style: text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    // A receipt dispute: open the receipt it's about.
                    if (ticket.paymentId case final paymentId?) ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => context.push(isStaff
                            ? AppRoutes.receipt(ticket.propertyId, paymentId)
                            : AppRoutes.myReceipt(ticket.tenancyId, paymentId)),
                        icon: const Icon(Icons.receipt_long_rounded),
                        label: const Text('View the receipt'),
                      ),
                    ],
                    // Fixed it? Log the repair (which can also resolve this issue).
                    if (isStaff &&
                        ticket.status != TicketStatus.resolved &&
                        ticket.category != TicketCategory.receipt &&
                        ticket.apartmentId != null) ...[
                      const SizedBox(height: 10),
                      FilledButton.tonalIcon(
                        onPressed: () => context.push(
                          AppRoutes.newRepair(ticket.propertyId, ticket.apartmentId!, ticketId: ticket.id),
                        ),
                        icon: const Icon(Icons.handyman_rounded),
                        label: const Text('Log the repair'),
                      ),
                    ],
                    if (isStaff) ...[
                      const SizedBox(height: 14),
                      Text('Status', style: text.titleSmall),
                      const SizedBox(height: 8),
                      SegmentedButton<TicketStatus>(
                        showSelectedIcon: false, // keeps "In progress" on one line
                        segments: [
                          for (final s in TicketStatus.values)
                            ButtonSegment(value: s, label: Text(s.label)),
                        ],
                        selected: {ticket.status},
                        onSelectionChanged: (s) => _setStatus(ticket, s.first),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Text('Conversation', style: text.titleSmall),
                    const SizedBox(height: 8),
                    if (messages.isEmpty)
                      Text('No replies yet.', style: text.bodySmall)
                    else
                      for (final m in messages) _Bubble(message: m, mine: m.fromStaff == isStaff),
                  ],
                ),
              ),
              // Reply box at the bottom.
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _replyController,
                          minLines: 1,
                          maxLines: 4,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(hintText: 'Write a reply'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: 'Send',
                        style: IconButton.styleFrom(backgroundColor: AppColors.primary),
                        onPressed: _busy ? null : () => _send(ticket),
                        icon: const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A chat bubble: mine on the right in orange, theirs on the left.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine});

  final TicketMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine ? AppColors.primary : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppColors.cardShadow(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.fromStaff ? 'Team' : 'Tenant',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: mine ? Colors.white70 : AppColors.muted,
              ),
            ),
            Text(message.body, style: TextStyle(color: mine ? Colors.white : null)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.pending) ...[
                  Icon(Icons.schedule_rounded, size: 11, color: mine ? Colors.white70 : AppColors.muted),
                  const SizedBox(width: 3),
                ],
                Text(
                  message.pending ? 'Waiting to send' : formatDate(message.createdAt),
                  style: TextStyle(fontSize: 10, color: mine ? Colors.white70 : AppColors.muted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
