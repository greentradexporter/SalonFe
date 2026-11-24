import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/service_catalog.dart';

enum ServiceArt {
  haircut,
  wash,
  styling,
  spa,
  color,
  texture,
  massage,
  facial,
  cleanup,
  detan,
  beard,
  shave,
  threading,
  waxing,
  manicure,
  pedicure,
  makeup,
}

ServiceArt serviceArtFor(String name, {String category = ''}) {
  final value = '$name $category'.toLowerCase();
  if (value.contains('makeup') ||
      value.contains('bridal') ||
      value.contains('party')) {
    return ServiceArt.makeup;
  }
  if (value.contains('thread')) return ServiceArt.threading;
  if (value.contains('wax')) return ServiceArt.waxing;
  if (value.contains('mani/pedi')) return ServiceArt.manicure;
  if (value.contains('pedi')) return ServiceArt.pedicure;
  if (value.contains('mani') || value.contains('nail')) {
    return ServiceArt.manicure;
  }
  if (value.contains('shav')) return ServiceArt.shave;
  if (value.contains('beard')) return ServiceArt.beard;
  if (value.contains('cleanup')) return ServiceArt.cleanup;
  if (value.contains('bleach') ||
      value.contains('detan') ||
      value.contains('d-tan')) {
    return ServiceArt.detan;
  }
  if (value.contains('facial') || value.contains('skin')) {
    return ServiceArt.facial;
  }
  if (value.contains('massage')) return ServiceArt.massage;
  if (value.contains('spa')) return ServiceArt.spa;
  if (value.contains('colour') ||
      value.contains('color') ||
      value.contains('root touch')) {
    return ServiceArt.color;
  }
  if (value.contains('keratin') ||
      value.contains('texture') ||
      value.contains('smooth')) {
    return ServiceArt.texture;
  }
  if (value.contains('wash') || value.contains('hair care')) {
    return ServiceArt.wash;
  }
  if (value.contains('blow') || value.contains('styling')) {
    return ServiceArt.styling;
  }
  return ServiceArt.haircut;
}

/// Uses the original detailed artwork, with distinct Facial and Makeup assets.
class ServiceIllustration extends StatelessWidget {
  final String category;
  final String? serviceName;
  final double size;
  final Color color;
  const ServiceIllustration({
    super.key,
    required this.category,
    this.serviceName,
    this.size = 48,
    this.color = AppColors.primary,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    label: serviceName ?? category,
    image: true,
    child: SizedBox.square(
      dimension: size,
      child: Image.asset(
        serviceIconAssetForService(serviceName ?? category, category: category),
        fit: BoxFit.contain,
        excludeFromSemantics: true,
        errorBuilder: (context, error, stackTrace) => Icon(
          serviceFallbackIconForCategory(category),
          color: color,
          size: size * .7,
        ),
      ),
    ),
  );
}
