import 'package:flutter/material.dart';
import 'package:nutrifit/email_verfication.dart';
import 'package:nutrifit/profile_setup.dart';
import 'login_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final usernameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool hidePassword = true;
  bool isLoading = false;

  @override
  void dispose() {
    usernameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  // ================= EMAIL/PASSWORD SIGN-UP =================
  Future<void> signUp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);

    try {
      UserCredential userCredential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      await FirebaseFirestore.instance
          .collection("users")
          .doc(userCredential.user!.uid)
          .set({
        "name": usernameController.text.trim(),
        "email": emailController.text.trim(),
        "createdAt": DateTime.now(),
      });

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (context) => const PersonalInformation()),
      );
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message ?? "Signup failed")));
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> signUpWithGoogle() async {
  setState(() => isLoading = true);

  try {
    await GoogleSignIn.instance.initialize(
      clientId:
          '533865808336-e0crp74eb7egdlhf1c64q1u0eq89ucdl.apps.googleusercontent.com',
    );

    final GoogleSignInAccount googleUser =
        await GoogleSignIn.instance.authenticate();

    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;

    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );

    final userCredential =
        await FirebaseAuth.instance.signInWithCredential(credential);

    final user = userCredential.user!;

    // If already registered
    if (!userCredential.additionalUserInfo!.isNewUser) {
      await FirebaseAuth.instance.signOut();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("This email is already registered."),
        ),
      );
      setState(() => isLoading = false);
      return;
    }

    // Send verification email
    await user.sendEmailVerification();

    // Save user to Firestore
    await FirebaseFirestore.instance
        .collection("users")
        .doc(user.uid)
        .set({
      "name": user.displayName ?? "",
      "email": user.email ?? "",
      "createdAt": FieldValue.serverTimestamp(),
      "emailVerified": false,
    });

    // Navigate to verification page
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const EmailVerificationPage(),
      ),
    );
  } catch (e) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text("Error: $e")));
  } finally {
    if (mounted) setState(() => isLoading = false);
  }
}

  // ================= UI =================
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
                  "Create Account",
                  style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Sign up to get started",
                  style:
                      TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 40),

                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        key: const Key('signup_username'),
                        controller: usernameController,
                        style:
                            const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white24,
                          labelText: "Username",
                          labelStyle: const TextStyle(
                              color: Colors.white),
                          prefixIcon: const Icon(
                              Icons.person_outline,
                              color: Colors.white),
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) =>
                            value!.isEmpty
                                ? "Enter username"
                                : null,
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        key: const Key('signup_email'),
                        controller: emailController,
                        style:
                            const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white24,
                          labelText: "Email",
                          labelStyle: const TextStyle(
                              color: Colors.white),
                          prefixIcon: const Icon(
                              Icons.email_outlined,
                              color: Colors.white),
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) =>
                            value!.isEmpty
                                ? "Enter email"
                                : null,
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        key: const Key('signup_password'),
                        controller: passwordController,
                        obscureText: hidePassword,
                        style:
                            const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white24,
                          labelText: "Password",
                          labelStyle: const TextStyle(
                              color: Colors.white),
                          prefixIcon: const Icon(
                              Icons.lock_outline,
                              color: Colors.white),
                          suffixIcon: IconButton(
                            icon: Icon(
                              hidePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: Colors.white,
                            ),
                            onPressed: () {
                              setState(() =>
                                  hidePassword =
                                      !hidePassword);
                            },
                          ),
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) =>
                            value!.isEmpty
                                ? "Enter password"
                                : null,
                      ),
                      const SizedBox(height: 30),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Colors.deepPurple,
                            shape:
                                RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(12),
                            ),
                          ),
                          onPressed:
                              isLoading ? null : signUp,
                          child: isLoading
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : const Text(
                                  "Sign Up",
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.white,
                                    fontWeight:
                                        FontWeight.bold,
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
                    Expanded(
                        child:
                            Divider(color: Colors.white54)),
                    Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        "OR",
                        style: TextStyle(
                            color: Colors.white),
                      ),
                    ),
                    Expanded(
                        child:
                            Divider(color: Colors.white54)),
                  ],
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: OutlinedButton(
                    key: const Key('signup_google'),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      side: const BorderSide(
                          color: Colors.grey),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: isLoading
                        ? null
                        : signUpWithGoogle,
                    child: const Row(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: [
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
                            fontWeight:
                                FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                Row(
                  mainAxisAlignment:
                      MainAxisAlignment.center,
                  children: [
                    const Text(
                      "Already have an account? ",
                      style:
                          TextStyle(color: Colors.white),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                              builder: (context) =>
                                  const LoginPage()),
                        );
                      },
                      child: const Text(
                        "Login",
                        style: TextStyle(
                          color:
                              Colors.deepPurpleAccent,
                          fontWeight:
                              FontWeight.bold,
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
