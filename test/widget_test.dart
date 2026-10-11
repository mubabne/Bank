import 'package:bank_app/bank_transaction.dart';
import 'package:bank_app/login_page.dart';
import 'package:bank_app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget loginApp() =>
      MaterialApp(theme: AppTheme.light, home: const LoginPage());

  testWidgets('shows the production login screen', (tester) async {
    await tester.pumpWidget(loginApp());

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.byKey(const Key('emailField')), findsOneWidget);
    expect(find.byKey(const Key('passwordField')), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
    expect(find.byKey(const Key('gmailButton')), findsNothing);
  });

  testWidgets('switches to sign up mode', (tester) async {
    await tester.pumpWidget(loginApp());

    await tester.ensureVisible(find.byKey(const Key('toggleAuthModeButton')));
    await tester.tap(find.byKey(const Key('toggleAuthModeButton')));
    await tester.pump();

    expect(find.text('Create your account'), findsOneWidget);
    expect(find.byKey(const Key('displayNameField')), findsOneWidget);
    expect(find.text('Already have an account?'), findsOneWidget);
  });

  test('formats Mongolian tugriks with the tugrik symbol', () {
    expect(formatMoney(125000, currency: 'MNT'), '₮125,000');
    expect(formatMoney(48500, currency: 'MNT', sign: '-'), '-₮48,500');
  });
}
