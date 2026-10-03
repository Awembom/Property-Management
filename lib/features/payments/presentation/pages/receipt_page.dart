import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/apartments/providers/apartments_providers.dart';
import 'package:rental_app/features/payments/data/payment.dart';
import 'package:rental_app/features/payments/data/payments_repository.dart';
import 'package:rental_app/features/payments/presentation/receipt_pdf.dart';
import 'package:rental_app/features/payments/presentation/widgets/receipt_view.dart';
import 'package:rental_app/features/payments/providers/payments_providers.dart';
import 'package:rental_app/features/properties/providers/properties_providers.dart';
import 'package:rental_app/features/tenancies/providers/tenancies_providers.dart';
import 'package:rental_app/shared/widgets/async_error_view.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';

/// One payment's receipt for the team: view it, see the tenant's answer,
/// share or print the PDF, or void it. Staff who may see money only.
class ReceiptPage extends ConsumerWidget {
  const ReceiptPage({super.key, required this.propertyId, required this.paymentId});

  final String propertyId;
  final String paymentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myProperty = ref.watch(myPropertyProvider(propertyId));
    final payment = ref.watch(paymentProvider(paymentId));
    // The tenancy gives the tenant and apartment names; load it once we know
    // which tenancy the payment belongs to.
    final tenancyId = payment.value?.tenancyId;
    final details = tenancyId == null
        ? null
        : ref.watch(tenancyDetailsProvider((propertyId: propertyId, tenancyId: tenancyId)));
    // Earlier receipts with the same reference code (extra PDF pages).
    final earlierPayments = ref.watch(earlierReceiptsProvider(paymentId));

    final error = myProperty.error ?? payment.error ?? details?.error ?? earlierPayments.error;
    final Widget body;
    ReceiptInfo? info;
    var earlier = const <ReceiptInfo>[];
    if (error != null) {
      body = AsyncErrorView(
        error: error,
        onRetry: () => ref.invalidate(paymentProvider(paymentId)),
      );
    } else if (!myProperty.hasValue ||
        !payment.hasValue ||
        !(details?.hasValue ?? false) ||
        !earlierPayments.hasValue) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final tenancy = details!.requireValue;
      info = ReceiptInfo(
        property: myProperty.requireValue.property,
        tenantName: tenancy.tenant.fullName,
        apartmentName: tenancy.overview.apartmentName,
        payment: payment.requireValue,
        tenantHasAccount: tenancy.tenant.hasAccount,
      );
      earlier = earlierPayments.requireValue.map(info.forPayment).toList();
      final canVoid = myProperty.requireValue.access.canVoidPayments && !info.payment.isVoided;
      body = ReceiptView(
        info: info,
        earlier: earlier,
        forTenant: false,
        routeFor: (other) => AppRoutes.receipt(other.propertyId, other.id),
        actions: [if (canVoid) _VoidButton(payment: info.payment)],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt'),
        actions: [
          if (info != null)
            IconButton(
              tooltip: 'Print',
              icon: const Icon(Icons.print_rounded),
              onPressed: () => _print(context, info!, earlier),
            ),
        ],
      ),
      body: body,
    );
  }

  Future<void> _print(BuildContext context, ReceiptInfo info, List<ReceiptInfo> earlier) async {
    try {
      await Printing.layoutPdf(
        name: info.payment.receiptNumber,
        onLayout: (_) => buildReceiptPdf(info, earlier: earlier),
      );
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}

/// The team's "Void this payment" button and its explanation.
class _VoidButton extends ConsumerWidget {
  const _VoidButton({required this.payment});

  final Payment payment;

  Future<void> _void(BuildContext context, WidgetRef ref) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _VoidDialog(),
    );
    if (reason == null || !context.mounted) return;
    try {
      await ref.read(paymentsRepositoryProvider).voidPayment(payment.id, reason);
      // Paid-until and the balance changed: reload everything showing them.
      ref.invalidate(paymentProvider(payment.id));
      ref.invalidate(tenancyPaymentsProvider(payment.tenancyId));
      ref.invalidate(tenancyDetailsProvider(
        (propertyId: payment.propertyId, tenancyId: payment.tenancyId),
      ));
      ref.invalidate(apartmentsProvider(payment.propertyId));
      if (context.mounted) showMessage(context, 'Payment voided');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.overdue,
            side: const BorderSide(color: AppColors.overdue),
          ),
          onPressed: () => _void(context, ref),
          icon: const Icon(Icons.block_rounded),
          label: const Text('Void this payment'),
        ),
        const SizedBox(height: 8),
        Text(
          'Use this if the payment was recorded by mistake. It stays in the '
          'history marked VOID, and the rent dates are recalculated.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// Asks for the reason a payment is voided; returns it, or null if cancelled.
class _VoidDialog extends StatefulWidget {
  const _VoidDialog();

  @override
  State<_VoidDialog> createState() => _VoidDialogState();
}

class _VoidDialogState extends State<_VoidDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reason = _controller.text.trim();
    return AlertDialog(
      icon: const Icon(Icons.block_rounded, color: AppColors.overdue, size: 36),
      title: const Text('Void this payment?'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'Reason',
          hintText: 'e.g. Recorded twice by mistake',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.overdue,
            foregroundColor: Colors.white,
          ),
          onPressed: reason.isEmpty ? null : () => Navigator.of(context).pop(reason),
          child: const Text('Void'),
        ),
      ],
    );
  }
}
