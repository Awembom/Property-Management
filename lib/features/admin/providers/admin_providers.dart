import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/features/admin/data/activity_entry.dart';
import 'package:rental_app/features/admin/data/admin_models.dart';
import 'package:rental_app/features/admin/data/admin_repository.dart';

/// Is the logged-in user the app admin? (Decides whether the Admin button
/// shows; the database checks again for everything the admin does.)
final isAppAdminProvider = FutureProvider.autoDispose<bool>((ref) {
  return ref.watch(adminRepositoryProvider).isAppAdmin();
});

final activityProvider = FutureProvider.autoDispose<List<ActivityEntry>>((ref) {
  return ref.watch(adminRepositoryProvider).fetchActivity();
});

final adminPropertiesProvider = FutureProvider.autoDispose<List<AdminProperty>>((ref) {
  return ref.watch(adminRepositoryProvider).fetchProperties();
});

final adminPeopleProvider = FutureProvider.autoDispose<List<AdminPerson>>((ref) {
  return ref.watch(adminRepositoryProvider).fetchPeople();
});
