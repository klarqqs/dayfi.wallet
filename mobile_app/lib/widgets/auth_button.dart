// lib/widgets/auth_button.dart
import 'package:flutter/material.dart';

class AuthButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isDisabled;
  final String? loadingText;
  final bool isValid;

  const AuthButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.isDisabled = false,
    this.loadingText,
    this.isValid = true,
  });

  @override
  Widget build(BuildContext context) {
    final isButtonDisabled = isDisabled || onPressed == null;
    final opacityValue = (isValid && !isButtonDisabled) ? 0.90 : 0.45;

    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        minimumSize: Size(MediaQuery.of(context).size.width, 48),
        side: BorderSide(
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withOpacity(opacityValue),
          width: 1.5,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: isButtonDisabled ? null : onPressed,
      label: Text(
        isLoading && (loadingText?.isNotEmpty ?? false) ? loadingText! : label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withOpacity(opacityValue),
          fontSize: 15,
        ),
      ),
    );
  }
}
