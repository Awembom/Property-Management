import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/offline/cache_cipher.dart';
import 'package:rental_app/core/offline/connection_status.dart';
import 'package:rental_app/core/offline/local_store.dart';
import 'package:rental_app/core/offline/network_errors.dart';
import 'package:rental_app/core/offline/offline_cache.dart';
import 'package:rental_app/core/supabase/supabase_providers.dart';
import 'package:rental_app/features/auth/data/profile.dart';
import 'package:rental_app/features/auth/data/profile_repository.dart';
import 'package:rental_app/features/auth/providers/auth_providers.dart';
import 'package:rental_app/features/payments/providers/payments_providers.dart';
import 'package:rental_app/features/receipts/data/receipts_repository.dart';
import 'package:rental_app/features/tenant_access/providers/tenant_access_providers.dart';
import 'package:rental_app/features/tickets/data/ticket.dart';
import 'package:rental_app/features/tickets/data/tickets_repository.dart';
import 'package:rental_app/features/tickets/providers/tickets_providers.dart';

/// What can wait in the outbox. Only things that are safe to send late:
/// ticket messages, new tickets, receipt confirmations and my own name and
/// phone. Money actions (payments, bills...) and passwords always need a
/// connection.
enum OutboxKind { ticketMessage, newTicket, confirmReceipt, updateProfile }

/// Something done offline, waiting to be sent. Its [id] is also sent to the
/// database as the "client id", so sending it twice saves it once.
class OutboxItem {
  const OutboxItem({required this.id, required this.kind, required this.data, required this.createdAt});

  final String id;
  final OutboxKind kind;
  final Map<String, dynamic> data;
  final DateTime createdAt;

  /// A queued ticket message.
  factory OutboxItem.ticketMessage({required String ticketId, required String body}) => OutboxItem(
        id: newUuid(),
        kind: OutboxKind.ticketMessage,
        data: {'ticket_id': ticketId, 'body': body},
        createdAt: DateTime.now(),
      );

  /// A queued new ticket.
  factory OutboxItem.newTicket({
    required String tenancyId,
    required String title,
    required String? description,
    required TicketCategory category,
  }) =>
      OutboxItem(
        id: newUuid(),
        kind: OutboxKind.newTicket,
        data: {'tenancy_id': tenancyId, 'title': title, 'description': description, 'category': category.value},
        createdAt: DateTime.now(),
      );

  /// A queued receipt confirmation.
  factory OutboxItem.confirmReceipt({required String paymentId, required String tenancyId}) => OutboxItem(
        id: newUuid(),
        kind: OutboxKind.confirmReceipt,
        data: {'payment_id': paymentId, 'tenancy_id': tenancyId},
        createdAt: DateTime.now(),
      );

  /// My new name and phone (only the latest edit is kept).
  factory OutboxItem.updateProfile({required String? fullName, required String? phone}) => OutboxItem(
        id: newUuid(),
        kind: OutboxKind.updateProfile,
        data: {'full_name': fullName, 'phone': phone},
        createdAt: DateTime.now(),
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'kind': kind.name, 'data': data, 'created_at': createdAt.toIso8601String()};

  factory OutboxItem.fromJson(Map<String, dynamic> json) => OutboxItem(
        id: json['id'] as String,
        kind: OutboxKind.values.byName(json['kind'] as String),
        data: json['data'] as Map<String, dynamic>,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  /// How a not-yet-sent ticket message looks in the conversation.
  TicketMessage asMessage({required bool fromStaff}) => TicketMessage(
        id: id,
        body: data['body'] as String,
        fromStaff: fromStaff,
        createdAt: createdAt,
        pending: true,
      );

  /// How a not-yet-sent ticket looks in the list.
  Ticket asTicket() => Ticket(
        id: id,
        propertyId: '',
        tenancyId: data['tenancy_id'] as String,
        title: data['title'] as String,
        description: data['description'] as String?,
        category: TicketCategory.fromJson(data['category'] as String),
        status: TicketStatus.open,
        createdAt: createdAt,
        updatedAt: createdAt,
        pending: true,
      );
}

/// A random (version 4) UUID.
String newUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// The logged-in account's outbox, saved encrypted on the phone so it
/// survives closing the app.
class OutboxNotifier extends AsyncNotifier<List<OutboxItem>> {
  bool _flushing = false;

  LocalStore get _store => ref.read(localStoreProvider);
  CacheCipher get _cipher => ref.read(cacheCipherProvider);
  String? get _account => ref.read(supabaseClientProvider).auth.currentUser?.id;

  @override
  Future<List<OutboxItem>> build() async {
    // Another login = another outbox.
    ref.watch(authStateProvider);
    final account = _account;
    if (account == null) return [];
    final items = <OutboxItem>[];
    for (final entry in await _store.outbox(account)) {
      try {
        final text = await _cipher.decrypt(account, entry.data);
        items.add(OutboxItem.fromJson(jsonDecode(text) as Map<String, dynamic>));
      } catch (e) {
        debugPrint('Outbox: could not read ${entry.key}: $e');
      }
    }
    return items;
  }

  /// Sends [item] now if possible. If the phone is offline (or the request
  /// can't get through), keeps it in the outbox and returns false; it's sent
  /// automatically when the connection is back. Other errors (the server
  /// said no) are thrown as usual.
  Future<bool> sendOrQueue(OutboxItem item) async {
    if (ref.read(connectionProvider).online) {
      try {
        await _send(item);
        ref.read(connectionProvider.notifier).reportRequest(reached: true);
        _refreshAfter(item);
        return true;
      } catch (e) {
        if (!isNetworkError(e)) rethrow;
        ref.read(connectionProvider.notifier).reportRequest(reached: false);
      }
    }
    await _add(item);
    return false;
  }

  /// Sends everything waiting, oldest first. Stops at the first connection
  /// problem (the rest waits for the next try). Something the server refuses
  /// (e.g. the 24 hours to confirm passed) is dropped: retrying wouldn't help.
  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      final items = [...(await future)];
      for (final item in items) {
        try {
          await _send(item);
        } catch (e) {
          if (isNetworkError(e)) break;
          debugPrint('Outbox: ${item.kind.name} refused, dropped: $e');
        }
        await _store.removeFromOutbox(item.id);
        state = AsyncData([...(state.value ?? const <OutboxItem>[])]..removeWhere((i) => i.id == item.id));
        _refreshAfter(item);
      }
    } finally {
      _flushing = false;
    }
  }

  Future<void> _add(OutboxItem item) async {
    final account = _account;
    if (account == null) throw StateError('Not logged in');
    // A newer profile edit replaces an older one still waiting.
    if (item.kind == OutboxKind.updateProfile) {
      for (final old in [...(state.value ?? const <OutboxItem>[])]) {
        if (old.kind != OutboxKind.updateProfile) continue;
        await _store.removeFromOutbox(old.id);
        state = AsyncData([...(state.value ?? const <OutboxItem>[])]..removeWhere((i) => i.id == old.id));
      }
    }
    final data = await _cipher.encrypt(account, jsonEncode(item.toJson()));
    await _store.addToOutbox(account, item.id, data, item.createdAt);
    state = AsyncData([...(state.value ?? const <OutboxItem>[]), item]);
  }

  Future<void> _send(OutboxItem item) async {
    final d = item.data;
    switch (item.kind) {
      case OutboxKind.ticketMessage:
        await ref
            .read(ticketsRepositoryProvider)
            .addMessage(d['ticket_id'] as String, d['body'] as String, clientId: item.id);
      case OutboxKind.newTicket:
        await ref.read(ticketsRepositoryProvider).create(
              tenancyId: d['tenancy_id'] as String,
              title: d['title'] as String,
              description: d['description'] as String?,
              category: TicketCategory.fromJson(d['category'] as String),
              clientId: item.id,
            );
      case OutboxKind.confirmReceipt:
        await ref.read(receiptsRepositoryProvider).confirm(d['payment_id'] as String);
      case OutboxKind.updateProfile:
        await ref.read(profileRepositoryProvider).updateMyProfile(
              Profile(id: '', fullName: d['full_name'] as String?, phone: d['phone'] as String?),
            );
    }
  }

  /// Reloads the screens that show what was just sent.
  void _refreshAfter(OutboxItem item) {
    final d = item.data;
    switch (item.kind) {
      case OutboxKind.ticketMessage:
        ref.invalidate(ticketMessagesProvider(d['ticket_id'] as String));
        ref.invalidate(ticketProvider(d['ticket_id'] as String));
      case OutboxKind.newTicket:
        ref.invalidate(tenancyTicketsProvider(d['tenancy_id'] as String));
      case OutboxKind.confirmReceipt:
        ref.invalidate(paymentProvider(d['payment_id'] as String));
        ref.invalidate(myRentalDetailsProvider(d['tenancy_id'] as String));
      case OutboxKind.updateProfile:
        ref.invalidate(myProfileProvider);
    }
  }
}

final outboxProvider = AsyncNotifierProvider<OutboxNotifier, List<OutboxItem>>(OutboxNotifier.new);

/// Ticket messages written offline for one ticket, not sent yet.
final pendingMessagesProvider = Provider.autoDispose.family<List<OutboxItem>, String>((ref, ticketId) {
  final items = ref.watch(outboxProvider).value ?? const [];
  return [
    for (final item in items)
      if (item.kind == OutboxKind.ticketMessage && item.data['ticket_id'] == ticketId) item,
  ];
});

/// Tickets reported offline for one tenancy, not sent yet.
final pendingTicketsProvider = Provider.autoDispose.family<List<Ticket>, String>((ref, tenancyId) {
  final items = ref.watch(outboxProvider).value ?? const [];
  return [
    for (final item in items)
      if (item.kind == OutboxKind.newTicket && item.data['tenancy_id'] == tenancyId) item.asTicket(),
  ];
});

/// Payments whose receipt was confirmed offline, not sent yet.
final queuedConfirmationsProvider = Provider.autoDispose<Set<String>>((ref) {
  final items = ref.watch(outboxProvider).value ?? const [];
  return {
    for (final item in items)
      if (item.kind == OutboxKind.confirmReceipt) item.data['payment_id'] as String,
  };
});
