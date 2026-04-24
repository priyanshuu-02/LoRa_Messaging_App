import 'package:flutter/material.dart';
import 'package:lora_communicator/constants/app_theme.dart';

/// An animated radar-style scanning indicator.
/// Shows expanding concentric rings emanating from a center point.
class AnimatedScanIndicator extends StatefulWidget {
  final double size;
  final Color? color;

  const AnimatedScanIndicator({
    super.key,
    this.size = 80,
    this.color,
  });

  @override
  State<AnimatedScanIndicator> createState() => _AnimatedScanIndicatorState();
}

class _AnimatedScanIndicatorState extends State<AnimatedScanIndicator>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _animations;

  static const int _ringCount = 3;

  @override
  void initState() {
    super.initState();

    _controllers = List.generate(
      _ringCount,
      (index) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2000),
      ),
    );

    _animations = _controllers.map((controller) {
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeOut),
      );
    }).toList();

    // Stagger the animations
    for (int i = 0; i < _ringCount; i++) {
      Future.delayed(Duration(milliseconds: i * 600), () {
        if (mounted) {
          _controllers[i].repeat();
        }
      });
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AppColors.primary;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Animated rings
          ..._animations.map((animation) {
            return AnimatedBuilder(
              animation: animation,
              builder: (context, child) {
                return Container(
                  width: widget.size * animation.value,
                  height: widget.size * animation.value,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color.withOpacity(1.0 - animation.value),
                      width: 2,
                    ),
                  ),
                );
              },
            );
          }),
          // Center dot
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.5),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
