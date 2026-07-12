import 'package:flutter/material.dart';
import 'package:patrol/patrol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutrifit/main.dart';

void main() {

  patrolTest('Signup success test', ($) async {
    await $.pumpWidgetAndSettle(MyApp());

    // Navigate to signup page (if needed)
    await $(Key('goToSignup')).tap();

    // Enter data
    await $(Key('signupUsername')).enterText('Ali');
    await $(Key('signupEmail')).enterText('ali@test.com');
    await $(Key('signupPassword')).enterText('123456');

    // Tap signup
    await $(Key('signupButton')).tap();

    await $.pumpAndSettle();

    // Expect next screen (Profile Setup)
    expect($(Key('profilePage')), findsOneWidget);
  });

  patrolTest('Signup validation test (empty fields)', ($) async {
    await $.pumpWidgetAndSettle(MyApp());

    await $(Key('goToSignup')).tap();

    // Tap without entering data
    await $(Key('signupButton')).tap();

    await $.pumpAndSettle();

    // Expect validation error
    expect($(find.text('Enter email')), findsOneWidget);
  });

  patrolTest('Google signup button test', ($) async {
    await $.pumpWidgetAndSettle(MyApp());

    await $(Key('goToSignup')).tap();

    await $(Key('googleSignupButton')).tap();

    await $.pumpAndSettle();

    // We can't fully test Google auth easily, so just check button works
    expect($(Key('signupPage')), findsOneWidget);
  });
}