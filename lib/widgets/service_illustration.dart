import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

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

/// Distinct code-native artwork; no shared generic face image or missing assets.
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
      child: CustomPaint(
        painter: _ServicePainter(
          serviceArtFor(serviceName ?? category, category: category),
          color,
        ),
      ),
    ),
  );
}

class _ServicePainter extends CustomPainter {
  final ServiceArt art;
  final Color color;
  const _ServicePainter(this.art, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    final soft = Paint()..color = color.withAlpha(40);
    void line(double x, double y, double xx, double yy) =>
        canvas.drawLine(Offset(x, y), Offset(xx, yy), stroke);
    void oval(double x, double y, double w, double h, {bool solid = false}) =>
        canvas.drawOval(Rect.fromLTWH(x, y, w, h), solid ? fill : stroke);
    void box(
      double x,
      double y,
      double w,
      double h, {
      bool solid = false,
      double radius = 6,
    }) => canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, w, h),
        Radius.circular(radius),
      ),
      solid ? fill : stroke,
    );
    void face() {
      oval(27, 18, 46, 65);
      line(36, 45, 41, 45);
      line(59, 45, 64, 45);
      canvas.drawArc(
        const Rect.fromLTWH(42, 61, 16, 9),
        0,
        math.pi,
        false,
        stroke,
      );
    }

    switch (art) {
      case ServiceArt.haircut:
        oval(16, 62, 24, 24);
        oval(60, 62, 24, 24);
        line(36, 67, 78, 14);
        line(64, 67, 22, 14);
        canvas.drawCircle(const Offset(50, 49), 5, fill);
      case ServiceArt.styling:
        box(18, 24, 26, 23);
        line(32, 48, 28, 73);
        line(45, 33, 65, 33);
        line(52, 46, 78, 46);
      case ServiceArt.texture:
        for (var x = 31.0; x < 74; x += 13) {
          canvas.drawPath(
            Path()
              ..moveTo(x, 18)
              ..cubicTo(x - 8, 37, x + 8, 57, x, 80),
            stroke,
          );
        }
        line(14, 20, 14, 79);
        for (var y = 28.0; y < 78; y += 10) {
          line(14, y, 22, y);
        }
      case ServiceArt.wash:
        canvas.drawArc(
          const Rect.fromLTWH(20, 57, 60, 26),
          0,
          math.pi,
          false,
          stroke,
        );
        line(25, 58, 75, 58);
        line(28, 24, 28, 43);
        line(28, 24, 65, 24);
        line(65, 24, 73, 33);
        for (var x = 42.0; x < 77; x += 12) {
          line(x, 40, x - 7, 51);
        }
        oval(35, 57, 27, 17, solid: true);
      case ServiceArt.color:
        canvas.drawArc(
          const Rect.fromLTWH(17, 50, 66, 35),
          0,
          math.pi,
          false,
          stroke,
        );
        line(17, 67, 83, 67);
        line(42, 49, 65, 18);
        line(51, 52, 74, 25);
        box(57, 15, 24, 12, solid: true, radius: 3);
      case ServiceArt.spa:
        oval(18, 70, 64, 14, solid: true);
        oval(28, 55, 44, 13, solid: true);
        oval(39, 40, 23, 12, solid: true);
        for (var x = 35.0; x <= 65; x += 15) {
          canvas.drawPath(
            Path()
              ..moveTo(x, 29)
              ..cubicTo(x - 8, 22, x + 8, 17, x, 10),
            stroke,
          );
        }
      case ServiceArt.facial:
        face();
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(30, 38, 40, 24),
            const Radius.circular(10),
          ),
          soft,
        );
        canvas.drawCircle(const Offset(35, 54), 5, fill);
        canvas.drawCircle(const Offset(65, 54), 5, fill);
        line(32, 29, 66, 29);
        line(78, 19, 78, 31);
        line(72, 25, 84, 25);
      case ServiceArt.cleanup:
        face();
        for (final o in [
          const Offset(75, 27),
          const Offset(83, 40),
          const Offset(76, 51),
        ]) {
          canvas.drawCircle(o, 5, stroke);
        }
        line(14, 57, 28, 62);
        box(8, 52, 12, 20, solid: true, radius: 3);
      case ServiceArt.detan:
        box(25, 39, 33, 44);
        box(33, 29, 17, 10, solid: true, radius: 2);
        canvas.drawCircle(const Offset(75, 27), 10, stroke);
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          line(
            75 + 14 * math.cos(a),
            27 + 14 * math.sin(a),
            75 + 20 * math.cos(a),
            27 + 20 * math.sin(a),
          );
        }
        line(35, 56, 47, 56);
        line(35, 67, 47, 67);
      case ServiceArt.beard:
        oval(25, 16, 50, 64);
        canvas.drawPath(
          Path()
            ..moveTo(25, 46)
            ..quadraticBezierTo(50, 66, 75, 46)
            ..lineTo(68, 76)
            ..lineTo(50, 89)
            ..lineTo(32, 76)
            ..close(),
          fill,
        );
        line(36, 39, 42, 39);
        line(58, 39, 64, 39);
      case ServiceArt.shave:
        box(22, 18, 56, 20, solid: true, radius: 4);
        box(44, 38, 12, 46);
        line(28, 25, 72, 25);
        line(44, 64, 56, 64);
      case ServiceArt.threading:
        canvas.drawPath(
          Path()
            ..moveTo(18, 40)
            ..quadraticBezierTo(50, 18, 83, 40),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(20, 51)
            ..quadraticBezierTo(50, 74, 78, 49),
          stroke,
        );
        line(17, 80, 83, 24);
        line(19, 76, 82, 78);
        line(82, 78, 83, 24);
      case ServiceArt.waxing:
        box(21, 45, 58, 38);
        oval(21, 39, 58, 15, solid: true);
        line(53, 41, 74, 14);
        line(62, 44, 83, 18);
        box(68, 10, 16, 11, solid: true, radius: 4);
        line(36, 62, 64, 62);
      case ServiceArt.manicure:
        canvas.drawPath(
          Path()
            ..moveTo(31, 82)
            ..lineTo(20, 60)
            ..quadraticBezierTo(16, 49, 25, 48)
            ..lineTo(33, 57)
            ..lineTo(33, 27)
            ..quadraticBezierTo(33, 19, 40, 24)
            ..lineTo(42, 44)
            ..lineTo(44, 17)
            ..quadraticBezierTo(46, 10, 51, 18)
            ..lineTo(52, 43)
            ..lineTo(57, 21)
            ..quadraticBezierTo(61, 16, 65, 23)
            ..lineTo(64, 48)
            ..lineTo(71, 32)
            ..quadraticBezierTo(77, 27, 79, 36)
            ..lineTo(70, 73)
            ..lineTo(64, 84),
          stroke,
        );
        for (final x in [37.0, 47.0, 60.0]) {
          box(x, 25, 5, 7, solid: true, radius: 2);
        }
      case ServiceArt.pedicure:
        canvas.drawPath(
          Path()
            ..moveTo(34, 77)
            ..quadraticBezierTo(20, 52, 46, 34)
            ..quadraticBezierTo(65, 23, 70, 47)
            ..lineTo(63, 77)
            ..quadraticBezierTo(49, 90, 34, 77),
          stroke,
        );
        for (var i = 0; i < 4; i++) {
          oval(25 + i * 11, 18 + (i - 2).abs() * 3, 8, 12, solid: true);
        }
        oval(69, 27, 12, 15, solid: true);
      case ServiceArt.makeup:
        box(24, 55, 18, 30, solid: true, radius: 3);
        canvas.drawPath(
          Path()
            ..moveTo(26, 53)
            ..lineTo(26, 32)
            ..lineTo(39, 22)
            ..lineTo(39, 53)
            ..close(),
          fill,
        );
        line(57, 77, 74, 41);
        box(65, 26, 18, 22, solid: true, radius: 8);
        oval(10, 69, 14, 14);
        line(52, 22, 52, 32);
        line(47, 27, 57, 27);
      case ServiceArt.massage:
        face();
        canvas.drawPath(
          Path()
            ..moveTo(10, 70)
            ..lineTo(10, 42)
            ..quadraticBezierTo(12, 32, 20, 36)
            ..lineTo(26, 53),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(90, 70)
            ..lineTo(90, 42)
            ..quadraticBezierTo(88, 32, 80, 36)
            ..lineTo(74, 53),
          stroke,
        );
        line(39, 10, 39, 4);
        line(51, 8, 51, 2);
        line(63, 10, 63, 4);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ServicePainter old) =>
      old.art != art || old.color != color;
}
