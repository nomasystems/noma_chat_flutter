import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  testWidgets('renders with given height', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WaveformDisplay(samples: [0.5, 0.8, 0.3, 0.9, 0.1], height: 40),
        ),
      ),
    );

    final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox));
    expect(sizedBox.height, 40.0);
  });

  testWidgets('renders with empty samples', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: WaveformDisplay(samples: [])),
      ),
    );

    expect(find.byType(WaveformDisplay), findsOneWidget);
  });

  testWidgets('calls onSeek on tap', (tester) async {
    double? seekValue;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            child: WaveformDisplay(
              samples: [0.5, 0.5, 0.5, 0.5],
              onSeek: (value) => seekValue = value,
            ),
          ),
        ),
      ),
    );

    await tester.tapAt(tester.getCenter(find.byType(WaveformDisplay)));
    expect(seekValue, isNotNull);
    expect(seekValue, closeTo(0.5, 0.15));
  });

  testWidgets('calls onSeek on horizontal drag', (tester) async {
    double? seekValue;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            child: WaveformDisplay(
              samples: [0.5, 0.5, 0.5, 0.5],
              onSeek: (value) => seekValue = value,
            ),
          ),
        ),
      ),
    );

    final center = tester.getCenter(find.byType(WaveformDisplay));
    await tester.dragFrom(center, const Offset(50, 0));

    expect(seekValue, isNotNull);
  });

  test('normalizeIntSamples converts 0-100 to 0.0-1.0', () {
    final result = WaveformDisplay.normalizeIntSamples([0, 50, 100]);
    expect(result, [0.0, 0.5, 1.0]);
  });

  testWidgets('does not add GestureDetector without onSeek', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: WaveformDisplay(samples: [0.5, 0.8])),
      ),
    );

    expect(find.byType(GestureDetector), findsNothing);
  });
}
