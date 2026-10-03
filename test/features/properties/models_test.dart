import 'package:flutter_test/flutter_test.dart';
import 'package:rental_app/features/properties/data/member.dart';
import 'package:rental_app/features/properties/data/membership_role.dart';
import 'package:rental_app/features/properties/data/property.dart';

void main() {
  test('MyProperty parses a memberships row with embedded property', () {
    final myProperty = MyProperty.fromMembershipJson({
      'role': 'manager',
      'can_record_payments': false,
      'property': {
        'id': 'p1',
        'name': 'Sunset Court',
        'address': null,
        'currency': 'XAF',
        'grace_period_days': 7,
      },
    });
    expect(myProperty.property.name, 'Sunset Court');
    expect(myProperty.property.gracePeriodDays, 7);
    expect(myProperty.access.role, MembershipRole.manager);
  });

  test('Property.toUpdateJson uses database column names', () {
    const property = Property(
      id: 'p1',
      name: 'A',
      currency: 'USD',
      gracePeriodDays: 3,
    );
    expect(property.toUpdateJson(), {
      'name': 'A',
      'address': null,
      'currency': 'USD',
      'grace_period_days': 3,
      'contact_phone': null,
    });
  });

  test(
    'Member parses embedded profile; displayName falls back to username',
    () {
      final withName = Member.fromJson({
        'id': 'm1',
        'user_id': 'u1',
        'role': 'caretaker',
        'can_record_payments': true,
        'profile': {'full_name': 'Jo', 'username': 'jo'},
      });
      final noName = Member.fromJson({
        'id': 'm2',
        'user_id': 'u2',
        'role': 'owner',
        'can_record_payments': false,
        'profile': {'full_name': null, 'username': 'sam'},
      });
      expect(withName.displayName, 'Jo');
      expect(withName.canRecordPayments, isTrue);
      expect(noName.displayName, 'sam');
    },
  );

  // Mirrors the permissions table in CLAUDE.md.
  group('PropertyAccess', () {
    const owner = PropertyAccess(
      role: MembershipRole.owner,
      canRecordPaymentsFlag: false,
    );
    const manager = PropertyAccess(
      role: MembershipRole.manager,
      canRecordPaymentsFlag: false,
    );
    const caretaker = PropertyAccess(
      role: MembershipRole.caretaker,
      canRecordPaymentsFlag: false,
    );
    const payingCaretaker = PropertyAccess(
      role: MembershipRole.caretaker,
      canRecordPaymentsFlag: true,
    );

    test('only owners delete property and manage members', () {
      expect([owner, manager, caretaker].map((a) => a.canDeleteProperty), [
        true,
        false,
        false,
      ]);
      expect([owner, manager, caretaker].map((a) => a.canManageMembers), [
        true,
        false,
        false,
      ]);
    });

    test('owners and managers edit property, apartments, tenancies', () {
      for (final a in [owner, manager]) {
        expect(
          a.canEditProperty && a.canManageApartments && a.canManageTenancies,
          isTrue,
        );
      }
      expect(
        caretaker.canEditProperty ||
            caretaker.canManageApartments ||
            caretaker.canManageTenancies,
        isFalse,
      );
    });

    test('caretakers record payments only with the flag, never see money', () {
      expect(caretaker.canRecordPayments, isFalse);
      expect(payingCaretaker.canRecordPayments, isTrue);
      expect(caretaker.canSeeMoney || payingCaretaker.canSeeMoney, isFalse);
      expect(owner.canSeeMoney && manager.canSeeMoney, isTrue);
    });
  });
}
