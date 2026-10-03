import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/announcements/presentation/pages/announcements_page.dart';
import 'package:rental_app/features/announcements/providers/announcements_providers.dart';
import 'package:rental_app/shared/widgets/async_error_view.dart';
import 'package:rental_app/shared/widgets/empty_state.dart';

/// A tenant's announcements from their landlords, newest first.
class MyAnnouncementsPage extends ConsumerWidget {
  const MyAnnouncementsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(myAnnouncementsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Announcements')),
      body: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AsyncErrorView(error: error, onRetry: () => ref.invalidate(myAnnouncementsProvider)),
        data: (items) => RefreshIndicator(
          onRefresh: () => ref.refresh(myAnnouncementsProvider.future),
          child: items.isEmpty
              ? ListView(children: const [
                  EmptyState(
                    icon: Icons.campaign_rounded,
                    color: AppColors.primary,
                    title: 'No announcements',
                    message: 'Messages from your landlord appear here.',
                  ),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => AnnouncementCard(announcement: items[i]),
                ),
        ),
      ),
    );
  }
}
