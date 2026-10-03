import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// One saved thing: encrypted bytes and when they were saved.
class StoredEntry {
  const StoredEntry({required this.key, required this.data, required this.savedAt});

  final String key;
  final Uint8List data;
  final DateTime savedAt;
}

/// The phone's own storage for offline use. Everything is stored per account
/// and already encrypted (see CacheCipher); this class only keeps bytes.
///
/// - cache:  the last data loaded for each query, replaced by fresher data.
/// - outbox: things done offline (ticket messages, ...) waiting to be sent.
abstract class LocalStore {
  Future<StoredEntry?> read(String account, String key);
  Future<void> write(String account, String key, Uint8List data, DateTime savedAt);

  /// When this account's data was last saved, or null if never.
  Future<DateTime?> latestSave(String account);

  /// Oldest first.
  Future<List<StoredEntry>> outbox(String account);
  Future<void> addToOutbox(String account, String id, Uint8List data, DateTime createdAt);
  Future<void> removeFromOutbox(String id);
}

/// [LocalStore] in an SQLite file inside the app's private storage.
class SqliteLocalStore implements LocalStore {
  Database? _db;

  Future<Database> get _open async {
    return _db ??= await openDatabase(
      p.join(await getDatabasesPath(), 'offline.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          create table cache (
            account  text not null,
            key      text not null,
            data     blob not null,
            saved_at integer not null,
            primary key (account, key)
          )''');
        await db.execute('''
          create table outbox (
            id         text primary key,
            account    text not null,
            data       blob not null,
            created_at integer not null
          )''');
      },
    );
  }

  @override
  Future<StoredEntry?> read(String account, String key) async {
    final rows = await (await _open).query(
      'cache',
      columns: ['data', 'saved_at'],
      where: 'account = ? and key = ?',
      whereArgs: [account, key],
    );
    if (rows.isEmpty) return null;
    return StoredEntry(
      key: key,
      data: rows.first['data'] as Uint8List,
      savedAt: DateTime.fromMillisecondsSinceEpoch(rows.first['saved_at'] as int),
    );
  }

  @override
  Future<void> write(String account, String key, Uint8List data, DateTime savedAt) async {
    await (await _open).insert(
      'cache',
      {'account': account, 'key': key, 'data': data, 'saved_at': savedAt.millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<DateTime?> latestSave(String account) async {
    final rows = await (await _open)
        .rawQuery('select max(saved_at) as latest from cache where account = ?', [account]);
    final latest = rows.first['latest'] as int?;
    return latest == null ? null : DateTime.fromMillisecondsSinceEpoch(latest);
  }

  @override
  Future<List<StoredEntry>> outbox(String account) async {
    final rows = await (await _open).query(
      'outbox',
      where: 'account = ?',
      whereArgs: [account],
      orderBy: 'created_at',
    );
    return [
      for (final row in rows)
        StoredEntry(
          key: row['id'] as String,
          data: row['data'] as Uint8List,
          savedAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        ),
    ];
  }

  @override
  Future<void> addToOutbox(String account, String id, Uint8List data, DateTime createdAt) async {
    await (await _open).insert('outbox', {
      'id': id,
      'account': account,
      'data': data,
      'created_at': createdAt.millisecondsSinceEpoch,
    });
  }

  @override
  Future<void> removeFromOutbox(String id) async {
    await (await _open).delete('outbox', where: 'id = ?', whereArgs: [id]);
  }
}

/// [LocalStore] in memory, for tests.
class MemoryLocalStore implements LocalStore {
  final _cache = <String, StoredEntry>{};
  final _outbox = <String, (String, StoredEntry)>{};

  @override
  Future<StoredEntry?> read(String account, String key) async => _cache['$account|$key'];

  @override
  Future<void> write(String account, String key, Uint8List data, DateTime savedAt) async {
    _cache['$account|$key'] = StoredEntry(key: key, data: data, savedAt: savedAt);
  }

  @override
  Future<DateTime?> latestSave(String account) async {
    DateTime? latest;
    for (final entry in _cache.entries) {
      if (!entry.key.startsWith('$account|')) continue;
      final at = entry.value.savedAt;
      if (latest == null || at.isAfter(latest)) latest = at;
    }
    return latest;
  }

  @override
  Future<List<StoredEntry>> outbox(String account) async {
    return [
      for (final (owner, entry) in _outbox.values)
        if (owner == account) entry,
    ]..sort((a, b) => a.savedAt.compareTo(b.savedAt));
  }

  @override
  Future<void> addToOutbox(String account, String id, Uint8List data, DateTime createdAt) async {
    _outbox[id] = (account, StoredEntry(key: id, data: data, savedAt: createdAt));
  }

  @override
  Future<void> removeFromOutbox(String id) async {
    _outbox.remove(id);
  }
}
