import 'package:flutter/material.dart';

import '../../models/app_models.dart';
import '../../theme/app_brand.dart';
import '../../theme/app_theme.dart';
import '../../widgets/brand_header.dart';
import 'role_sign_in_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  void _signIn(BuildContext context, UserRole role) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => RoleSignInScreen(role: role)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(painter: _WelcomeBackground()),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 32,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const BrandWordmark(width: 280, onWhite: true),
                              const SizedBox(height: 24),
                              Text(
                                'Welcome to ${AppBrand.name}',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.headlineLarge
                                    ?.copyWith(
                                      fontSize: 29,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.9,
                                    ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Choose how you want to continue',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 36),
                              _WelcomeChoice(
                                key: const ValueKey('welcome-book-service'),
                                title: 'Book Service',
                                subtitle: 'Haircut, beard, salon services',
                                primary: true,
                                onTap: () =>
                                    _signIn(context, UserRole.customer),
                              ),
                              const SizedBox(height: 20),
                              _WelcomeChoice(
                                key: const ValueKey('welcome-register-salon'),
                                title: 'Register Salon',
                                subtitle: 'For salon owners & staff',
                                primary: false,
                                onTap: () => _signIn(context, UserRole.owner),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeChoice extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool primary;
  final VoidCallback onTap;

  const _WelcomeChoice({
    super.key,
    required this.title,
    required this.subtitle,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: Material(
        color: primary ? AppColors.primary : AppColors.primarySoft,
        borderRadius: BorderRadius.circular(25),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: primary
                    ? [const Color(0xFFFF6942), AppColors.primary]
                    : [AppColors.primarySoft, const Color(0xFFFFF8F5)],
              ),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 138),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 18,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 90,
                      height: 96,
                      child: CustomPaint(
                        painter: _ChoiceIllustration(salon: !primary),
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 78,
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      color: primary
                          ? Colors.white.withAlpha(150)
                          : AppColors.primaryBorder,
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 22,
                              color: AppColors.ink,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.ink,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: primary
                            ? Colors.white.withAlpha(75)
                            : AppColors.primaryBorder.withAlpha(100),
                      ),
                      child: const Icon(
                        Icons.chevron_right_rounded,
                        size: 27,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Code-native artwork keeps the new welcome screen crisp at every size.
class _ChoiceIllustration extends CustomPainter {
  final bool salon;
  const _ChoiceIllustration({required this.salon});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 120, size.height / 128);
    final paint = Paint()..isAntiAlias = true;
    void box(Rect rect, Color color, double radius) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        paint..color = color,
      );
    }

    canvas.drawCircle(
      const Offset(59, 68),
      55,
      paint..color = (salon ? AppColors.primary : Colors.white).withAlpha(35),
    );
    if (salon) {
      box(const Rect.fromLTWH(17, 51, 88, 64), const Color(0xFF56392F), 11);
      box(const Rect.fromLTWH(20, 48, 82, 63), const Color(0xFFFFE5D8), 9);
      box(const Rect.fromLTWH(29, 70, 35, 29), Colors.white, 5);
      box(const Rect.fromLTWH(73, 67, 20, 44), AppColors.primary, 7);
      canvas.drawCircle(const Offset(88, 91), 2, paint..color = Colors.white);
      final roof = Path()
        ..moveTo(16, 50)
        ..lineTo(27, 23)
        ..lineTo(95, 23)
        ..lineTo(106, 50)
        ..close();
      canvas.drawPath(roof, paint..color = AppColors.primary);
      for (final x in [36.0, 70.0]) {
        canvas.drawPath(
          Path()
            ..moveTo(x, 23)
            ..lineTo(x + 15, 23)
            ..lineTo(x + 20, 50)
            ..lineTo(x - 5, 50)
            ..close(),
          paint..color = Colors.white,
        );
      }
      for (var i = 0; i < 5; i++) {
        final x = 16.0 + i * 18;
        canvas.drawArc(
          Rect.fromLTWH(x, 39, 18, 24),
          0,
          3.14159,
          true,
          paint..color = i.isEven ? AppColors.primary : Colors.white,
        );
      }
      final shine = Paint()
        ..color = AppColors.primaryBorder
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(const Offset(35, 83), const Offset(45, 75), shine);
      canvas.drawLine(const Offset(42, 90), const Offset(52, 82), shine);
    } else {
      box(const Rect.fromLTWH(51, 91, 10, 25), const Color(0xFF604232), 3);
      canvas.drawOval(
        const Rect.fromLTWH(32, 111, 52, 9),
        paint..color = const Color(0xFF604232),
      );
      final chair = Path()
        ..moveTo(30, 35)
        ..quadraticBezierTo(20, 35, 23, 48)
        ..lineTo(30, 83)
        ..quadraticBezierTo(33, 96, 46, 96)
        ..lineTo(86, 96)
        ..quadraticBezierTo(96, 96, 96, 85)
        ..lineTo(96, 72)
        ..quadraticBezierTo(96, 64, 88, 64)
        ..lineTo(74, 64)
        ..lineTo(65, 41)
        ..quadraticBezierTo(62, 35, 54, 35)
        ..close();
      canvas.drawPath(
        chair,
        Paint()
          ..color = const Color(0xFF604232)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
      canvas.drawPath(chair, paint..color = const Color(0xFFFFF6EE));
      box(const Rect.fromLTWH(37, 84, 57, 10), const Color(0xFFFFDEBF), 4);
      box(const Rect.fromLTWH(26, 67, 25, 9), const Color(0xFF604232), 4);
      box(const Rect.fromLTWH(28, 66, 21, 6), const Color(0xFFFFE5D0), 3);
      final scissors = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(Icons.content_cut_rounded.codePoint),
          style: const TextStyle(
            fontFamily: 'MaterialIcons',
            fontSize: 38,
            color: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      scissors.paint(canvas, const Offset(70, 5));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ChoiceIllustration oldDelegate) =>
      oldDelegate.salon != salon;
}

class _WelcomeBackground extends CustomPainter {
  const _WelcomeBackground();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.primarySoft;
    canvas.drawOval(
      Rect.fromLTWH(size.width * .57, -100, size.width * .7, 220),
      paint,
    );
    canvas.drawOval(
      Rect.fromLTWH(size.width * .82, 55, size.width * .5, 170),
      paint,
    );
    canvas.drawOval(
      Rect.fromLTWH(-100, size.height - 55, size.width * .7, 200),
      paint,
    );
    canvas.drawOval(
      Rect.fromLTWH(-50, size.height - 24, size.width * .9, 130),
      paint..color = AppColors.primaryBorder.withAlpha(100),
    );
  }

  @override
  bool shouldRepaint(_WelcomeBackground oldDelegate) => false;
}
