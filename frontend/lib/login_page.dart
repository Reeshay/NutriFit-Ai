import 'package:flutter/material.dart';
import 'home_page.dart';
import 'signup_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'auth_gate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool hidePassword = true;
  bool isLoading = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);

    try {
      final userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      final user = userCredential.user;
      if (user != null && mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (_) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      print("LOGIN ERROR: ${e.code} - ${e.message}");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.code)),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

 Future<void> signInWithGoogle() async {
  setState(() => isLoading = true);

  try {
    // Use the static instance and initialize with clientId
    await GoogleSignIn.instance.initialize(
      serverClientId: '533865808336-5vhnn64ne06d4j813c1aehcm1h6569q1.apps.googleusercontent.com',
    );

    // Start Google Sign-In
    final GoogleSignInAccount? googleUser = await GoogleSignIn.instance.authenticate();

    if (googleUser == null) {
      setState(() => isLoading = false); // User canceled
      return;
    }

    final googleAuth = await googleUser.authentication;

    // Firebase credential (use only idToken)
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );

    try {
      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCredential.user!;

      // Check Firestore to confirm this account is actually registered with NutriFit
      final docSnapshot = await FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .get();

      if (!docSnapshot.exists) {
  await user.delete(); // Auth ki ghost entry hata do
  await FirebaseAuth.instance.signOut();
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("This account is not registered with NutriFit"),
      ),
    );
  }
  return;
}

      if (!user.emailVerified) {
        await user.sendEmailVerification();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Verification link sent. Please check your email."),
          ),
        );
        await FirebaseAuth.instance.signOut();
        return;
      }

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (_) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      print("LOGIN ERROR: ${e.code} - ${e.message}");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? "Google login failed")),
      );
    }
  } catch (e) {
    print("GOOGLE SIGNIN ERROR: $e");
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Google login failed: $e")),
    );
  } finally {
    if (mounted) setState(() => isLoading = false);
  }
}
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage("images/background_image.jpeg"),
            fit: BoxFit.cover,
          ),
        ),
        child: Container(
          color: Colors.black38,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 100),
                const Text(
                  "Welcome Back!",
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Login to your account",
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 40),

                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: emailController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white24,
                          labelText: "Email",
                          labelStyle: const TextStyle(color: Colors.white),
                          prefixIcon: const Icon(
                            Icons.email_outlined,
                            color: Colors.white,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) =>
                            value!.isEmpty ? "Enter email" : null,
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: passwordController,
                        obscureText: hidePassword,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white24,
                          labelText: "Password",
                          labelStyle: const TextStyle(color: Colors.white),
                          prefixIcon: const Icon(
                            Icons.lock_outline,
                            color: Colors.white,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              hidePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: Colors.white,
                            ),
                            onPressed: () {
                              setState(() => hidePassword = !hidePassword);
                            },
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) =>
                            value!.isEmpty ? "Enter password" : null,
                      ),
                      const SizedBox(height: 30),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: isLoading ? null : login,
                          child: isLoading
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : const Text(
                                  "Login",
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                Row(
                  children: const [
                    Expanded(child: Divider(color: Colors.white54)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text("OR", style: TextStyle(color: Colors.white)),
                    ),
                    Expanded(child: Divider(color: Colors.white54)),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: Colors.grey),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 3,
                    ),
                    onPressed: isLoading ? null : signInWithGoogle,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        FaIcon(
                          FontAwesomeIcons.google,
                          color: Colors.red,
                          size: 20,
                        ),
                        SizedBox(width: 12),
                        Text(
                          "Continue with Google",
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "Don't have an account? ",
                      style: TextStyle(color: Colors.white),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SignupPage(),
                          ),
                        );
                      },
                      child: const Text(
                        "Sign Up",
                        style: TextStyle(
                          color: Colors.deepPurpleAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
