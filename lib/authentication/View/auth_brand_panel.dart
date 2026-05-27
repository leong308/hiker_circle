import 'package:flutter/material.dart';

class AuthBrandPanel extends StatelessWidget {
  const AuthBrandPanel({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    const textGreen = Color(0xFF17382C);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.terrain, color: color, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'HikerCircle',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: textGreen,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Emergency and alert assistant for hiker safety',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF4E6A59),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
