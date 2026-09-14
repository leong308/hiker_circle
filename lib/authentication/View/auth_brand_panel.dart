import 'package:flutter/material.dart';

class AuthBrandPanel extends StatelessWidget {
  const AuthBrandPanel({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 26),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF234E38), Color(0xFF102C22)],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.asset(
                  'assets/icons/AppIcon-Android-1024.png',
                  width: 58,
                  height: 58,
                  semanticLabel: 'HikerCircle logo',
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'HikerCircle',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.7,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
