import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:rental_app/core/offline/outbox.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/payments/data/payment.dart';
import 'package:rental_app/features/payments/presentation/receipt_pdf.dart';
import 'package:rental_app/features/payments/providers/payments_providers.dart';
import 'package:rental_app/features/receipts/data/receipt_standing.dart';
import 'package:rental_app/features/receipts/providers/receipts_providers.dart';
import 'package:rental_app/features/tenant_access/providers/tenant_access_providers.dart';
import 'package:rental_app/shared/utils/dates.dart';
import 'package:rental_app/shared/widgets/app_card.dart';
import 'package:rental_app/shared/widgets/confirm_dialog.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';
import 'package:rental_app/shared/widgets/status_pill.dart';

/// A receipt on screen, for the team (ReceiptPage) and for the tenant
/// (TenantReceiptPage): the receipt itself, where it stands with the tenant
/// (confirmed, disputed...), its QR code, and sharing the PDF.
class ReceiptView extends ConsumerWidget {
  const ReceiptView({
    super.key,
    required this.info,
    required this.earlier,
    required this.forTenant,
    required this.routeFor,
    this.actions = const [],
  });

  final ReceiptInfo info;

  /// Earlier receipts with the same reference code, oldest first.
  final List<ReceiptInfo> earlier;

  /// The tenant is looking (they can confirm or report a problem).
  final bool forTenant;

  /// Where another receipt of this tenancy opens.
  final String Function(Payment payment) routeFor;

  /// Extra buttons at the bottom (e.g. "Void" for the team).
  final List<Widget> actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Not signed yet (e.g. recorded a moment ago): sign it now. Offline, the
    // QR code waits until the phone is back online.
    var shown = info;
    var signing = false;
    if (info.payment.signed == null && !info.payment.isVoided) {
      final signature = ref.watch(receiptSignatureProvider(info.payment.id));
      if (signature.value case final signed?) shown = info.withSigned(signed);
      signing = signature.isLoading;
    }
    final queued = ref.watch(queuedConfirmationsProvider).contains(info.payment.id);
    final standing = shown.standing(confirmationQueued: queued);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _ReceiptCard(info: shown),
        if (standing != null) ...[
          const SizedBox(height: 14),
          _StandingCard(
            standing: standing,
            queued: queued,
            forTenant: forTenant,
            info: shown,
          ),
        ],
        const SizedBox(height: 14),
        _QrCard(info: shown, signing: signing),
        if (earlier.isNotEmpty) ...[
          const SizedBox(height: 14),
          _EarlierCard(info: shown, earlier: earlier, routeFor: routeFor),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => _share(context, shown),
          icon: const Icon(Icons.share_rounded),
          label: Text(earlier.isEmpty
              ? 'Share receipt (PDF)'
              : 'Share receipts (${earlier.length + 1}-page PDF)'),
        ),
        ...actions,
      ],
    );
  }

  Future<void> _share(BuildContext context, ReceiptInfo shown) async {
    try {
      await Printing.sharePdf(
        bytes: await buildReceiptPdf(shown, earlier: earlier),
        filename: '${shown.payment.receiptNumber}.pdf',
      );
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}

/// The receipt: header, lines, and what's left to pay.
class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({required this.info});

  final ReceiptInfo info;

  @override
  Widget build(BuildContext context) {
    final payment = info.payment;
    final text = Theme.of(context).textTheme;
    final balance = payment.balanceAfter;
    final balanceColor = balance > 0 ? AppColors.overdue : AppColors.paid;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header strip in the brand colours.
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(gradient: AppColors.gradientFor(AppColors.primary)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 36),
                const SizedBox(height: 8),
                Text(
                  payment.receiptNumber,
                  style: text.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                ),
                Text(
                  '${info.property.name} · issued ${formatDate(payment.issuedAt)}',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
          if (payment.isVoided)
            Container(
              color: AppColors.soft(AppColors.overdue),
              padding: const EdgeInsets.all(12),
              child: Text(
                'VOID: ${payment.voidReason}',
                style: text.titleSmall?.copyWith(color: AppColors.overdue, fontWeight: FontWeight.w800),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                for (final line in info.lines)
                  Container(
                    // "Amount left" (money still owed) stands out in red.
                    decoration: line.isAlert
                        ? BoxDecoration(
                            color: AppColors.soft(AppColors.overdue),
                            borderRadius: BorderRadius.circular(8),
                          )
                        : null,
                    padding: EdgeInsets.symmetric(vertical: 6, horizontal: line.isAlert ? 8 : 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            line.label,
                            style: text.bodyMedium?.copyWith(
                              color: line.isAlert ? AppColors.overdue : null,
                              fontWeight: line.isAlert ? FontWeight.w800 : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            line.value,
                            textAlign: TextAlign.end,
                            style: text.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: line.isAlert ? AppColors.overdue : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.soft(balanceColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    info.balanceText,
                    textAlign: TextAlign.center,
                    style: text.titleMedium?.copyWith(color: balanceColor, fontWeight: FontWeight.w800),
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

/// Confirmed / awaiting / disputed..., and for the tenant the buttons to
/// confirm or report a problem.
class _StandingCard extends ConsumerWidget {
  const _StandingCard({required this.standing, required this.queued, required this.forTenant, required this.info});

  final ReceiptStanding standing;
  final bool queued;
  final bool forTenant;
  final ReceiptInfo info;

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Confirm this receipt?',
      message: 'You agree the amount, months and dates are correct. This can\'t be undone.',
      confirmLabel: 'Confirm',
    );
    if (!ok || !context.mounted) return;
    final payment = info.payment;
    try {
      // Offline, the confirmation waits in the outbox and is sent later.
      final sent = await ref
          .read(outboxProvider.notifier)
          .sendOrQueue(OutboxItem.confirmReceipt(paymentId: payment.id, tenancyId: payment.tenancyId));
      if (sent) {
        ref.invalidate(myRentalDetailsProvider(payment.tenancyId));
        ref.invalidate(paymentProvider(payment.id));
      }
      if (context.mounted) {
        showMessage(context, sent ? 'Thank you, receipt confirmed.' : 'Confirmed. It will be sent when you\'re back online.');
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final ticketId = standing.response?.ticketId;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Wraps onto two lines on narrow screens.
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(forTenant ? 'Your answer' : 'Tenant\'s answer', style: text.titleSmall),
              StatusPill(
                label: queued ? 'Confirmed (waiting to send)' : standing.label,
                color: standing.color,
                icon: queued ? Icons.schedule_rounded : standing.icon,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            queued
                ? 'Your confirmation will be sent when you\'re back online.'
                : standing.describe(forTenant: forTenant),
            style: text.bodyMedium,
          ),
          if (forTenant && standing.canAnswer) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.paid),
              onPressed: () => _confirm(context, ref),
              icon: const Icon(Icons.verified_rounded),
              label: const Text('Confirm, it\'s correct'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.overdue,
                side: const BorderSide(color: AppColors.overdue),
              ),
              onPressed: () => context.push(
                AppRoutes.reportReceiptProblem(info.payment.tenancyId, info.payment.id),
              ),
              icon: const Icon(Icons.report_problem_rounded),
              label: const Text('Report a problem'),
            ),
          ],
          if (ticketId != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => context.push(AppRoutes.ticket(ticketId)),
              icon: const Icon(Icons.forum_rounded),
              label: const Text('Open the conversation'),
            ),
          ],
        ],
      ),
    );
  }
}

/// The QR code that proves the receipt is genuine.
class _QrCard extends StatelessWidget {
  const _QrCard({required this.info, required this.signing});

  final ReceiptInfo info;
  final bool signing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final signed = info.payment.signed;
    final Widget code;
    final String explanation;
    if (signed != null) {
      code = Container(
        padding: const EdgeInsets.all(6),
        color: Colors.white, // QR codes need a light background, also in dark mode
        child: BarcodeWidget(barcode: Barcode.qrCode(), data: signed.qrText, width: 96, height: 96),
      );
      explanation = 'Anyone with the app can scan this code (Profile > Check a receipt) to '
          'see it\'s genuine. It\'s also printed on the PDF.';
    } else {
      code = SizedBox.square(
        dimension: 96,
        child: Center(
          child: signing
              ? const CircularProgressIndicator()
              : const Icon(Icons.qr_code_2_rounded, size: 56, color: AppColors.muted),
        ),
      );
      explanation = info.payment.isVoided
          ? 'Voided payments have no check code.'
          : signing
              ? 'Adding the check code…'
              : 'The check code is added when you\'re back online.';
    }
    return AppCard(
      child: Row(
        children: [
          code,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Proof it\'s genuine', style: text.titleSmall),
                const SizedBox(height: 4),
                Text(explanation, style: text.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Earlier receipts with the same reference (they go on the extra PDF pages).
class _EarlierCard extends StatelessWidget {
  const _EarlierCard({required this.info, required this.earlier, required this.routeFor});

  final ReceiptInfo info;
  final List<ReceiptInfo> earlier;
  final String Function(Payment payment) routeFor;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      color: AppColors.solidSoft(context, AppColors.primary),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Same reference ${info.payment.referenceCode}: the PDF includes '
                '${earlier.length == 1 ? 'this earlier receipt' : 'these earlier receipts'}',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            for (final other in earlier)
              ListTile(
                leading: const Icon(Icons.link_rounded, color: AppColors.primary),
                title: Text(other.payment.receiptNumber),
                subtitle: Text('${formatDate(other.payment.paidOn)} · ${other.balanceText}'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(routeFor(other.payment)),
              ),
          ],
        ),
      ),
    );
  }
}
