/// One line of the activity log (`activity_log`): who changed what, when,
/// with the row before ([oldData]) and after ([newData]) as JSON.
class ActivityEntry {
  const ActivityEntry({
    required this.id,
    required this.happenedAt,
    required this.tableName,
    required this.action,
    this.actorId,
    this.propertyId,
    this.rowId,
    this.oldData,
    this.newData,
  });

  final int id;
  final DateTime happenedAt;

  /// e.g. 'payments', 'tenancies', or 'auth' for password resets.
  final String tableName;

  /// 'INSERT', 'UPDATE', 'DELETE', or e.g. 'password_reset'.
  final String action;
  final String? actorId;
  final String? propertyId;
  final String? rowId;
  final Map<String, dynamic>? oldData;
  final Map<String, dynamic>? newData;

  static const columns =
      'id, happened_at, actor_id, property_id, table_name, action, row_id, old_data, new_data';

  factory ActivityEntry.fromJson(Map<String, dynamic> json) {
    return ActivityEntry(
      id: json['id'] as int,
      happenedAt: DateTime.parse(json['happened_at'] as String).toLocal(),
      actorId: json['actor_id'] as String?,
      propertyId: json['property_id'] as String?,
      tableName: json['table_name'] as String,
      action: json['action'] as String,
      rowId: json['row_id'] as String?,
      oldData: json['old_data'] as Map<String, dynamic>?,
      newData: json['new_data'] as Map<String, dynamic>?,
    );
  }

  /// The row as it is now (after), or as it was (if deleted).
  Map<String, dynamic> get row => newData ?? oldData ?? const {};

  /// Fields an UPDATE changed: (name, before, after). Bookkeeping columns
  /// like created_at are left out.
  List<(String, Object?, Object?)> get changes {
    final before = oldData;
    final after = newData;
    if (before == null || after == null) return const [];
    const ignored = {'created_at', 'updated_at', 'created_by'};
    return [
      for (final key in after.keys)
        if (!ignored.contains(key) && before[key]?.toString() != after[key]?.toString())
          (key, before[key], after[key]),
    ];
  }
}
