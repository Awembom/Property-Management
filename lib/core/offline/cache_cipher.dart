import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Gives each account its own secret key for the data saved on the phone.
abstract class KeyVault {
  Future<List<int>> keyFor(String account);
}

/// Keys live in the phone's secure keystore (Android Keystore), not in the
/// app's files: copying the offline database off the phone doesn't reveal
/// anything. A key is kept after logout, so logging back into the SAME
/// account opens its saved data again; another account has another key.
class SecureKeyVault implements KeyVault {
  SecureKeyVault([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final _keys = <String, List<int>>{};

  @override
  Future<List<int>> keyFor(String account) async {
    final known = _keys[account];
    if (known != null) return known;
    final name = 'offline_key_$account';
    final stored = await _storage.read(key: name);
    final key = stored != null
        ? base64Decode(stored)
        : await (await AesGcm.with256bits().newSecretKey()).extractBytes();
    if (stored == null) await _storage.write(key: name, value: base64Encode(key));
    return _keys[account] = key;
  }
}

/// Fixed keys, for tests.
class MemoryKeyVault implements KeyVault {
  final _keys = <String, List<int>>{};

  @override
  Future<List<int>> keyFor(String account) async => _keys.putIfAbsent(account, () {
        final seed = account.codeUnits.fold<int>(17, (sum, c) => (sum * 31 + c) % 65521);
        return List<int>.generate(32, (i) => (seed * (i + 3) + i * 7) % 256);
      });
}

/// Encrypts saved data with AES-256-GCM (which also detects tampering).
/// Stored bytes are nonce + ciphertext + MAC.
class CacheCipher {
  CacheCipher(this._vault);

  final KeyVault _vault;
  final _algorithm = AesGcm.with256bits();

  Future<Uint8List> encrypt(String account, String text) async {
    final box = await _algorithm.encrypt(
      utf8.encode(text),
      secretKey: SecretKey(await _vault.keyFor(account)),
    );
    return Uint8List.fromList(box.concatenation());
  }

  /// Throws if the data was encrypted with another account's key or changed.
  Future<String> decrypt(String account, Uint8List data) async {
    final box = SecretBox.fromConcatenation(
      data,
      nonceLength: _algorithm.nonceLength,
      macLength: _algorithm.macAlgorithm.macLength,
    );
    final clear = await _algorithm.decrypt(box, secretKey: SecretKey(await _vault.keyFor(account)));
    return utf8.decode(clear);
  }
}
