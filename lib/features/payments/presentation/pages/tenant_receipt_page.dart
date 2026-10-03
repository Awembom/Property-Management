import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/features/payments/presentation/receipt_pdf.dart';
import 'package:rental_app/features/payments/presentation/widgets/receipt_view.dart';
import 'package:rental_app/features/properties/data/property.dart';
import 'package:rental_app/features/tenant_access/providers/tenant_access_providers.dart';
import 'package:rental_app/shared/widgets/async_error_view.dart';

/// One of my receipts, as the tenant: check it, then confirm it or report a
/// problem (within 24 hours), and share the PDF.
///
/// Everything comes from my rental's details (already loaded, also offline).
class TenantReceiptPage extends ConsumerWidget {
  const TenantReceiptPage({super.key, required this.tenancyId, required this.paymentId});

  final String tenancyId;
  final String paymentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(myRentalDetailsProvider(tenancyId));

    return Scaffold(
      appBar: AppBar(title: const Text('Receipt')),
      body: details.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AsyncErrorView(
          error: error,
          onRetry: () => ref.invalidate(myRentalDetailsProvider(tenancyId)),
        ),
        data: (d) {
          final payment = d.payments.where((p) => p.id == paymentId).firstOrNull;
          if (payment == null) {
            return const Center(child: Text('This receipt wasn\'t found.'));
          }
          final info = ReceiptInfo(
            property: Property(
              id: d.tenancy.propertyId,
              name: d.propertyName,
              address: d.propertyAddress,
              currency: d.currency,
              gracePeriodDays: 0, // not used on receipts
            ),
            tenantName: d.tenantName,
            apartmentName: d.tenancy.apartmentName,
            payment: payment,
            tenantHasAccount: true,
          );
          final earlier = d.payments
              .where((other) =>
                  other.id != payment.id &&
                  other.referenceCode == payment.referenceCode &&
                  other.issuedAt.isBefore(payment.issuedAt))
              .toList()
            ..sort((a, b) => a.issuedAt.compareTo(b.issuedAt));
          return RefreshIndicator(
            onRefresh: () => ref.refresh(myRentalDetailsProvider(tenancyId).future),
            child: ReceiptView(
              info: info,
              earlier: earlier.map(info.forPayment).toList(),
              forTenant: true,
              routeFor: (other) => AppRoutes.myReceipt(tenancyId, other.id),
            ),
          );
        },
      ),
    );
  }
}
