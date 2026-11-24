import 'package:flutter/material.dart';

import '../theme/app_brand.dart';

/// A compact wordmark that leaves the page's existing actions intact.
class BrandWordmark extends StatelessWidget {
  final double width;
  final bool onWhite;

  const BrandWordmark({super.key, this.width = 78, this.onWhite = false});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: AppBrand.name,
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.asset(
          onWhite ? AppBrand.welcomeWordmarkAsset : AppBrand.wordmarkAsset,
          width: width,
          height: width / 3,
          fit: BoxFit.contain,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}

/// Shared branding for standard page headers; back buttons, titles, tabs and
/// existing actions continue to use the normal Material AppBar behavior.
class SalonFeAppBar extends AppBar {
  SalonFeAppBar({
    super.key,
    super.title,
    super.leading,
    super.automaticallyImplyLeading,
    super.bottom,
    super.backgroundColor,
    super.surfaceTintColor,
    super.centerTitle,
    List<Widget>? actions,
  }) : super(
         actions: [
           ...?actions,
           const Padding(
             padding: EdgeInsets.only(left: 4, right: 12),
             child: Center(child: BrandWordmark()),
           ),
         ],
       );
}
