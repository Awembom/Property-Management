import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/tickets/data/ticket.dart';

/// How long a tenant has to confirm a receipt or report a problem. After
/// that, a receipt nobody answered counts as accepted. (The database
/// enforces the same 24 hours in receipt_open_for_response.)
const receiptAnswerWindow = Duration(hours: 24);

/// What a tenant can say is wrong with a receipt (`receipt_responses.problem`).
enum ReceiptProblem {
  amount('amount', 'Wrong amount'),
  months('months', 'Wrong number of months'),
  dates('dates', 'Wrong dates'),
  notMine('not_mine', 'I didn\'t make this payment'),
  other('other', 'Something else');

  const ReceiptProblem(this.value, this.label);

  final String value;
  final String label;

  static ReceiptProblem? fromJson(String? value) {
    for (final problem in values) {
      if (problem.value == value) return problem;
    }
    return null;
  }
}

/// The tenant's answer to a receipt (`receipt_responses`), if any.
class ReceiptResponse {
  const ReceiptResponse({
    required this.confirmed,
    required this.answeredAt,
    this.problem,
    this.ticketId,
    this.ticketStatus,
  });

  /// true = confirmed; false = reported a problem.
  final bool confirmed;
  final DateTime answeredAt;
  final ReceiptProblem? problem;

  /// The dispute's ticket (disputes only).
  final String? ticketId;
  final TicketStatus? ticketStatus;

  /// To embed in a payments query.
  static const embed =
      'response:receipt_responses(response, problem, ticket_id, created_at, ticket:tickets(status))';

  static ReceiptResponse? fromEmbed(Object? json) {
    // One-to-one embeds come back as an object; be lenient with a list.
    final row = json is List ? (json.isEmpty ? null : json.first) : json;
    if (row is! Map<String, dynamic>) return null;
    final ticket = row['ticket'] as Map<String, dynamic>?;
    return ReceiptResponse(
      confirmed: row['response'] == 'confirmed',
      answeredAt: DateTime.parse(row['created_at'] as String).toLocal(),
      problem: ReceiptProblem.fromJson(row['problem'] as String?),
      ticketId: row['ticket_id'] as String?,
      ticketStatus: ticket == null ? null : TicketStatus.fromJson(ticket['status'] as String),
    );
  }
}

/// Where a receipt stands with the tenant.
enum ReceiptStandingKind {
  /// Within 24 hours, no answer yet.
  awaiting,

  /// The tenant confirmed it.
  confirmed,

  /// 24 hours passed without an answer.
  accepted,

  /// The tenant reported a problem that isn't sorted out yet.
  disputed,

  /// The problem's ticket was resolved.
  disputeResolved,

  /// The payment was voided.
  voided,
}

class ReceiptStanding {
  const ReceiptStanding(this.kind, {this.at, this.response});

  final ReceiptStandingKind kind;

  /// awaiting: the deadline; confirmed/disputed: when; accepted: when it
  /// became accepted.
  final DateTime? at;
  final ReceiptResponse? response;

  /// Works out the standing. Returns null when there's nothing to show: the
  /// tenant has no app account, so they can't answer.
  static ReceiptStanding? of({
    required DateTime issuedAt,
    required bool isVoided,
    required ReceiptResponse? response,
    required bool tenantHasAccount,
    bool confirmationQueued = false,
    DateTime? now,
  }) {
    if (isVoided) return const ReceiptStanding(ReceiptStandingKind.voided);
    if (response != null) {
      if (response.confirmed) {
        return ReceiptStanding(ReceiptStandingKind.confirmed, at: response.answeredAt, response: response);
      }
      return ReceiptStanding(
        response.ticketStatus == TicketStatus.resolved
            ? ReceiptStandingKind.disputeResolved
            : ReceiptStandingKind.disputed,
        at: response.answeredAt,
        response: response,
      );
    }
    // Confirmed offline, waiting to be sent: show it as confirmed already.
    if (confirmationQueued) {
      return ReceiptStanding(ReceiptStandingKind.confirmed, at: now ?? DateTime.now());
    }
    if (!tenantHasAccount) return null;
    final deadline = issuedAt.add(receiptAnswerWindow);
    if ((now ?? DateTime.now()).isBefore(deadline)) {
      return ReceiptStanding(ReceiptStandingKind.awaiting, at: deadline);
    }
    return ReceiptStanding(ReceiptStandingKind.accepted, at: deadline);
  }

  /// Can the tenant still confirm or report a problem?
  bool get canAnswer => kind == ReceiptStandingKind.awaiting;

  String get label => switch (kind) {
        ReceiptStandingKind.awaiting => 'Awaiting confirmation',
        ReceiptStandingKind.confirmed => 'Confirmed by tenant',
        ReceiptStandingKind.accepted => 'Accepted',
        ReceiptStandingKind.disputed => 'Disputed',
        ReceiptStandingKind.disputeResolved => 'Dispute resolved',
        ReceiptStandingKind.voided => 'Void',
      };

  Color get color => switch (kind) {
        ReceiptStandingKind.awaiting => AppColors.dueSoon,
        ReceiptStandingKind.confirmed || ReceiptStandingKind.accepted => AppColors.paid,
        ReceiptStandingKind.disputed || ReceiptStandingKind.voided => AppColors.overdue,
        ReceiptStandingKind.disputeResolved => AppColors.accent,
      };

  IconData get icon => switch (kind) {
        ReceiptStandingKind.awaiting => Icons.hourglass_top_rounded,
        ReceiptStandingKind.confirmed => Icons.verified_rounded,
        ReceiptStandingKind.accepted => Icons.task_alt_rounded,
        ReceiptStandingKind.disputed => Icons.report_problem_rounded,
        ReceiptStandingKind.disputeResolved => Icons.handshake_rounded,
        ReceiptStandingKind.voided => Icons.block_rounded,
      };

  /// One sentence explaining the standing, for the tenant ([forTenant]) or
  /// for the team.
  String describe({required bool forTenant, DateTime? now}) {
    final when = at == null ? '' : _formatWhen(at!);
    switch (kind) {
      case ReceiptStandingKind.awaiting:
        final left = _hoursLeft(at!, now ?? DateTime.now());
        return forTenant
            ? 'Please check it. You have $left to confirm or report a problem; '
                'after that it counts as accepted.'
            : 'The tenant has $left to confirm it or report a problem.';
      case ReceiptStandingKind.confirmed:
        return forTenant ? 'You confirmed this receipt on $when.' : 'The tenant confirmed it on $when.';
      case ReceiptStandingKind.accepted:
        return 'No problem was reported within 24 hours, so it was accepted on $when.';
      case ReceiptStandingKind.disputed:
        final problem = response?.problem?.label.toLowerCase() ?? 'a problem';
        return forTenant
            ? 'You reported: $problem. Follow it up in the ticket.'
            : 'The tenant reported: $problem ($when). Answer in the ticket.';
      case ReceiptStandingKind.disputeResolved:
        return 'A problem was reported on $when and has been resolved.';
      case ReceiptStandingKind.voided:
        return 'This payment was voided.';
    }
  }

  /// The line printed on the PDF, or null for nothing.
  String? get pdfLine => switch (kind) {
        ReceiptStandingKind.confirmed => 'Confirmed by the tenant on ${_formatWhen(at!)}',
        ReceiptStandingKind.accepted =>
          'Accepted: no problem reported within 24 hours (${_formatWhen(at!)})',
        ReceiptStandingKind.disputed => 'Disputed by the tenant on ${_formatWhen(at!)}',
        ReceiptStandingKind.disputeResolved => 'Dispute raised and resolved',
        ReceiptStandingKind.awaiting => 'Awaiting tenant confirmation (until ${_formatWhen(at!)})',
        ReceiptStandingKind.voided => null,
      };

  static String _formatWhen(DateTime at) => DateFormat('d MMM yyyy, HH:mm').format(at.toLocal());

  static String _hoursLeft(DateTime deadline, DateTime now) {
    final minutes = deadline.difference(now).inMinutes;
    if (minutes >= 120) return '${minutes ~/ 60} hours';
    if (minutes >= 60) return '1 hour';
    return '${minutes < 1 ? 1 : minutes} minutes';
  }
}
