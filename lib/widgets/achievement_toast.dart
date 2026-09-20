import 'package:flutter/material.dart';
import '../models/achievement.dart';

/// Zeigt einen animierten "Achievement freigeschaltet"-Toast von oben ins
/// Bild gleiten, hält kurz und schiebt sich wieder raus. Läuft über einen
/// OverlayEntry statt SnackBar, damit mehrere Achievements (z.B. bei einem
/// großen Sprung) sauber nacheinander angezeigt werden können, ohne dass
/// eine Snackbar die andere abbricht.
class AchievementToastQueue {
  final OverlayState overlay;
  final List<AchievementDefinition> _queue = [];
  bool _showing = false;

  AchievementToastQueue(this.overlay);

  void show(AchievementDefinition definition) {
    _queue.add(definition);
    if (!_showing) _showNext();
  }

  void _showNext() {
    if (_queue.isEmpty) {
      _showing = false;
      return;
    }
    _showing = true;
    final definition = _queue.removeAt(0);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _AchievementToastWidget(
        definition: definition,
        onFinished: () {
          entry.remove();
          _showNext();
        },
      ),
    );
    overlay.insert(entry);
  }
}

class _AchievementToastWidget extends StatefulWidget {
  final AchievementDefinition definition;
  final VoidCallback onFinished;

  const _AchievementToastWidget({required this.definition, required this.onFinished});

  @override
  State<_AchievementToastWidget> createState() => _AchievementToastWidgetState();
}

class _AchievementToastWidgetState extends State<_AchievementToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));

    _slide = Tween<Offset>(begin: const Offset(0, -1.2), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeIn);

    _run();
  }

  Future<void> _run() async {
    await _controller.forward();
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    await _controller.reverse();
    widget.onFinished();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final def = widget.definition;

    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A1F2E), Color(0xFF0D1017)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.amber.withValues(alpha: 0.6),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.amber.withValues(alpha: 0.25),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: Colors.amber,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.emoji_events, color: Colors.black, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ACHIEVEMENT FREIGESCHALTET',
                          style: TextStyle(
                            color: Colors.amber,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          def.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          def.description,
                          style: TextStyle(color: Colors.grey[400], fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
