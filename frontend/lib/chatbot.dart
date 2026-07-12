import 'package:flutter/material.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatbotPage extends StatefulWidget {
  const ChatbotPage({super.key});

  @override
  State<ChatbotPage> createState() => _ChatbotPageState();
}

class _ChatbotPageState extends State<ChatbotPage> {
  final TextEditingController messageController = TextEditingController();
  final ScrollController scrollController = ScrollController();

  List<Map<String, dynamic>> messages = [];
  bool isTyping = false;
Future<Map<String, dynamic>> getUserProfile() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    throw Exception("User not logged in");
  }

  final uid = user.uid;
  final firestore = FirebaseFirestore.instance;

  // Fetch main user document
  final userDoc = await firestore.collection("users").doc(uid).get();
  if (!userDoc.exists) {
    throw Exception("User profile not found in Firestore");
  }
  Map<String, dynamic> profile = userDoc.data()!;

  // Fetch meal_plan from subcollection
  final mealPlanSnap = await firestore
    .collection('users')
    .doc(uid)
    .collection('meal_plan')
    .doc('current_plan')
    .get(GetOptions(source: Source.cache))
    .catchError((_) => firestore
        .collection('users')
        .doc(uid)
        .collection('meal_plan')
        .doc('current_plan')
        .get(GetOptions(source: Source.server)));

  final exerciseSnap = await firestore
      .collection('users')
      .doc(uid)
      .collection('exercise_plan')
      .doc('current_plan')
      .get();

  final WeeklyProgressSnap = await firestore
      .collection('users')
      .doc(uid)
      .collection('progress')
      .doc('weekly')
      .get();
      final MonthlyProgressSnap = await firestore
      .collection('users')
      .doc(uid)
      .collection('progress')
      .doc('monthly')
      .get();
  // Merge meal and exercise plans into profile
  profile['meal_plan'] = mealPlanSnap.exists ? mealPlanSnap.data()! : {};
  profile['exercise_plan'] = exerciseSnap.exists ? exerciseSnap.data()! : {};
  profile['progress'] = {
    "weekly": WeeklyProgressSnap.exists ? WeeklyProgressSnap.data()! : {},
    "monthly": MonthlyProgressSnap.exists ? MonthlyProgressSnap.data()! : {},
  };
  

  print("Full profile including meal & exercise plans: $profile");

  return profile;
}
 void sendMessage() async {
  String message = messageController.text.trim();
  if (message.isEmpty) return;

  setState(() {
    messages.add({"text": message, "isUser": true});
    isTyping = true;
  });

  messageController.clear();
  scrollToBottom();

  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception("User not logged in");

    final uid = user.uid;
    final firestore = FirebaseFirestore.instance;

    // Fetch main user profile
    final userDoc = await firestore.collection('users').doc(uid).get();
    if (!userDoc.exists) throw Exception("User profile not found");
    Map<String, dynamic> profile = userDoc.data()!;

    // Fetch meal plan
    final mealSnap = await firestore
        .collection('users')
        .doc(uid)
        .collection('meal_plan')
        .doc('current_plan')
        .get(GetOptions(source: Source.cache))
    .catchError((_) => firestore
        .collection('users')
        .doc(uid)
        .collection('meal_plan')
        .doc('current_plan')
        .get(GetOptions(source: Source.server)));
    profile['meal_plan'] = mealSnap.exists ? mealSnap.data()! : {};

    // Fetch exercise plan
    final exerciseSnap = await firestore
        .collection('users')
        .doc(uid)
        .collection('exercise_plan')
        .doc('current_plan')
        .get();
    profile['exercise_plan'] = exerciseSnap.exists ? exerciseSnap.data()! : {};

    // Fetch progress
    final weeklySnap = await firestore
        .collection('users')
        .doc(uid)
        .collection('progress')
        .doc('weekly')
        .get();
    final monthlySnap = await firestore
        .collection('users')
        .doc(uid)
        .collection('progress')
        .doc('monthly')
        .get();

      final dailySnap = await firestore
        .collection('users')
        .doc(uid)
        .collection('progress')
        .doc('daily')
        .get();

    profile['progress'] = {
  "weekly": weeklySnap.exists ? weeklySnap.data()! : {},
  "monthly": monthlySnap.exists ? monthlySnap.data()! : {},
  "daily": dailySnap.exists ? dailySnap.data()! : {},
};

// Fetch cheat meals / compensation plan
final cheatSnap = await firestore
    .collection('users')
    .doc(uid)
    .collection('meals')
    .where('is_cheat', isEqualTo: true)
    .orderBy('created_at', descending: true)
    .limit(5)
    .get();

profile['compensation_plans'] = cheatSnap.docs
    .map((d) => d.data())
    .toList();

dynamic convertTimestamps(dynamic data) {
      if (data is Timestamp) return data.toDate().toIso8601String();
      if (data is Map) {
        return data.map((k, v) => MapEntry(k.toString(), convertTimestamps(v)));
      }
      if (data is List) return data.map((e) => convertTimestamps(e)).toList();
      return data;
    }

    profile = convertTimestamps(profile);

    print("Full profile including meal & exercise plans: $profile");

    final response = await http.post(
      Uri.parse("https://nutrifit-backend-production-1761.up.railway.app/chatbot"),
      //Uri.parse("http://192.168.18.197:8000/chatbot"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"user_profile": profile, "message": message}),
    );

    final data = jsonDecode(response.body);

    setState(() {
      messages.add({"text": data["reply"], "isUser": false});
      isTyping = false;
    });
  } catch (e) {
    print("Error sending message: $e");
    setState(() {
      messages.add({"text": "Server error", "isUser": false});
      isTyping = false;
    });
  }

  scrollToBottom();
}
  void scrollToBottom() {
    Timer(const Duration(milliseconds: 300), () {
      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  Widget buildMessage(Map<String, dynamic> message) {
    bool isUser = message["isUser"];

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        padding: const EdgeInsets.all(14),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isUser ? Colors.blueAccent : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          message["text"],
          style: TextStyle(
            color: isUser ? Colors.white : Colors.black87,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  Widget buildTypingIndicator() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 8,
            height: 8,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text("NutriFit AI is typing...")
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text(
          "NutriFit AI Coach",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: messages.length,
              itemBuilder: (context, index) {
                return buildMessage(messages[index]);
              },
            ),
          ),
          if (isTyping) buildTypingIndicator(),
          const Divider(height: 1),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            color: Colors.grey.shade100,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: messageController,
                    enabled: !isTyping,
                    decoration: InputDecoration(
                      hintText: isTyping ? "Waiting for response..." : "Ask something about nutrition...",
                      border: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(
                  icon: isTyping
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent),
                        )
                      : const Icon(Icons.send, color: Colors.blueAccent),
                  onPressed: isTyping ? null : sendMessage,
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}