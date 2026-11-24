import 'package:flutter/material.dart';

import '../models/service_catalog.dart';
import 'service_illustration.dart';

class ServiceImageIcon extends StatelessWidget {
  final String category;
  final String? serviceName;
  final double size;
  final Color? color;

  const ServiceImageIcon({
    super.key,
    required this.category,
    this.serviceName,
    this.size = 48,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final accent = color ?? serviceColorForCategory(category);
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withAlpha(34)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D0F172A),
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: ServiceIllustration(
        category: category,
        serviceName: serviceName,
        size: size,
        color: accent,
      ),
    );
  }
}
