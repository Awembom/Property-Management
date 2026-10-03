import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/features/tickets/data/ticket.dart';
import 'package:rental_app/features/tickets/data/tickets_repository.dart';

final propertyTicketsProvider =
    FutureProvider.autoDispose.family<List<Ticket>, String>((ref, propertyId) {
  return ref.watch(ticketsRepositoryProvider).fetchForProperty(propertyId);
});

final tenancyTicketsProvider =
    FutureProvider.autoDispose.family<List<Ticket>, String>((ref, tenancyId) {
  return ref.watch(ticketsRepositoryProvider).fetchForTenancy(tenancyId);
});

final ticketProvider = FutureProvider.autoDispose.family<Ticket, String>((ref, ticketId) {
  return ref.watch(ticketsRepositoryProvider).fetchTicket(ticketId);
});

final ticketMessagesProvider =
    FutureProvider.autoDispose.family<List<TicketMessage>, String>((ref, ticketId) {
  return ref.watch(ticketsRepositoryProvider).fetchMessages(ticketId);
});
