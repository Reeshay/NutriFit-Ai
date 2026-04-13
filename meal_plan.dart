import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nutrifit/cheatmeal.dart';
import 'meal_snap.dart';
import 'compensation_plan.dart';

class MealPlan extends StatefulWidget {
  const MealPlan({
    super.key,
    required this.targetGoal,
    required this.activityLevel,
    this.timelineWeeks,
    required this.gender,
    required this.height,
    required this.age,
    required this.weight,
    required this.healthConditions,
    required this.allergies,
  });

  final String targetGoal;
  final String activityLevel;
  final int? timelineWeeks;
  final String gender;
  final double height;
  final int age;
  final double weight;
  final List<String> healthConditions;
  final List<String> allergies;

  @override
  State<MealPlan> createState() => _MealPlanState();
}

class _MealPlanState extends State<MealPlan> {
  bool loading = true;
  String? errorMessage;
  Map<String, dynamic>? weeklyMealPlanData;

  final User? currentUser = FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    fetchMealPlanFromFirestore();
  }

  Future<void> fetchMealPlanFromFirestore() async {
    if (currentUser == null) {
      setState(() {
        errorMessage = "User not logged in";
        loading = false;
      });
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser!.uid)
          .collection('meal_plan')
          .doc('current_plan')
          .get();

      if (doc.exists && doc.data() != null && doc.data()!['plan'] != null) {
        final planData = Map<String, dynamic>.from(doc.data()!['plan']);

        setState(() {
          weeklyMealPlanData = planData;
          loading = false;
        });
      } else {
        setState(() {
          errorMessage = "No meal plan found. Complete your profile first.";
          loading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = "Error fetching meal plan: $e";
        loading = false;
      });
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
            "Meal Plan",
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.camera_alt, color: Colors.black),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const UploadMealScreen()),
                );
              },
            ),
          ],
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : weeklyMealPlanData == null
                ? Center(child: Text(errorMessage ?? "No data available"))
                : _mealPlanContent(),
      ),
    );
  }

  Widget _mealPlanContent() {
    

    final daysOrder = [
      "Monday",
      "Tuesday",
      "Wednesday",
      "Thursday",
      "Friday",
      "Saturday",
      "Sunday"
    ];
    final todayName = daysOrder[DateTime.now().weekday - 1];
    final sortedDays =
        daysOrder.where((d) => weeklyMealPlanData!.containsKey(d)).toList();

    final firstDay = weeklyMealPlanData![sortedDays.first]!;
    double dailyCalories =
        (firstDay['predicted_daily_calories'] ?? 0).toDouble();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [

        // ✅ 🔥 NEW BUTTON (UNDER CAMERA ICON)
        // Buttons Row — Cheat Meal + View Compensation Plan
Row(
  mainAxisAlignment: MainAxisAlignment.end,
  children: [
    // Cheat Meal button
    ElevatedButton(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const CheatMealScreen(),
          ),
        );
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.grey,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: const Text(
        "Cheat Meal",
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    ),

    const SizedBox(width: 12), // spacing between buttons

    // View Compensation Plan button
    ElevatedButton(
      onPressed: () async {
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser!.uid)
            .collection('meals')
            .where('is_cheat', isEqualTo: true)
            .orderBy('created_at', descending: true)
            .get();

        List<Map<String, dynamic>> compensationPlan = [];

        for (var doc in snapshot.docs) {
          final data = doc.data();
          if (data['compensation_days'] != null) {
            compensationPlan.addAll(
              List<Map<String, dynamic>>.from(data['compensation_days'])
            );
          }
        }

        final Map<String, Map<String, dynamic>> uniqueByDate = {};
        for (var day in compensationPlan) {
          uniqueByDate[day['date']] = day;
        }

        final finalPlan = uniqueByDate.values.toList()
          ..sort((a, b) => a['date'].compareTo(b['date']));

        if (finalPlan.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("No compensation plan available")),
          );
          return;
        }

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CompensationPlan(plan: finalPlan),
          ),
        );
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: const Text(
        "View Compensation Plan",
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    ),
  ],
),
const SizedBox(height: 16), // spacing below buttons
        // Daily Calories Card
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.local_fire_department,
                  size: 30, color: Colors.white),
              const SizedBox(width: 12),
              Text("${dailyCalories.toStringAsFixed(2)} kcal/day",
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
            ],
          ),
        ),

        ...sortedDays.map((dayName) {
          final dayData = weeklyMealPlanData![dayName]!;
          final meals = dayData['meals'] ?? {};
          final isToday = dayName == todayName;

          return Column(
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isToday
                      ? Colors.blue.withOpacity(0.2)
                      : Colors.blueAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(dayName,
                            style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: isToday
                                    ? Colors.blueAccent
                                    : Colors.blue)),
                        if (isToday)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.redAccent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              "Today",
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (meals.containsKey("breakfast"))
                      _buildMealSection(
                          "Breakfast", meals["breakfast"]["items"]),
                    if (meals.containsKey("lunch"))
                      _buildMealSection("Lunch", meals["lunch"]["items"]),
                    if (meals.containsKey("dinner"))
                      _buildMealSection("Dinner", meals["dinner"]["items"]),
                  ],
                ),
              ),
              if (dayName != sortedDays.last)
                const Divider(
                  thickness: 3,
                  color: Colors.blue,
                  height: 32,
                ),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildMealSection(String title, List<dynamic> foods) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueAccent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue)),
          const SizedBox(height: 8),
          ...foods.map((item) => _mealCard(item)),
        ],
      ),
    );
  }

  Widget _mealCard(dynamic item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
          Text(item['food_name'],
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black)),
          const SizedBox(height: 8),
          _foodDetail(Icons.scale, "${item['grams']} g", "Qty", Colors.blue),
          _foodDetail(
              Icons.fastfood, "${item['calories']} kcal", "Calories", Colors.blue),
          _foodDetail(Icons.accessibility,
              "${item['protein_g']} g", "Protein", Colors.blue),
          _foodDetail(Icons.restaurant,
              "${item['carbs_g']} g", "Carbs", Colors.blue),
          _foodDetail(Icons.monitor_weight,
              "${item['fat_g']} g", "Fats", Colors.blue),
        ],
      ),
    );
  }

  Widget _foodDetail(
      IconData icon, String value, String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style:
                      const TextStyle(fontSize: 12, color: Colors.black54)),
              Text(value,
                  style:
                      const TextStyle(fontSize: 14, color: Colors.black87)),
            ],
          ),
        ],
      ),
    );
  }
}