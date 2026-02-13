import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/features/onboarding/feedback_sheet.dart';

void main() {
  group('FeedbackSheet', () {
    testWidgets('renders title and submit button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeedbackSheet(
              onSubmit: (_, __) {},
            ),
          ),
        ),
      );

      expect(find.text('Send Feedback'), findsOneWidget);
      expect(find.text('Submit'), findsOneWidget);
    });

    testWidgets('renders category segmented button with 3 options',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeedbackSheet(
              onSubmit: (_, __) {},
            ),
          ),
        ),
      );

      expect(find.text('Bug Report'), findsOneWidget);
      expect(find.text('Feature Request'), findsOneWidget);
      expect(find.text('General Feedback'), findsOneWidget);
    });

    testWidgets('submit button is disabled when description is empty',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeedbackSheet(
              onSubmit: (_, __) {},
            ),
          ),
        ),
      );

      final submitButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Submit'),
      );
      expect(submitButton.onPressed, isNull);
    });

    testWidgets('submit button is enabled after entering text',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeedbackSheet(
              onSubmit: (_, __) {},
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'Test feedback');
      await tester.pump();

      final submitButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Submit'),
      );
      expect(submitButton.onPressed, isNotNull);
    });

    testWidgets('renders description text field with hint', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeedbackSheet(
              onSubmit: (_, __) {},
            ),
          ),
        ),
      );

      expect(find.text('Describe your feedback...'), findsOneWidget);
    });

    testWidgets('submit button remains disabled for whitespace-only input',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeedbackSheet(
              onSubmit: (_, __) {},
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();

      final submitButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Submit'),
      );
      expect(submitButton.onPressed, isNull);
    });

    testWidgets('calls onSubmit with category and description on submit',
        (tester) async {
      FeedbackCategory? receivedCategory;
      String? receivedDescription;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute(
                builder: (_) => Scaffold(
                  body: FeedbackSheet(
                    onSubmit: (category, description) {
                      receivedCategory = category;
                      receivedDescription = description;
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'App crashes on start');
      await tester.pump();

      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();

      expect(receivedCategory, FeedbackCategory.bugReport);
      expect(receivedDescription, 'App crashes on start');
    });
  });
}
