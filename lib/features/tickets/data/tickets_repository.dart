import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/offline/network_errors.dart';
import 'package:rental_app/core/offline/offline_cache.dart';
import 'package:rental_app/core/supabase/supabase_providers.dart';
import 'package:rental_app/features/tickets/data/ticket.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Tickets (issues reported by tenants) and their replies. Creating,
/// changing the status and replying go through database functions that
/// check who's calling.
class TicketsRepository {
  TicketsRepository(this._client, this._cache);

  final SupabaseClient _client;

  /// Keeps what was loaded, for offline use (see OfflineCache).
  final OfflineCache _cache;

  /// All tickets of a property (the team's view), newest activity first,
  /// with the apartment and tenant names.
  Future<List<Ticket>> fetchForProperty(String propertyId) async {
    final rows = await _cache.rows(
      'tickets/property/$propertyId',
      () => _client
          .from('tickets')
          .select(Ticket.columns)
          .eq('property_id', propertyId)
          .order('updated_at', ascending: false),
    );
    for (final row in rows) {
      await _cache.put('ticket/${row['id']}', row);
    }
    return _withNames(rows, 'ticket_names/$propertyId');
  }

  /// One tenancy's tickets (the tenant's view).
  Future<List<Ticket>> fetchForTenancy(String tenancyId) async {
    final rows = await _cache.rows(
      'tickets/tenancy/$tenancyId',
      () => _client
          .from('tickets')
          .select(Ticket.columns)
          .eq('tenancy_id', tenancyId)
          .order('updated_at', ascending: false),
    );
    for (final row in rows) {
      await _cache.put('ticket/${row['id']}', row);
    }
    return rows.map(Ticket.fromJson).toList();
  }

  /// All tickets of one unit (every tenancy it had), newest activity first.
  Future<List<Ticket>> fetchForUnit(String apartmentId, List<String> tenancyIds) async {
    if (tenancyIds.isEmpty) return [];
    final rows = await _cache.rows(
      'tickets/unit/$apartmentId',
      () => _client
          .from('tickets')
          .select(Ticket.columns)
          .inFilter('tenancy_id', tenancyIds)
          .order('updated_at', ascending: false),
    );
    for (final row in rows) {
      await _cache.put('ticket/${row['id']}', row);
    }
    return rows.map(Ticket.fromJson).toList();
  }

  Future<Ticket> fetchTicket(String ticketId) async {
    final row = await _cache.row(
      'ticket/$ticketId',
      () => _client.from('tickets').select(Ticket.columns).eq('id', ticketId).maybeSingle(),
    );
    if (row == null) throw StateError('Ticket not found');
    return (await _withNames([row], 'ticket_names/${row['property_id']}', single: true)).single;
  }

  Future<List<TicketMessage>> fetchMessages(String ticketId) async {
    final rows = await _cache.rows(
      'ticket_messages/$ticketId',
      () => _client
          .from('ticket_messages')
          .select('id, body, from_staff, created_at')
          .eq('ticket_id', ticketId)
          .order('created_at'),
    );
    return rows.map(TicketMessage.fromJson).toList();
  }

  Future<String> create({
    required String tenancyId,
    required String title,
    String? description,
    required TicketCategory category,
    String? clientId,
  }) async {
    final id = await _client.rpc('create_ticket', params: {
      'p_tenancy_id': tenancyId,
      'p_title': title,
      'p_description': description,
      'p_category': category.value,
      'p_client_id': clientId,
    });
    return id as String;
  }

  Future<void> setStatus(String ticketId, TicketStatus status) async {
    await _client.rpc('set_ticket_status', params: {'p_ticket_id': ticketId, 'p_status': status.value});
  }

  /// [clientId]: the outbox item's id. If the same message is sent twice
  /// (the answer to the first try got lost), the database keeps one.
  Future<void> addMessage(String ticketId, String body, {String? clientId}) async {
    await _client.rpc('add_ticket_message', params: {
      'p_ticket_id': ticketId,
      'p_body': body,
      'p_client_id': clientId,
    });
  }

  /// Adds apartment and tenant names from the tenancy overview.
  /// Names are saved per property ([cacheKey]); one ticket's ([single])
  /// under its own key, falling back to the property's when offline.
  Future<List<Ticket>> _withNames(List<Map<String, dynamic>> rows, String cacheKey, {bool single = false}) async {
    if (rows.isEmpty) return [];
    final tenancyIds = rows.map((r) => r['tenancy_id'] as String).toSet().toList();
    List<Map<String, dynamic>> names;
    try {
      names = await _cache.rows(
        single ? '$cacheKey/${rows.single['id']}' : cacheKey,
        () => _client
            .from('tenancy_overview')
            .select('id, apartment_id, apartment_name, tenant_name')
            .inFilter('id', tenancyIds),
      );
    } on OfflineException {
      names = await _cache.savedRows(cacheKey).catchError((_) => <Map<String, dynamic>>[]);
    }
    final byId = {for (final n in names) n['id'] as String: n};
    return [
      for (final row in rows)
        Ticket.fromJson(
          row,
          apartmentName: byId[row['tenancy_id']]?['apartment_name'] as String?,
          apartmentId: byId[row['tenancy_id']]?['apartment_id'] as String?,
          tenantName: byId[row['tenancy_id']]?['tenant_name'] as String?,
        ),
    ];
  }
}

final ticketsRepositoryProvider = Provider<TicketsRepository>((ref) {
  return TicketsRepository(ref.watch(supabaseClientProvider), ref.watch(offlineCacheProvider));
});
