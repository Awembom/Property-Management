import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Pick a number of months: a row of buttons for common choices plus
/// "Custom", which shows a box to type any number from [min] to [max].
///
/// Used for "how often does the tenant pay" and "how many months is this
/// payment for". The parent keeps the value; this widget reports changes.
class MonthsPicker extends StatefulWidget {
  const MonthsPicker({
    super.key,
    required this.value,
    required this.onChanged,
    required this.presets,
    required this.labelFor,
    this.min = 1,
    this.max = 24,
    this.color,
  });

  /// Currently chosen number of months.
  final int value;
  final ValueChanged<int> onChanged;

  /// The buttons shown, e.g. [1, 3, 6, 12].
  final List<int> presets;

  /// Button text for a preset, e.g. 3 -> 'Every 3 months'.
  final String Function(int months) labelFor;

  final int min;
  final int max;
  final Color? color;

  @override
  State<MonthsPicker> createState() => _MonthsPickerState();
}

class _MonthsPickerState extends State<MonthsPicker> {
  late bool _custom = !widget.presets.contains(widget.value);
  late final _controller = TextEditingController(text: _custom ? '${widget.value}' : '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedColor = widget.color?.withValues(alpha: 0.18);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final months in widget.presets)
              ChoiceChip(
                label: Text(widget.labelFor(months)),
                selected: !_custom && widget.value == months,
                selectedColor: selectedColor,
                onSelected: (_) {
                  setState(() => _custom = false);
                  widget.onChanged(months);
                },
              ),
            ChoiceChip(
              label: const Text('Custom'),
              selected: _custom,
              selectedColor: selectedColor,
              onSelected: (_) {
                setState(() {
                  _custom = true;
                  _controller.text = '${widget.value}';
                });
              },
            ),
          ],
        ),
        if (_custom) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Number of months',
              helperText: '${widget.min} to ${widget.max}',
              prefixIcon: const Icon(Icons.tune_rounded),
            ),
            validator: (text) {
              final months = int.tryParse(text ?? '');
              if (months == null || months < widget.min || months > widget.max) {
                return 'Enter ${widget.min} to ${widget.max}';
              }
              return null;
            },
            onChanged: (text) {
              final months = int.tryParse(text);
              if (months != null && months >= widget.min && months <= widget.max) {
                widget.onChanged(months);
              }
            },
          ),
        ],
      ],
    );
  }
}
