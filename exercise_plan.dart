import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'exercise_video.dart';

class ExercisePlan extends StatefulWidget {
  const ExercisePlan({super.key});

  @override
  State<ExercisePlan> createState() => _ExercisePlanState();
}

class _ExercisePlanState extends State<ExercisePlan> {
  Map<String, dynamic>? planData;
  bool loading = true;
  String? errorMessage;

  String? targetGoal;
  String? activityLevel;
  int? timelineWeeks;

  final User? currentUser = FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _loadProfileAndFetchPlan();
  }

  /// Load profile from Firestore
  Future<void> _loadProfileAndFetchPlan() async {
    if (currentUser == null) {
      setState(() {
        errorMessage = "User not logged in";
        loading = false;
      });
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection("users")
          .doc(currentUser!.uid)
          .get();

      if (!doc.exists) {
        setState(() {
          errorMessage = "Please complete your profile first.";
          loading = false;
        });
        return;
      }

      final data = doc.data()!;
      targetGoal = data["goal"];
      activityLevel = data["activitylevel"];
      timelineWeeks = (data["timeline_weeks"] as num?)?.toInt();

      if (targetGoal == null || activityLevel == null) {
        setState(() {
          errorMessage = "Incomplete profile data.";
          loading = false;
        });
        return;
      }

      await _fetchExercisePlan();
    } catch (e) {
      setState(() {
        errorMessage = "Failed to load profile: $e";
        loading = false;
      });
    }
  }

  Future<void> _fetchExercisePlan() async {
    final url = Uri.parse("http://192.168.18.197:8000/exercise_plan");

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "goal": targetGoal,
          "activitylevel": activityLevel,
          "timeline_weeks": timelineWeeks ?? 4,
        }),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body)["plan"];
        print(decoded);
        setState(() {
          planData = decoded;
          loading = false;
        });

        await _storePlanToFirestore(decoded);
      } else {
        setState(() {
          errorMessage = "Error ${response.statusCode}: ${response.body}";
          loading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = "Backend error: $e";
        loading = false;
      });
    }
  }

  Future<void> _storePlanToFirestore(Map<String, dynamic> data) async {
  if (currentUser == null) return;

  final daysOfWeek = [
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
    "Sunday"
  ];

  Map<String, dynamic> mappedPlan = {};
  int index = 0;

  data.forEach((key, value) {
    if (index < daysOfWeek.length) {
      mappedPlan[daysOfWeek[index]] = value;
      index++;
    }
  });

  await FirebaseFirestore.instance
      .collection('users')
      .doc(currentUser!.uid)
      .collection('exercise_plan')
      .doc('current_plan')
      .set({
    'created_at': FieldValue.serverTimestamp(),
    'timeline_weeks': timelineWeeks,
    'plan': mappedPlan,
  });
}
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Colors.white,
          title: const Text(
  "Exercise Plan",
  style: TextStyle(
    color: Colors.black,
    fontWeight: FontWeight.bold,
    fontSize: 24, // set your original size here
  ),
),

          iconTheme: const IconThemeData(color: Colors.black),
          actions: [
            IconButton(
              icon: const Icon(Icons.video_camera_front_sharp, color: Colors.black),
             
              onPressed: () {

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ExerciseVideo(
            
          ),
        ),
      );
    
  }

            ),
          ],
        ),
        body: loading
            ? Center(
                child: errorMessage == null
                    ? const CircularProgressIndicator()
                    : Text(errorMessage!),
              )
            : _buildPlan(),
      ),
    );
  }

 Widget _buildPlan() {
  if (planData == null || planData!.isEmpty) {
    return const Center(
      child: Text("No exercise plan available."),
    );
  }

  final daysOfWeek = [
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
    "Sunday"
  ];

  int todayIndex = DateTime.now().weekday - 1; // Monday=0

  Map<String, dynamic> mappedPlan = {};
  int index = 0;

  planData!.forEach((key, value) {
    if (index < daysOfWeek.length) {
      mappedPlan[daysOfWeek[index]] = value;
      index++;
    }
  });

  final entries = mappedPlan.entries.toList();

  return SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: entries.asMap().entries.map((entry) {
        final index = entry.key;
        final day = entry.value.key;
        final exercises = entry.value.value as List;

        bool isToday = index == todayIndex;

        return Column(
          children: [
            _dayCard(day, exercises, isToday),
            if (index != entries.length - 1)
              const Divider(color: Colors.blue, thickness: 3, height: 32),
          ],
        );
      }).toList(),
    ),
  );
}
  Widget _dayCard(String day, List exercises, bool isToday) {
  return Container(
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.blueAccent.withOpacity(0.1),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              day,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            if (isToday)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  "Today",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
          ],
        ),

        const SizedBox(height: 10),

        ...exercises.map((ex) => _exerciseTile(ex)),
      ],
    ),
  );
}
  Widget _exerciseTile(dynamic ex) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(blurRadius: 8, color: Colors.grey.withOpacity(0.1))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ex["exercise_name"] ?? "Exercise",
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Sets: ${ex["sets"] ?? "-"}"),
              Text("Reps: ${ex["repetitions"] ?? "-"}"),
              Text("Duration: ${ex["duration"] ?? "-"} min"),
            ],
          ),
        ],
      ),
    );
  }
}
