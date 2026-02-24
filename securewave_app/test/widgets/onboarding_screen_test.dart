import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/features/onboarding/onboarding_screen.dart';

void main() {
  group('OnboardingScreen', () {
    testWidgets('renders first page with shield icon and title',
        (tester) async {
      bool completed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(onComplete: () => completed = true),
        ),
      );

      expect(find.text('Encrypted by default'), findsOneWidget);
      expect(find.byIcon(Icons.shield_rounded), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(completed, isFalse);
    });

    testWidgets('navigates to second page on Next tap', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(onComplete: () {}),
        ),
      );

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Choose your location'), findsOneWidget);
      expect(find.byIcon(Icons.public_rounded), findsOneWidget);
    });

    testWidgets('navigates to third page and shows Get Started',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(onComplete: () {}),
        ),
      );

      // Go to page 2
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Go to page 3
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text("You're all set"), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);
    });

    testWidgets('calls onComplete when Skip is tapped', (tester) async {
      bool completed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(onComplete: () => completed = true),
        ),
      );

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(completed, isTrue);
    });

    testWidgets('calls onComplete when Get Started is tapped on last page',
        (tester) async {
      bool completed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(onComplete: () => completed = true),
        ),
      );

      // Navigate to last page
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Get Started'));
      await tester.pumpAndSettle();

      expect(completed, isTrue);
    });

    testWidgets('shows 3 dot indicators', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(onComplete: () {}),
        ),
      );

      // There should be 3 AnimatedContainer dot indicators.
      // They are inside a Row in the bottom section.
      expect(find.byType(AnimatedContainer), findsNWidgets(3));
    });

    testWidgets('button text changes from Next to Get Started on last page',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(onComplete: () {}),
        ),
      );

      // First page shows "Next"
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Get Started'), findsNothing);

      // Navigate to last page
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Last page shows "Get Started"
      expect(find.text('Get Started'), findsOneWidget);
      expect(find.text('Continue'), findsNothing);
    });
  });
}
