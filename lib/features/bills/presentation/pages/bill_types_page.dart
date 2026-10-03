import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/bills/data/bills_repository.dart';
import 'package:rental_app/features/bills/providers/bills_providers.dart';
import 'package:rental_app/shared/widgets/app_card.dart';
import 'package:rental_app/shared/widgets/async_error_view.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';

/// Which bills this property uses: switch Water / Electricity on or off, add
/// custom types (e.g. Internet, Security), delete unused custom ones.
class BillTypesPage extends ConsumerWidget {
  const BillTypesPage({super.key, required this.propertyId});

  final String propertyId;

  Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() action) async {
    try {
      await action();
      ref.invalidate(billTypesProvider(propertyId));
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(context: context, builder: (_) => const _NameDialog());
    if (name == null || !context.mounted) return;
    await _run(context, ref, () => ref.read(billsRepositoryProvider).addType(propertyId, name));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final types = ref.watch(billTypesProvider(propertyId));
    // Read inside the button handlers, never while drawing.
    BillsRepository repository() => ref.read(billsRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Bill types')),
      body: types.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AsyncErrorView(error: error, onRetry: () => ref.invalidate(billTypesProvider(propertyId))),
        data: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            Text(
              'Switched-off types can\'t be used for new bills. Water and Electricity '
              'come with every property.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final type in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
                  child: Row(
                    children: [
                      Icon(type.icon, color: type.enabled ? AppColors.primary : AppColors.muted),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(type.name, style: Theme.of(context).textTheme.titleSmall),
                            Text(type.isStandard ? 'Standard' : 'Custom', style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                      Switch(
                        value: type.enabled,
                        onChanged: (on) => _run(context, ref, () => repository().setTypeEnabled(type.id, on)),
                      ),
                      if (!type.isStandard)
                        IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () => _run(context, ref, () => repository().deleteType(type.id)),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Custom bill type'),
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog();

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = _controller.text.trim();
    return AlertDialog(
      title: const Text('New bill type'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Internet, Security, Gas'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: name.isEmpty ? null : () => Navigator.of(context).pop(name),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
