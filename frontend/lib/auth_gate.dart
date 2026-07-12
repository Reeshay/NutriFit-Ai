import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nutrifit/get_started.dart';
import 'home_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nutrifit/profile_setup.dart';
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData) {
  return FutureBuilder<DocumentSnapshot>(
    future: FirebaseFirestore.instance
        .collection('users')
        .doc(snapshot.data!.uid)
        .get(),
    builder: (context, userSnap) {
      if (userSnap.connectionState == ConnectionState.waiting) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      }

      final data = userSnap.data?.data() as Map<String, dynamic>?;
      final bool profileComplete = data?['isProfileCompleted'] == true;

      if (profileComplete) {
        return const HomePage();
      } else {
        return const PersonalInformation();
      }
    },
  );
}

        return const GetStartedPage(); 
      },
    );
  }
}

