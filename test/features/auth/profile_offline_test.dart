import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_app/core/offline/outbox.dart';
import 'package:rental_app/features/auth/data/account_type.dart';
import 'package:rental_app/features/auth/data/profile.dart';
import 'package:rental_app/features/auth/data/profile_repository.dart';
import 'package:rental_app/features/auth/providers/auth_providers.dart';

class FakeProfileRepository extends Fake implements ProfileRepository {
  Profile current = const Profile(id: 'u1', username: 'tina', fullName: 'Tina', accountType: AccountType.tenant);
  Profile? savedLocally;

  @override
  Future<Profile> fetchMyProfile() async => current;

  @override
  Future<void> saveLocally(Profile profile) async => savedLocally = profile;

  @override
  Future<Profile?> fetchSavedProfile() async => null;
}

/// An outbox that is always "offline": everything waits.
class OfflineOutbox extends OutboxNotifier {
  final queued = <OutboxItem>[];

  @override
  Future<List<OutboxItem>> build() async => [];

  @override
  Future<bool> sendOrQueue(OutboxItem item) async {
    queued.add(item);
    return false;
  }
}

void main() {
  test('offline: a profile edit shows at once, is kept on the phone and waits to be sent', () async {
    final repository = FakeProfileRepository();
    final outbox = OfflineOutbox();
    final container = ProviderContainer(overrides: [
      profileRepositoryProvider.overrideWithValue(repository),
      outboxProvider.overrideWith(() => outbox),
    ]);
    addTearDown(container.dispose);
    final sub = container.listen(myProfileProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(myProfileProvider.future);

    final sent = await container.read(myProfileProvider.notifier).save(fullName: ' Tina Tenant ', phone: '677 000 000');

    expect(sent, isFalse);
    expect(container.read(myProfileProvider).value?.fullName, 'Tina Tenant');
    expect(container.read(myProfileProvider).value?.username, 'tina');
    expect(repository.savedLocally?.phone, '677 000 000');
    expect(outbox.queued.single.kind, OutboxKind.updateProfile);
    expect(outbox.queued.single.data, {'full_name': 'Tina Tenant', 'phone': '677 000 000'});
  });
}
