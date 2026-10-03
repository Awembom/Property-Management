import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rental_app/shared/utils/phone.dart';

/// A phone number field with +237 in front: people type only the 9 digits.
/// Read the value with normalizePhone(controller.text); fill it from a saved
/// number with phoneLocalPart(saved).
class PhoneField extends StatelessWidget {
  const PhoneField({
    super.key,
    required this.controller,
    this.label = 'Phone',
    this.required = false,
    this.helperText,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String label;
  final bool required;
  final String? helperText;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.phone,
      textInputAction: textInputAction,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
      validator: phoneValidator(required: required),
      decoration: InputDecoration(
        labelText: required ? label : '$label (optional)',
        hintText: '6XX XX XX XX',
        prefixText: '$kPhonePrefix ',
        helperText: helperText,
        prefixIcon: const Icon(Icons.phone_rounded),
      ),
    );
  }
}
