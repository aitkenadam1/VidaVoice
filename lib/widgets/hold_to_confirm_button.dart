import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/onevoz_theme.dart';

/// Press-and-hold confirmation for dangerous actions (emergency flow).
///
/// The child must keep a finger down for the full [holdDuration] (default
/// 2 seconds). Releasing early — or the pointer being cancelled — resets
/// the progress and [onConfirmed] never fires. This is what prevents
/// accidental emergency triggers from a stray tap on the home board:
///
/// - a tap is instant and means nothing here;
/// - the hold is deliberate, visible (progress fill + press-scale), and
///   cancellable at any point before completion.
///
/// Visual, not haptic: many of our devices run with vibration off or on
/// silent, so the progress fill and the slight press-scale carry the
/// "something is happening" feedback instead of relying on a buzz.
class HoldToConfirmButton extends StatefulWidget {
  const HoldToConfirmButton({
    super.key,
    required this.onConfirmed,
    this.holdDuration = const Duration(seconds: 2),
    this.label = 'Emergency',
    this.sublabel = 'Hold 2 seconds',
    this.minHeight = 96.0,
  });

  /// Fires exactly once per completed hold.
  final VoidCallback onConfirmed;

  /// How long the press must be held. Keep at 2s for emergency actions.
  final Duration holdDuration;

  final String label;
  final String sublabel;

  /// Minimum button height — emergency actions stay big (>= 96).
  final double minHeight;

  @override
  State<HoldToConfirmButton> createState() => _HoldToConfirmButtonState();
}

class _HoldToConfirmButtonState extends State<HoldToConfirmButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress;
  Timer? _timer;
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(
      vsync: this,
      duration: widget.holdDuration,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _progress.dispose();
    super.dispose();
  }

  void _beginHold() {
    _timer?.cancel();
    _fired = false;
    _progress.forward(from: 0);
    _timer = Timer(widget.holdDuration, () {
      if (!mounted || _fired) return;
      _fired = true;
      _progress.reset();
      widget.onConfirmed();
    });
  }

  void _cancelHold() {
    _timer?.cancel();
    _timer = null;
    _fired = false;
    _progress.reset();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${widget.label}. ${widget.sublabel} to confirm.',
      child: Listener(
        onPointerDown: (_) => _beginHold(),
        onPointerUp: (_) => _cancelHold(),
        onPointerCancel: (_) => _cancelHold(),
        child: AnimatedBuilder(
          animation: _progress,
          builder: (context, child) {
            // Haptic-ish visual feedback: the button presses in slightly
            // and fills with white as the hold progresses.
            final scale = 1.0 - 0.04 * _progress.value;
            return Transform.scale(
              scale: scale,
              child: Container(
                constraints: BoxConstraints(minHeight: widget.minHeight),
                decoration: BoxDecoration(
                  color: OneVozColors.emergency,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    children: [
                      FractionallySizedBox(
                        widthFactor: _progress.value,
                        child: Container(color: Colors.white.withValues(alpha: 0.35)),
                      ),
                      Center(child: child),
                    ],
                  ),
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.emergency, color: Colors.white, size: 36),
                const SizedBox(height: 4),
                Text(
                  widget.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  widget.sublabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
