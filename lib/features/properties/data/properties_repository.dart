import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/supabase/supabase_providers.dart';
import 'package:rental_app/features/properties/data/member.dart';
import 'package:rental_app/features/properties/data/membership_role.dart';
import 'package:rental_app/features/properties/data/property.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Columns we load for a property, embedded in a memberships query.
const _propertyColumns = 'id, name, address, currency, grace_period_days';

/// All Supabase calls for properties and their members.
///
/// Permissions are enforced by the database (RLS + functions). If the user
/// isn't allowed to do something, these calls throw with the database's
/// message, e.g. "A property must keep at least one owner."
class PropertiesRepository {
  PropertiesRepository(this._client);

  final SupabaseClient _client;

  String get _userId {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Not logged in');
    return user.id;
  }

  // ---------- properties ----------

  /// Properties where I'm staff, with my role on each, sorted by name.
  /// We start from `memberships` (my rows) and embed the property, so the
  /// role comes back in the same query.
  Future<List<MyProperty>> fetchMyProperties() async {
    final rows = await _client
        .from('memberships')
        .select('role, can_record_payments, property:properties($_propertyColumns)')
        .eq('user_id', _userId);

    final properties = rows.map(MyProperty.fromMembershipJson).toList()
      ..sort((a, b) => a.property.name.toLowerCase().compareTo(b.property.name.toLowerCase()));
    return properties;
  }

  /// One property with my role on it. Throws if I'm not a member.
  Future<MyProperty> fetchMyProperty(String propertyId) async {
    final row = await _client
        .from('memberships')
        .select('role, can_record_payments, property:properties($_propertyColumns)')
        .eq('user_id', _userId)
        .eq('property_id', propertyId)
        .maybeSingle();
    if (row == null) throw StateError('Property not found');
    return MyProperty.fromMembershipJson(row);
  }

  /// Creates a property; the database makes me its owner in the same step.
  Future<Property> createProperty({
    required String name,
    required String currency,
    String? address,
    required int gracePeriodDays,
  }) async {
    final row = await _client.rpc('create_property', params: {
      'p_name': name,
      'p_currency': currency,
      'p_address': address,
      'p_grace_period_days': gracePeriodDays,
    });
    return Property.fromJson(row as Map<String, dynamic>);
  }

  Future<void> updateProperty(Property property) async {
    await _client
        .from('properties')
        .update(property.toUpdateJson())
        .eq('id', property.id);
  }

  /// Deletes a property and EVERYTHING in it (owners only).
  Future<void> deleteProperty(String propertyId) async {
    // `.select('id')` returns the deleted rows. RLS doesn't raise an error
    // when you're not allowed; it just deletes nothing, so we check.
    final deleted = await _client
        .from('properties')
        .delete()
        .eq('id', propertyId)
        .select('id');
    if (deleted.isEmpty) {
      throw StateError('You are not allowed to delete this property.');
    }
  }

  // ---------- members ----------

  Future<List<Member>> fetchMembers(String propertyId) async {
    final rows = await _client
        .from('memberships')
        .select('id, user_id, role, can_record_payments, profile:profiles(full_name, email)')
        .eq('property_id', propertyId);

    // Owners first, then managers, then caretakers; alphabetical within each.
    final members = rows.map(Member.fromJson).toList()
      ..sort((a, b) {
        final byRole = a.role.index.compareTo(b.role.index);
        if (byRole != 0) return byRole;
        return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
      });
    return members;
  }

  /// Adds someone who already has an account, by email (owners only).
  Future<void> addMember({
    required String propertyId,
    required String email,
    required MembershipRole role,
    required bool canRecordPayments,
  }) async {
    await _client.rpc('add_property_member', params: {
      'p_property_id': propertyId,
      'p_email': email,
      'p_role': role.toJson(),
      'p_can_record_payments': canRecordPayments,
    });
  }

  Future<void> updateMember({
    required String membershipId,
    required MembershipRole role,
    required bool canRecordPayments,
  }) async {
    final updated = await _client
        .from('memberships')
        .update({
          'role': role.toJson(),
          // The toggle only applies to caretakers.
          'can_record_payments': role == MembershipRole.caretaker && canRecordPayments,
        })
        .eq('id', membershipId)
        .select('id');
    if (updated.isEmpty) throw StateError('Only owners can change members.');
  }

  Future<void> removeMember(String membershipId) async {
    final deleted = await _client
        .from('memberships')
        .delete()
        .eq('id', membershipId)
        .select('id');
    if (deleted.isEmpty) throw StateError('Only owners can remove members.');
  }
}

final propertiesRepositoryProvider = Provider<PropertiesRepository>((ref) {
  return PropertiesRepository(ref.watch(supabaseClientProvider));
});
