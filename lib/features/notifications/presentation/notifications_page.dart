import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/notifications/data/app_notification.dart';
import 'package:rental_app/features/notifications/data/notifications_repository.dart';
import 'package:rental_app/shared/widgets/app_card.dart';
import 'package:rental_app/shared/widgets/async_error_view.dart';
import 'package:rental_app/shared/widgets/empty_state.dart';
import 'package:rental_app/shared/widgets/icon_bubble.dart';

/// The bell: every notification I got (also the ones I swiped away on the
/// phone), newest first. Opening the page marks them all read.
class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  /// What was unread when the page opened: keeps its dot while I'm here,
  /// even though everything is marked read straight away.
  Set<String>? _newIds;

  @override
  void initState() {
    super.initState();
    // Seen = read, and the bell's number goes back to 0. (Offline: they stay
    // unread until next time.)
    Future.microtask(() async {
      try {
        await ref.read(notificationsRepositoryProvider).markAllRead();
        if (mounted) ref.invalidate(myNotificationsProvider);
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final notifications = ref.watch(myNotificationsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: notifications.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AsyncErrorView(
          error: error,
          onRetry: () => ref.invalidate(myNotificationsProvider),
        ),
        data: (list) {
          _newIds ??= {
            for (final n in list)
              if (!n.isRead) n.id,
          };
          return list.isEmpty
              ? const EmptyState(
                  icon: Icons.notifications_none_rounded,
                  color: AppColors.accent,
                  title: 'Nothing yet',
                  message: 'Rent reminders, bills, receipts and messages will appear here.',
                )
              : RefreshIndicator(
                  onRefresh: () => ref.refresh(myNotificationsProvider.future),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => _NotificationTile(
                      notification: list[index],
                      isNew: _newIds!.contains(list[index].id),
                    ),
                  ),
                );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.isNew});

  final AppNotification notification;

  /// Unread when the page was opened (shown with a dot and in bold).
  final bool isNew;

  /// "14:05", "Yesterday", "3 Oct".
  static String _when(DateTime at) {
    final now = DateTime.now();
    final day = DateUtils.dateOnly(at);
    final today = DateUtils.dateOnly(now);
    if (day == today) return DateFormat('HH:mm').format(at);
    if (today.difference(day).inDays == 1) return 'Yesterday';
    return DateFormat(at.year == now.year ? 'd MMM' : 'd MMM yyyy').format(at);
  }

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final text = Theme.of(context).textTheme;
    return AppCard(
      padding: const EdgeInsets.all(12),
      onTap: n.route == null ? null : () => context.push(n.route!),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBubble(icon: n.icon, color: n.color, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        n.title,
                        style: text.titleSmall?.copyWith(
                          fontWeight: isNew ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(_when(n.createdAt), style: text.bodySmall),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  n.body,
                  style: text.bodySmall,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (isNew)
            Container(
              margin: const EdgeInsets.only(left: 8, top: 6),
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }
}
