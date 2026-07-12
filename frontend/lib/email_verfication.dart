import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:nutrifit/profile_setup.dart';

class EmailVerificationPage extends StatefulWidget {
  const EmailVerificationPage({super.key});

  @override
  State<EmailVerificationPage> createState() =>
      _EmailVerificationPageState();
}

class _EmailVerificationPageState
    extends State<EmailVerificationPage> {
  final TextEditingController linkController =
      TextEditingController();

  bool isLoading = false;
  bool isResending = false;

  Future<void> verifyLink() async {
    setState(() => isLoading = true);

    try {
      String link = linkController.text.trim();

      Uri uri = Uri.parse(link);
      String? oobCode = uri.queryParameters['oobCode'];

      if (oobCode == null) {
        throw Exception("Invalid verification link");
      }

      await FirebaseAuth.instance.applyActionCode(oobCode);

      User? user = FirebaseAuth.instance.currentUser;
      await user?.reload();

      await FirebaseFirestore.instance
          .collection("users")
          .doc(user!.uid)
          .update({"emailVerified": true});

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const PersonalInformation(),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Verification failed: $e")),
      );
    }

    setState(() => isLoading = false);
  }

  Future<void> resendEmail() async {
    setState(() => isResending = true);
    await FirebaseAuth.instance.currentUser
        ?.sendEmailVerification();
    setState(() => isResending = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Verification email sent again")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF4CAF50),
              Color(0xFF2E7D32),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.mark_email_read_rounded,
                    size: 80,
                    color: Color(0xFF2E7D32),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Verify Your Email",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "We have sent a verification link to your email.\nCopy the link and paste it below to continue.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 30),

                  /// LINK FIELD
                  TextField(
                    controller: linkController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: "Paste full verification link here",
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  /// VERIFY BUTTON
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed:
                          isLoading ? null : verifyLink,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            const Color(0xFF2E7D32),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(12),
                        ),
                      ),
                      child: isLoading
                          ? const CircularProgressIndicator(
                              color: Colors.white)
                          : const Text(
                              "Verify Email",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 15),

                  /// RESEND BUTTON
                  TextButton(
                    onPressed:
                        isResending ? null : resendEmail,
                    child: isResending
                        ? const CircularProgressIndicator()
                        : const Text(
                            "Resend Email",
                            style: TextStyle(
                              color: Color(0xFF2E7D32),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
