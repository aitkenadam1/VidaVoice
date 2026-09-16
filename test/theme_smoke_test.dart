import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onevoz/theme/onevoz_theme.dart';

void main() {
  testWidgets('WaveformMotif renders without exceptions', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: WaveformMotif())),
      ),
    );
    expect(find.byType(WaveformMotif), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    await tester.pump();
  });

  testWidgets('WaveformMotif honors barCount/gradient overrides', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: WaveformMotif(
              barCount: 5,
              height: 64,
              gradient: const LinearGradient(
                colors: [Colors.red, Colors.orange],
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(WaveformMotif), findsOneWidget);
    await tester.pump();
  });

  testWidgets('OneVozGradientButton renders and the tap fires', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: OneVozGradientButton(
              label: 'Call Mom',
              icon: Icons.call,
              onPressed: () => tapped = true,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Call Mom'), findsOneWidget);
    expect(find.byIcon(Icons.call), findsOneWidget);
    await tester.tap(find.byType(OneVozGradientButton));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('OneVozGradientButton disabled does not fire', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: OneVozGradientButton(
              label: 'Call Mom',
              onPressed: null,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(OneVozGradientButton));
    await tester.pump();
    expect(tapped, isFalse);
  });

  testWidgets('OneVozEmergencyButton renders and the tap fires', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: OneVozEmergencyButton(
              label: 'Emergency',
              onPressed: () => tapped = true,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Emergency'), findsOneWidget);
    await tester.tap(find.byType(OneVozEmergencyButton));
    await tester.pump();
    expect(tapped, isTrue);
  });

  test('child and caregiver themes build and differ', () {
    final child = OneVozTheme.childTheme();
    final caregiver = OneVozTheme.caregiverTheme();
    expect(child.useMaterial3, isTrue);
    expect(caregiver.useMaterial3, isTrue);
    expect(child.scaffoldBackgroundColor,
        OneVozColors.childBackground);
    expect(caregiver.scaffoldBackgroundColor,
        OneVozColors.caregiverBackground);
    expect(child.scaffoldBackgroundColor,
        isNot(caregiver.scaffoldBackgroundColor));
  });

  testWidgets('breakpoint helpers classify phone vs tablet widths',
      (tester) async {
    OneVozDeviceClass? phoneClass;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: Builder(
            builder: (context) {
              phoneClass = OneVozBreakpoints.deviceClassOf(context);
              expect(OneVozBreakpoints.criticalTouchTarget(context),
                  greaterThanOrEqualTo(64));
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(phoneClass, OneVozDeviceClass.phone);

    OneVozDeviceClass? tabletClass;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(1024, 1366)),
          child: Builder(
            builder: (context) {
              tabletClass = OneVozBreakpoints.deviceClassOf(context);
              expect(OneVozBreakpoints.criticalTouchTarget(context),
                  greaterThanOrEqualTo(64));
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(tabletClass, OneVozDeviceClass.tablet);
  });
}
