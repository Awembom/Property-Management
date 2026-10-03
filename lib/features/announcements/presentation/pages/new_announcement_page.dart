import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/features/announcements/data/announcements_repository.dart';
import 'package:rental_app/features/announcements/providers/announcements_providers.dart';
import 'package:rental_app/features/apartments/providers/apartments_providers.dart';
import 'package:rental_app/shared/widgets/app_card.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';
import 'package:rental_app/shared/widgets/user_avatar.dart';

/// Write an announcement to all current tenants, or to chosen ones.
/// From a unit page, [tenantId] starts it as a message to that one tenant.
class NewAnnouncementPage extends ConsumerStatefulWidget {
  const NewAnnouncementPage({super.key, required this.propertyId, this.tenantId, this.title, this.body});

  final String propertyId;
  final String? tenantId;

  /// Pre-filled text, e.g. a rent reminder (can still be edited).
  final String? title;
  final String? body;

  @override
  ConsumerState<NewAnnouncementPage> createState() => _NewAnnouncementPageState();
}

class _NewAnnouncementPageState extends ConsumerState<NewAnnouncementPage> {
  final _formKey = GlobalKey<FormState>();
  late final _titleController = TextEditingController(text: widget.title);
  late final _bodyController = TextEditingController(text: widget.body);
  late bool _everyone = widget.tenantId == null;
  late final Set<String> _chosenTenantIds = {?widget.tenantId};
  String? _chooseError;
  bool _sending = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _chooseError =
        !_everyone && _chosenTenantIds.isEmpty ? 'Choose at least one tenant' : null);
    if (!_formKey.currentState!.validate() || _chooseError != null) return;
    setState(() => _sending = true);
    try {
      await ref.read(announcementsRepositoryProvider).send(
            propertyId: widget.propertyId,
            title: _titleController.text.trim(),
            body: _bodyController.text.trim(),
            tenantIds: _everyone ? const [] : _chosenTenantIds.toList(),
          );
      ref.invalidate(propertyAnnouncementsProvider(widget.propertyId));
      if (!mounted) return;
      showMessage(context, 'Announcement sent');
      context.pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Current tenants = the active tenancies of the property's apartments.
    final occupied = (ref.watch(apartmentsProvider(widget.propertyId)).value ?? const [])
        .where((a) => a.activeTenancy != null)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('New announcement')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            TextFormField(
              controller: _titleController,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) => (v?.trim() ?? '').isEmpty ? 'Enter a title' : null,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'e.g. Water cut on Saturday',
                prefixIcon: Icon(Icons.title_rounded),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _bodyController,
              textCapitalization: TextCapitalization.sentences,
              minLines: 4,
              maxLines: 10,
              validator: (v) => (v?.trim() ?? '').isEmpty ? 'Write the message' : null,
              decoration: const InputDecoration(labelText: 'Message', alignLabelWithHint: true),
            ),
            const SizedBox(height: 20),
            Text('Send to', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('All tenants'), icon: Icon(Icons.groups_rounded)),
                ButtonSegment(value: false, label: Text('Choose'), icon: Icon(Icons.person_rounded)),
              ],
              selected: {_everyone},
              onSelectionChanged: (s) => setState(() => _everyone = s.first),
            ),
            if (!_everyone) ...[
              const SizedBox(height: 12),
              if (occupied.isEmpty)
                const Text('No current tenants.')
              else
                AppCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      for (final item in occupied)
                        CheckboxListTile(
                          value: _chosenTenantIds.contains(item.activeTenancy!.tenantId),
                          onChanged: (on) => setState(() {
                            final id = item.activeTenancy!.tenantId;
                            on == true ? _chosenTenantIds.add(id) : _chosenTenantIds.remove(id);
                          }),
                          secondary: UserAvatar(name: item.activeTenancy!.tenantName, size: 36),
                          title: Text(item.activeTenancy!.tenantName),
                          subtitle: Text('Unit ${item.apartment.name}'),
                        ),
                    ],
                  ),
                ),
              if (_chooseError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_chooseError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ],
            const SizedBox(height: 26),
            FilledButton.icon(
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.send_rounded),
              label: const Text('Send announcement'),
            ),
          ],
        ),
      ),
    );
  }
}
