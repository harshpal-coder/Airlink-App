import 'package:flutter/material.dart';

class RadarAnimation extends StatefulWidget {
  final bool isDiscovering;
  final Widget? centerWidget;

  const RadarAnimation({
    super.key,
    required this.isDiscovering,
    this.centerWidget,
  });

  @override
  State<RadarAnimation> createState() => _RadarAnimationState();
}

class _RadarAnimationState extends State<RadarAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    if (widget.isDiscovering) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(RadarAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isDiscovering != oldWidget.isDiscovering) {
      if (widget.isDiscovering) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 200,
        height: 200,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (widget.isDiscovering)
              ...List.generate(3, (index) {
                return RadarCircle(animation: _controller, delay: index * 1.0);
              }),
            if (widget.centerWidget != null) widget.centerWidget!,
          ],
        ),
      ),
    );
  }
}

class RadarCircle extends StatelessWidget {
  final Animation<double> animation;
  final double delay;

  const RadarCircle({super.key, required this.animation, required this.delay});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        double val = (animation.value + delay / 3) % 1.0;
        double radius = val * 180;
        double opacity = (1.0 - val).clamp(0.0, 1.0);

        return Container(
          width: radius,
          height: radius,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.blue.withValues(alpha: opacity * 0.3),
              width: 2,
            ),
            gradient: RadialGradient(
              colors: [
                Colors.blue.withValues(alpha: opacity * 0.1),
                Colors.blue.withValues(alpha: 0.3),
              ],
            ),
          ),
        );
      },
    );
  }
}
