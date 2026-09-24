import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// An interactive colour wheel, used in place rather than behind a dialog.
///
/// Hue is the angle and saturation the distance from the middle, which is the
/// wheel's whole vocabulary; brightness is its missing axis, so it gets the
/// slider underneath. Dragging reports continuously through [onChanged] so the
/// app can re-tint live, and once through [onChangeEnd] when the finger lifts —
/// which is the caller's cue to persist, rather than writing on every frame of
/// a drag.
class ColourWheelDial extends StatefulWidget {
  /// The colour to show as chosen. Changing it from outside — by picking a
  /// preset swatch — moves the marker to that colour's place on the wheel.
  final Color colour;
  final double size;

  /// Whether to offer brightness. Off leaves a bare wheel.
  final bool brightness;

  final ValueChanged<Color> onChanged;
  final ValueChanged<Color> onChangeEnd;

  const ColourWheelDial({
    super.key,
    required this.colour,
    required this.onChanged,
    required this.onChangeEnd,
    this.size = 96,
    this.brightness = true,
  });

  @override
  State<ColourWheelDial> createState() => _ColourWheelDialState();
}

class _ColourWheelDialState extends State<ColourWheelDial> {
  late HSVColor _hsv = HSVColor.fromColor(widget.colour);

  @override
  void didUpdateWidget(ColourWheelDial old) {
    super.didUpdateWidget(old);
    // Only re-seed when the colour changed to something that isn't already
    // where the marker sits — otherwise our own onChanged would fight the drag.
    if (widget.colour != _hsv.toColor()) {
      _hsv = HSVColor.fromColor(widget.colour);
    }
  }

  /// Map a touch inside the wheel to a hue (angle) and saturation (distance).
  void _handleTouch(Offset local) {
    final radius = widget.size / 2;
    final v = local - Offset(radius, radius);
    // atan2 gives -pi..pi; shift to 0..360 so hue reads clockwise from the right.
    var angle = math.atan2(v.dy, v.dx) * 180 / math.pi;
    if (angle < 0) angle += 360;
    setState(() {
      _hsv = _hsv
          .withHue(angle)
          .withSaturation(v.distance.clamp(0.0, radius) / radius);
    });
    widget.onChanged(_hsv.toColor());
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      GestureDetector(
        onPanDown: (d) => _handleTouch(d.localPosition),
        onPanUpdate: (d) => _handleTouch(d.localPosition),
        onPanEnd: (_) => widget.onChangeEnd(_hsv.toColor()),
        onTapUp: (_) => widget.onChangeEnd(_hsv.toColor()),
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(painter: _WheelPainter(_hsv)),
        ),
      ),
      if (widget.brightness)
        SizedBox(
          width: widget.size + 12,
          height: 26,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: _hsv.toColor(),
              inactiveTrackColor: AppColors.border,
              thumbColor: _hsv.toColor(),
              overlayColor: _hsv.toColor().withValues(alpha: 0.14),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: _hsv.value,
              onChanged: (v) {
                setState(() => _hsv = _hsv.withValue(v));
                widget.onChanged(_hsv.toColor());
              },
              onChangeEnd: (_) => widget.onChangeEnd(_hsv.toColor()),
            ),
          ),
        ),
    ],
  );
}

/// Hue around the wheel, saturation out from the middle, at the current value.
class _WheelPainter extends CustomPainter {
  final HSVColor hsv;
  const _WheelPainter(this.hsv);

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: centre, radius: radius);

    // Hue ring: a sweep through the spectrum.
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..shader = SweepGradient(
          colors: [
            for (var i = 0; i <= 360; i += 30)
              HSVColor.fromAHSV(1, i % 360.0, 1, hsv.value).toColor(),
          ],
        ).createShader(rect),
    );
    // Desaturate toward the middle.
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            HSVColor.fromAHSV(1, 0, 0, hsv.value).toColor(),
            HSVColor.fromAHSV(0, 0, 0, hsv.value).toColor(),
          ],
        ).createShader(rect),
    );

    // The current position.
    final angle = hsv.hue * math.pi / 180;
    final knob = centre +
        Offset(math.cos(angle), math.sin(angle)) * (hsv.saturation * radius);
    canvas.drawCircle(
      knob,
      11,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(knob, 9, Paint()..color = hsv.toColor());
  }

  @override
  bool shouldRepaint(_WheelPainter old) => old.hsv != hsv;
}
