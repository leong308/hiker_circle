// AuthBrandPanel renders the HikerCircle app identity above authentication controls.
import 'package:flutter/material.dart';

class AuthBrandPanel extends StatelessWidget {
  const AuthBrandPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Image.asset(
            'assets/icons/AppIcon-Android-1024.png',
            width: 44,
            height: 44,
            excludeFromSemantics: true,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            'HikerCircle',
            style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFFE2EDE1)
                  : const Color(0xFF243E2E),
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
            ),
          ),
        ),
      ],
    );
  }
}
