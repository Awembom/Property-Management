import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/features/tenant_access/data/my_rental.dart';
import 'package:rental_app/features/tenant_access/data/my_rental_details.dart';
import 'package:rental_app/features/tenant_access/data/tenant_access_repository.dart';
import 'package:rental_app/features/tenant_access/data/tenant_invite.dart';

/// The open invite code of one tenant contact (null if none).
final openInviteProvider =
    FutureProvider.autoDispose.family<TenantInvite?, String>((ref, tenantId) {
  return ref.watch(tenantAccessRepositoryProvider).fetchOpenInvite(tenantId);
});

/// What the logged-in user rents as a tenant.
final myRentalsProvider = FutureProvider.autoDispose<List<MyRental>>((ref) {
  return ref.watch(tenantAccessRepositoryProvider).fetchMyRentals();
});

/// One rental of the logged-in tenant (rent, balance, payments).
final myRentalDetailsProvider =
    FutureProvider.autoDispose.family<MyRentalDetails, String>((ref, tenancyId) {
  return ref.watch(tenantAccessRepositoryProvider).fetchMyRentalDetails(tenancyId);
});
