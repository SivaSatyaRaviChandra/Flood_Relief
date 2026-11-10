/// A stepper for integer counts (people, arrivals, capacity).
///
/// Extracted from the SOS wizard because the flood report, help request and
/// shelter screens all need the same control, and a counter that silently
/// clamps differently per screen is an easy source of inconsistent data.
library;

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

class CounterField extends StatelessWidget {
  const CounterField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max,
    this.suffix,
    this.helper,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final int min;

  /// Upper bound. `null` means unbounded; the increment button is then always
  /// enabled so the value is never silently pinned.
  final int? max;

  /// Optional unit shown after the number, e.g. "people".
  final String? suffix;

  final String? helper;

  bool get _canDecrement => value > min;
  bool get _canIncrement => max == null || value < max!;

  @override
  Widget build(BuildContext context) {
    final canDecrement = _canDecrement;
    final canIncrement = _canIncrement;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (helper != null)
                    Text(
                      helper!,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              onPressed: canDecrement
                  ? () {
                      // Clamp inside the handler too: a rapid double-tap must
                      // not be able to push the value below the minimum.
                      final next = (value - 1) < min ? min : value - 1;
                      if (next != value) onChanged(next);
                    }
                  : null,
              icon: const Icon(Icons.remove_circle_outline),
              tooltip: 'Decrease $label',
            ),
            SizedBox(
              width: 56,
              child: Text(
                suffix == null ? '$value' : '$value',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              onPressed: canIncrement
                  ? () {
                      final next = value + 1;
                      if (max != null && next > max!) return;
                      onChanged(next);
                    }
                  : null,
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Increase $label',
            ),
          ],
        ),
        if (suffix != null)
          Padding(
            padding: const EdgeInsets.only(left: 2, top: 0),
            child: Text(
              '$value $suffix',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// A text field that only accepts whole numbers, used for capacity/occupancy
/// entry so a stray letter cannot be stored as a count.
class NumberTextField extends StatelessWidget {
  const NumberTextField({
    super.key,
    required this.controller,
    required this.label,
    this.helper,
    this.suffixText,
  });

  final TextEditingController controller;
  final String label;
  final String? helper;
  final String? suffixText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 2,
        suffixText: suffixText,
      ),
    );
  }
}
