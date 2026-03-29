import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// A sleek bracket for the camera preview corners.
class CornerBracket extends StatelessWidget {
  final Color color;
  const CornerBracket({super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(
        painter: _CornerPainter(color: color),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  _CornerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset.zero, Offset(size.width, 0), paint);
    canvas.drawLine(Offset.zero, Offset(0, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// A specialized bubble for chat messages.
class ChatBubble extends StatelessWidget {
  final String text;
  final bool isAI;
  final bool isStreaming;

  const ChatBubble({
    super.key,
    required this.text,
    required this.isAI,
    this.isStreaming = false,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isAI ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: isAI
              ? const LinearGradient(
                  colors: [Color(0xFF1E1E35), Color(0xFF252540)])
              : const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF8A63FF)]),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isAI ? 4 : 18),
            bottomRight: Radius.circular(isAI ? 18 : 4),
          ),
          border: isAI
              ? Border.all(
                  color: const Color(0xFF6C63FF).withValues(alpha: 0.2),
                  width: 1)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isAI) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome,
                      size: 12, color: Color(0xFF00D4FF)),
                  const SizedBox(width: 5),
                  Text(
                    'OmniTutor',
                    style: TextStyle(
                      fontSize: 10,
                      color: const Color(0xFF00D4FF).withValues(alpha: 0.85),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            if (isStreaming && text.isEmpty)
              const ThinkingShimmer()
            else
              Text(
                isStreaming ? '$text▋' : text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Industry-standard shimmer effect for "AI is thinking" state.
class ThinkingShimmer extends StatelessWidget {
  const ThinkingShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.white.withValues(alpha: 0.05),
      highlightColor: Colors.white.withValues(alpha: 0.15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            height: 12,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: MediaQuery.of(context).size.width * 0.4,
            height: 12,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}
