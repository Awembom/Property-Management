import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/features/announcements/data/announcement.dart';
import 'package:rental_app/features/announcements/data/announcements_repository.dart';
import 'package:rental_app/features/tenant_access/providers/tenant_access_providers.dart';

/// A property's announcements (team).
final propertyAnnouncementsProvider =
    FutureProvider.autoDispose.family<List<Announcement>, String>((ref, propertyId) {
  return ref.watch(announcementsRepositoryProvider).fetchForProperty(propertyId);
});

/// Announcements for me as a tenant (from the properties I rent in).
final myAnnouncementsProvider = FutureProvider.autoDispose<List<Announcement>>((ref) async {
  final rentals = await ref.watch(myRentalsProvider.future);
  final propertyIds = rentals.map((r) => r.tenancy.propertyId).toSet().toList();
  return ref.watch(announcementsRepositoryProvider).fetchMine(propertyIds);
});
