import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/ui/widgets/empty_state.dart';

void main() {
  group('EmptyState', () {
    testWidgets('renders icon and title', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyState(
              icon: Icons.search_off,
              title: 'Nothing found',
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.search_off), findsOneWidget);
      expect(find.text('Nothing found'), findsOneWidget);
    });

    testWidgets('renders optional message when provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyState(
              icon: Icons.search_off,
              title: 'Nothing found',
              message: 'Try a different search',
            ),
          ),
        ),
      );

      expect(find.text('Nothing found'), findsOneWidget);
      expect(find.text('Try a different search'), findsOneWidget);
    });

    testWidgets('does not render message widget when message is null',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyState(
              icon: Icons.wifi_off,
              title: 'No connection',
            ),
          ),
        ),
      );

      expect(find.text('No connection'), findsOneWidget);
      // Only the title and icon should be present, no extra Text widgets
      // for the message.
      final textWidgets = tester.widgetList<Text>(find.byType(Text));
      final texts = textWidgets.map((w) => w.data).toList();
      expect(texts, contains('No connection'));
      expect(texts.length, 1);
    });

    testWidgets('renders action button when provided', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyState(
              icon: Icons.search_off,
              title: 'Nothing found',
              action: EmptyStateAction(
                label: 'Clear filters',
                onTap: () => tapped = true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Clear filters'), findsOneWidget);

      await tester.tap(find.text('Clear filters'));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('action button uses default refresh icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyState(
              icon: Icons.inbox,
              title: 'Empty inbox',
              action: EmptyStateAction(
                label: 'Refresh',
                onTap: () {},
              ),
            ),
          ),
        ),
      );

      // EmptyStateAction defaults to Icons.refresh
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('action button uses custom icon when provided',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyState(
              icon: Icons.inbox,
              title: 'Empty inbox',
              action: EmptyStateAction(
                label: 'Add item',
                onTap: () {},
                icon: Icons.add,
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('does not render action button when action is null',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyState(
              icon: Icons.folder_open,
              title: 'No files',
            ),
          ),
        ),
      );

      expect(find.byType(FilledButton), findsNothing);
    });
  });
}
