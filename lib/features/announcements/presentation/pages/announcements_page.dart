import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/announcements/data/announcement.dart';
import 'package:rental_app/features/announcements/providers/announcements_providers.dart';
import 'package:rental_app/shared/utils/dates.dart';
import 'package:rental_app/shared/widgets/app_card.dart';
import 'package:rental_app/shared/widgets/async_error_view.dart';
import 'package:rental_app/shared/widgets/empty_state.dart';
import 'package:rental_app/shared/widgets/status_pill.dart';

/// The team's list of announcements for a property, with "New announcement".
class AnnouncementsPage extends ConsumerWidget {
  const AnnouncementsPage({super.key, required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final announcements = ref.watch(propertyAnnouncementsProvider(propertyId));
    return Scaffold(
      appBar: AppBar(title: const Text('Announcements')),
      body: announcements.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AsyncErrorView(
          error: error,
          onRetry: () => ref.invalidate(propertyAnnouncementsProvider(propertyId)),
        ),
        data: (list) => RefreshIndicator(
          onRefresh: () => ref.refresh(propertyAnnouncementsProvider(propertyId).future),
          child: list.isEmpty
              ? ListView(children: const [
                  EmptyState(
                    icon: Icons.campaign_rounded,
                    color: AppColors.primary,
                    title: 'No announcements yet',
                    message: 'Tell all your tenants, or just some, about water cuts, '
                        'repairs, rent reminders and more.',
                  ),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => AnnouncementCard(announcement: list[index], showAudience: true),
                ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.newAnnouncement(propertyId)),
        icon: const Icon(Icons.campaign_rounded),
        label: const Text('New announcement'),
      ),
    );
  }
}

/// One announcement: title, message, date (and who it went to, for the team).
class AnnouncementCard extends StatelessWidget {
  const AnnouncementCard({super.key, required this.announcement, this.showAudience = false});

  final Announcement announcement;
  final bool showAudience;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.soft(AppColors.primary)),
                child: const Icon(Icons.campaign_rounded, size: 20, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(announcement.title, style: text.titleSmall)),
              Text(formatDate(announcement.createdAt), style: text.bodySmall),
            ],
          ),
          const SizedBox(height: 10),
          Text(announcement.body),
          if (showAudience) ...[
            const SizedBox(height: 10),
            StatusPill(
              label: announcement.toEveryone
                  ? 'All tenants'
                  : '${announcement.recipientCount} chosen tenant${announcement.recipientCount == 1 ? '' : 's'}',
              color: announcement.toEveryone ? AppColors.accent : AppColors.primary,
              icon: announcement.toEveryone ? Icons.groups_rounded : Icons.person_rounded,
            ),
          ],
        ],
      ),
    );
  }
}
