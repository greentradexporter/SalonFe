import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../widgets/brand_header.dart';

enum LegalDocument { privacy, terms }

class LegalScreen extends StatelessWidget {
  final LegalDocument document;
  const LegalScreen({super.key, required this.document});
  static Future<void> open(BuildContext context, LegalDocument document) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => LegalScreen(document: document)),
      );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: SalonFeAppBar(
      title: Text(
        document == LegalDocument.privacy
            ? 'Privacy Policy'
            : 'Terms & Conditions',
      ),
    ),
    body: FutureBuilder<String>(
      future: rootBundle.loadString('assets/legal/policies.json'),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Call +91 89996 08278 for a copy.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = jsonDecode(snapshot.data!) as Map<String, dynamic>;
        final policy = data[document.name] as Map<String, dynamic>;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: SelectionArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Last updated: ${data['updated']}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                for (final section in policy['sections'] as List) ...[
                  const SizedBox(height: 24),
                  Text(
                    section['title'] as String,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    section['body'] as String,
                    style: const TextStyle(height: 1.6),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    ),
  );
}
