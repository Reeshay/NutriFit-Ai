import 'package:flutter/material.dart';
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
    _loadPlanFromFirestore();
  }


 Future<void> _loadPlanFromFirestore() async {
  if (currentUser == null) {
    setState(() { errorMessage = "User not logged in"; loading = false; });
    return;
  }

  try {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser!.uid)
        .collection('exercise_plan')
        .doc('current_plan')
        .get();

    if (!doc.exists) {
      setState(() { errorMessage = "No exercise plan found."; loading = false; });
      return;
    }

    final data = doc.data()!;
    setState(() {
      planData = Map<String, dynamic>.from(data['plan']);
      timelineWeeks = data['timeline_weeks'];
      loading = false;
    });
  } catch (e) {
    setState(() { errorMessage = "Failed to load plan: $e"; loading = false; });
  }
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