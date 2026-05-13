import 'package:flutter/material.dart';

/// Static waveform painter: bars from a list of amplitude [samples] with a
/// progress indicator. Used in audio bubbles and the recorder preview.
class WaveformDisplay extends StatelessWidget {
  const WaveformDisplay({
    super.key,
    required this.samples,
    this.progress = 0.0,
    this.activeColor,
    this.inactiveColor,
    this.barWidth = 3.0,
    this.barSpacing = 2.0,
    this.height = 32.0,
    this.onSeek,
    this.isLive = false,
  });

  final List<double> samples;
  final double progress;
  final Color? activeColor;
  final Color? inactiveColor;
  final double barWidth;
  final double barSpacing;
  final double height;
  final ValueChanged<double>? onSeek;
  final bool isLive;

  static List<double> normalizeIntSamples(List<int> intSamples) {
    return intSamples.map((v) => v / 100.0).toList();
  }

  @override
  Widget build(BuildContext context) {
    final active = activeColor ?? Theme.of(context).colorScheme.primary;
    final inactive = inactiveColor ?? Colors.grey.shade300;

    Widget waveform = CustomPaint(
      size: Size(double.infinity, height),
      painter: _WaveformPainter(
        samples: samples,
        progress: progress,
        activeColor: active,
        inactiveColor: inactive,
        barWidth: barWidth,
        barSpacing: barSpacing,
        isLive: isLive,
      ),
    );

    if (onSeek != null) {
      waveform = GestureDetector(
        onHorizontalDragUpdate: (details) {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;
          final position = details.localPosition.dx / box.size.width;
          onSeek!(position.clamp(0.0, 1.0));
        },
        onTapDown: (details) {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;
          final position = details.localPosition.dx / box.size.width;
          onSeek!(position.clamp(0.0, 1.0));
        },
        child: waveform,
      );
    }

    return SizedBox(height: height, child: waveform);
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.samples,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    required this.barWidth,
    required this.barSpacing,
    required this.isLive,
  });

  final List<double> samples;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final double barWidth;
  final double barSpacing;
  final bool isLive;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;

    final totalBarWidth = barWidth + barSpacing;
    final maxBars = (size.width / totalBarWidth).floor();
    if (maxBars <= 0) return;
    final centerY = size.height / 2;
    final maxBarHeight = size.height * 0.9;
    const minBarHeight = 2.0;

    final displaySamples = isLive
        ? (samples.length > maxBars
            ? samples.sublist(samples.length - maxBars)
            : samples)
        : samples;

    final barCount = isLive ? displaySamples.length : maxBars;

    final step = isLive ? 1.0 : displaySamples.length / barCount;

    for (var i = 0; i < barCount; i++) {
      final rawIndex = isLive ? i : (i * step).floor();
      final sampleIndex =
          rawIndex.clamp(0, displaySamples.length - 1);

      final amplitude = displaySamples[sampleIndex].clamp(0.0, 1.0);
      final barHeight =
          (amplitude * maxBarHeight).clamp(minBarHeight, maxBarHeight);

      final x = isLive
          ? size.width - (barCount - i) * totalBarWidth + barSpacing
          : i * totalBarWidth;

      if (x < 0) continue;

      final isPlayed = !isLive && progress > 0 && (i / barCount) < progress;
      final paint = Paint()
        ..color = isPlayed ? activeColor : inactiveColor
        ..strokeCap = StrokeCap.round
        ..strokeWidth = barWidth;

      canvas.drawLine(
        Offset(x + barWidth / 2, centerY - barHeight / 2),
        Offset(x + barWidth / 2, centerY + barHeight / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      samples != oldDelegate.samples ||
      progress != oldDelegate.progress ||
      activeColor != oldDelegate.activeColor ||
      inactiveColor != oldDelegate.inactiveColor ||
      isLive != oldDelegate.isLive;
}
