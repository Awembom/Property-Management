/// A message from the team to tenants (`announcements`).
class Announcement {
  const Announcement({
    required this.id,
    required this.propertyId,
    required this.title,
    required this.body,
    required this.toEveryone,
    required this.createdAt,
    this.recipientCount = 0,
  });

  final String id;
  final String propertyId;
  final String title;
  final String body;

  /// true = every current tenant; false = only chosen tenants.
  final bool toEveryone;
  final DateTime createdAt;

  /// How many chosen tenants (when not [toEveryone]).
  final int recipientCount;

  static const columns =
      'id, property_id, title, body, audience, created_at, recipients:announcement_recipients(count)';

  factory Announcement.fromJson(Map<String, dynamic> json) {
    final recipients = json['recipients'] as List?;
    return Announcement(
      id: json['id'] as String,
      propertyId: json['property_id'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      toEveryone: json['audience'] == 'all',
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      recipientCount: recipients == null || recipients.isEmpty
          ? 0
          : (recipients.first as Map<String, dynamic>)['count'] as int,
    );
  }
}
