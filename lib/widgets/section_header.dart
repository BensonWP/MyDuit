import 'package:flutter/material.dart';

/// Judul seksi dengan trailing opsional (mis. [FlowToggle]).
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
