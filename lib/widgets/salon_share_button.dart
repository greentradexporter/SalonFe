import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/app_models.dart';
import '../services/salon_link_service.dart';

class SalonShareButton extends StatelessWidget {
  final Salon salon;
  const SalonShareButton({super.key, required this.salon});
  @override
  Widget build(BuildContext context) => IconButton(
    key: ValueKey('share-salon-${salon.id}'),
    tooltip: 'Share ${salon.displayName}',
    icon: const Icon(Icons.share_outlined),
    onPressed: () async {
      final box = context.findRenderObject() as RenderBox?;
      try {
        await SharePlus.instance.share(
          ShareParams(
            title: salon.displayName,
            subject: '${salon.displayName} on SalonFe',
            text:
                'Book ${salon.displayName} on SalonFe.\n${SalonLinkService.linkFor(salon.id)}',
            sharePositionOrigin: box == null
                ? null
                : box.localToGlobal(Offset.zero) & box.size,
          ),
        );
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sharing could not open. Please try again.'),
            ),
          );
        }
      }
    },
  );
}
