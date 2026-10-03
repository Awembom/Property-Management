import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/tickets/data/ticket.dart';
import 'package:rental_app/core/offline/outbox.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';

/// A tenant reports an issue with their home.
class NewTicketPage extends ConsumerStatefulWidget {
  const NewTicketPage({super.key, required this.tenancyId});

  final String tenancyId;

  @override
  ConsumerState<NewTicketPage> createState() => _NewTicketPageState();
}

class _NewTicketPageState extends ConsumerState<NewTicketPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  TicketCategory _category = TicketCategory.plumbing;
  bool _busy = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      // Offline, it waits in the outbox and is sent automatically later.
      final sent = await ref.read(outboxProvider.notifier).sendOrQueue(OutboxItem.newTicket(
            tenancyId: widget.tenancyId,
            title: _titleController.text.trim(),
            description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
            category: _category,
          ));
      if (!mounted) return;
      showMessage(
        context,
        sent
            ? 'Issue reported. Your landlord will see it.'
            : 'You\'re offline. The issue is saved and will be sent when you\'re back online.',
      );
      context.pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report an issue')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text('What is it about?', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in TicketCategory.pickable)
                  ChoiceChip(
                    avatar: Icon(c.icon, size: 18, color: _category == c ? AppColors.primary : AppColors.muted),
                    label: Text(c.label),
                    selected: _category == c,
                    onSelected: (_) => setState(() => _category = c),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _titleController,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) => (v?.trim() ?? '').isEmpty ? 'Say in a few words what\'s wrong' : null,
              decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. Kitchen tap is leaking'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _descriptionController,
              textCapitalization: TextCapitalization.sentences,
              minLines: 4,
              maxLines: 10,
              decoration: const InputDecoration(
                labelText: 'Details (optional)',
                hintText: 'Where, since when, how bad…',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 26),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: const Icon(Icons.send_rounded),
              label: const Text('Send to my landlord'),
            ),
          ],
        ),
      ),
    );
  }
}
