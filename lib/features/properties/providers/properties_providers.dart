import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/features/properties/data/member.dart';
import 'package:rental_app/features/properties/data/properties_repository.dart';
import 'package:rental_app/features/properties/data/property.dart';

// Data providers for the properties feature.
//
// - FutureProvider: loads data once and exposes it as AsyncValue
//   (loading / error / data), which screens display with `.when(...)`.
// - autoDispose: the data is dropped when no screen shows it, so it is
//   fresh the next time.
// - family: one provider per id, e.g. myPropertyProvider('abc').
//
// After changing data (create, edit, delete...), screens call
// `ref.invalidate(someProvider)` so it reloads from the database.

/// All properties where I'm staff.
final myPropertiesProvider = FutureProvider.autoDispose<List<MyProperty>>((ref) {
  return ref.watch(propertiesRepositoryProvider).fetchMyProperties();
});

/// One property (by id) with my role on it.
final myPropertyProvider =
    FutureProvider.autoDispose.family<MyProperty, String>((ref, propertyId) {
  return ref.watch(propertiesRepositoryProvider).fetchMyProperty(propertyId);
});

/// Staff members of one property.
final propertyMembersProvider =
    FutureProvider.autoDispose.family<List<Member>, String>((ref, propertyId) {
  return ref.watch(propertiesRepositoryProvider).fetchMembers(propertyId);
});
