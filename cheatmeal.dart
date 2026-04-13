import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:nutrifit/compensation_plan.dart';

class CheatMealScreen extends StatefulWidget {
  final String? foodName;
  final double? calories;
  final double? protein;
  final double? carbs;
  final double? fats;

  const CheatMealScreen({
    super.key,
    this.foodName,
    this.calories,
    this.protein,
    this.carbs,
    this.fats,
  });

  @override
  State<CheatMealScreen> createState() => _CheatMealScreenState();
}

class _CheatMealScreenState extends State<CheatMealScreen> {
  final _formKey = GlobalKey<FormState>();

  Map<String, dynamic>? cheatMealResult;

  late TextEditingController nameController;
  late TextEditingController caloriesController;
  late TextEditingController proteinController;
  late TextEditingController carbsController;
  late TextEditingController fatsController;

  bool saving = false;

  static const String _backendUrl = 'http://192.168.18.197:8000/cheatmeal';

  double totalCalories = 0;
  double totalProtein = 0;
  double totalCarbs = 0;
  double totalFats = 0;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.foodName ?? "");
    caloriesController =
        TextEditingController(text: widget.calories?.toString() ?? "");
    proteinController =
        TextEditingController(text: widget.protein?.toString() ?? "");
    carbsController = TextEditingController(text: widget.carbs?.toString() ?? "");
    fatsController = TextEditingController(text: widget.fats?.toString() ?? "");
    _loadLatestCompensationPlan();
  }

  @override
  void dispose() {
    nameController.dispose();
    caloriesController.dispose();
    proteinController.dispose();
    carbsController.dispose();
    fatsController.dispose();
    super.dispose();
  }
Widget _buildMacroBadge(String label, String value, Color color, IconData icon) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 4),
         Flexible(
  child: Text(
    value,
    style: const TextStyle(
      fontWeight: FontWeight.bold,
      color: Colors.black87,
    ),
    overflow: TextOverflow.ellipsis,
  ),
),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        label,
        style: const TextStyle(
          color: Colors.black54,
          fontSize: 12,
        ),
      ),
    ],
  );
}
Widget _buildPlanRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Wrap(
  spacing: 12,
  runSpacing: 12,
  alignment: WrapAlignment.spaceBetween,
  children: [
    SizedBox(
      width: 90,
      child: _buildMacroBadge(
        "Calories",
        "${totalCalories.toStringAsFixed(0)}",
        Colors.orange,
        Icons.local_fire_department,
      ),
    ),
    SizedBox(
      width: 90,
      child: _buildMacroBadge(
        "Protein",
        "${totalProtein.toStringAsFixed(0)} g",
        Colors.green,
        Icons.fitness_center,
      ),
    ),
    SizedBox(
      width: 90,
      child: _buildMacroBadge(
        "Carbs",
        "${totalCarbs.toStringAsFixed(0)} g",
        Colors.blue,
        Icons.bakery_dining,
      ),
    ),
    SizedBox(
      width: 90,
      child: _buildMacroBadge(
        "Fats",
        "${totalFats.toStringAsFixed(0)} g",
        Colors.purple,
        Icons.emoji_food_beverage,
      ),
    ),
  ],
)
  );
}
  Future<void> _loadLatestCompensationPlan() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('meals')
          .where('is_cheat', isEqualTo: true)
          .orderBy('created_at', descending: true)
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final compensation = data['compensation_days'];

        if (compensation != null &&
            compensation is List &&
            compensation.isNotEmpty) {
          if (mounted) {
            setState(() {
              cheatMealResult = {
                "surplus": data['surplus'] ?? 0,
                "severity": data['severity'] ?? '',
                "strategy": data['strategy'] ?? '',
                "window_days": data['window_days'] ?? 0,
                "compensation_days": compensation,
                ...?(data['backend_result'] is Map
                    ? Map<String, dynamic>.from(data['backend_result'])
                    : null),
              };
            });
          }
          break;
        }
      }
    } catch (e) {
      debugPrint("Error loading compensation plan: $e");
    }
  }

  Future<Map<String, dynamic>?> _fetchUserProfile(String uid) async {
    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (!userDoc.exists) return null;
    final data = userDoc.data()!;

    final mealPlanDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('meal_plan')
        .doc('current_plan')
        .get();

    Map<String, dynamic> dailyMacrosTarget = {};
    if (mealPlanDoc.exists) {
      final plan = mealPlanDoc.data()?['plan'] as Map<String, dynamic>? ?? {};
      final firstDay = plan.values.isNotEmpty ? plan.values.first : null;
      if (firstDay != null && firstDay is Map) {
        final dailyMacros =
            firstDay['daily_macros_target'] as Map<String, dynamic>? ?? {};
        dailyMacrosTarget = {
          "daily_calories_target": firstDay['predicted_daily_calories'] ?? 0,
          "daily_protein_target": (dailyMacros['protein_g'] ?? 0).toDouble(),
          "daily_carbs_target": (dailyMacros['carbs_g'] ?? 0).toDouble(),
          "daily_fats_target": (dailyMacros['fat_g'] ?? 0).toDouble(),
        };
      }
    }

    return {
      "user_id": uid,
      "name": data["name"] ?? "",
      "age": data["age"] ?? "",
      "weight": data["weight"] ?? "",
      "height": data["height"] ?? "",
      "gender": data["gender"] ?? "",
      "goal": data["goal"] ?? "",
      "activitylevel": data["activitylevel"] ?? "",
      "bmi": data["bmi"] ?? 0,
      "bmr": data["bmr"] ?? 0,
      "tdee": data["tdee"] ?? 0,
      ...dailyMacrosTarget,
    };
  }

  Future<void> _saveCheatMeal() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !_formKey.currentState!.validate()) return;

    setState(() => saving = true);

    try {
      final mealData = {
        "food_name": nameController.text.trim(),
        "calories": double.tryParse(caloriesController.text) ?? 0,
        "protein_g": double.tryParse(proteinController.text) ?? 0,
        "carbs_g": double.tryParse(carbsController.text) ?? 0,
        "fat_g": double.tryParse(fatsController.text) ?? 0,
        "is_cheat": true,
      };

      final userProfile = await _fetchUserProfile(user.uid);
      if (userProfile == null) throw Exception("User profile not found");

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('meals')
          .get();

      List<Map<String, dynamic>> allMeals = [];

      for (var doc in snapshot.docs) {
        final d = doc.data();
        allMeals.add({
          "food_name": d['food_name'],
          "calories": (d['calories'] ?? 0),
          "protein_g": (d['protein_g'] ?? 0),
          "carbs_g": (d['carbs_g'] ?? 0),
          "fat_g": (d['fat_g'] ?? 0),
          "is_cheat": d['is_cheat'] ?? false,
        });
      }

      allMeals.add(mealData);

      final response = await http.post(
        Uri.parse(_backendUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "user": userProfile,
          "all_meals": allMeals,
          "cheat_meal": {
            ...mealData,
            "created_at": DateTime.now().toIso8601String(),
          },
        }),
      );

      if (response.statusCode != 200) {
        throw Exception("Backend error: ${response.body}");
      }

      final data = jsonDecode(response.body);
      setState(() => cheatMealResult = data);

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('meals')
          .add({
        ...mealData,
        "created_at": FieldValue.serverTimestamp(),
        "backend_result": data,
        "surplus": data["surplus"] ?? 0,
        "severity": data["severity"] ?? "",
        "strategy": data["strategy"] ?? "",
        "window_days": data["window_days"] ?? 0,
        "compensation_days": data["compensation_days"] ?? [],
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data["status"] == "success"
                  ? "Cheat meal analyzed ✅ (${data["strategy"]})"
                  : data["message"] ?? "Saved",
            ),
          ),
        );
      }

      nameController.clear();
      caloriesController.clear();
      proteinController.clear();
      carbsController.clear();
      fatsController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => saving = false);
    }
  }

  Future<void> _deleteCheatMeal(String id) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('meals')
        .doc(id)
        .delete();

    setState(() => cheatMealResult = null);

    await _loadLatestCompensationPlan();
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    bool required = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType:
          label == "Food Name" ? TextInputType.text : TextInputType.number,
      validator: required
          ? (v) => (v == null || v.isEmpty) ? "Required field" : null
          : null,
      style: const TextStyle(fontSize: 16, color: Colors.black87),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            const TextStyle(fontWeight: FontWeight.w500, color: Colors.black54),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Cheat Meals"),
        centerTitle: true,
        backgroundColor: Colors.grey,
       actions: [
  TextButton(
    child: const Text("View Plan"),
    onPressed: () async {
              final user = FirebaseAuth.instance.currentUser;
              if (user == null) return;

              final snapshot = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .collection('meals')
                  .where('is_cheat', isEqualTo: true)
                  .orderBy('created_at', descending: true)
                  .get();

              List<Map<String, dynamic>> mergedPlan = [];

              for (var doc in snapshot.docs) {
                final data = doc.data();
                if (data['compensation_days'] != null) {
                  final days = List<Map<String, dynamic>>.from(
                    data['compensation_days'],
                  );
                  mergedPlan.addAll(days);
                }
              }

              if (mergedPlan.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("No compensation plan available")),
                );
                return;
              }

              final Map<String, Map<String, dynamic>> uniqueByDate = {};
              for (var day in mergedPlan) {
                final date = day['date'];
                uniqueByDate[date] = day;
              }

              final finalPlan = uniqueByDate.values.toList();
              finalPlan.sort(
                  (a, b) => a['date'].toString().compareTo(b['date'].toString()));

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CompensationPlan(plan: finalPlan),
                ),

              );
            },
          ),
        ],
      ),
      body: user == null
          ? const Center(child: Text("Please login to view cheat meals"))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .collection('meals')
                  .where('is_cheat', isEqualTo: true)
                  .orderBy('created_at', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs;

                totalCalories = 0;
                totalProtein = 0;
                totalCarbs = 0;
                totalFats = 0;

                for (var doc in docs) {
                  totalCalories += (doc['calories'] ?? 0).toDouble();
                  totalProtein += (doc['protein_g'] ?? 0).toDouble();
                  totalCarbs += (doc['carbs_g'] ?? 0).toDouble();
                  totalFats += (doc['fat_g'] ?? 0).toDouble();
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                     // Cheat Summary Card
if (docs.isNotEmpty)
  Card(
    margin: const EdgeInsets.only(bottom: 16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "📊 Cheat Summary",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          
          Column(
  children: [
    Row(
      children: [
        Expanded(
          child: _buildMacroBadge(
            "Calories",
            "${totalCalories.toStringAsFixed(0)} kcal",
            Colors.orange,
            Icons.local_fire_department,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMacroBadge(
            "Protein",
            "${totalProtein.toStringAsFixed(0)} g",
            Colors.green,
            Icons.fitness_center,
          ),
        ),
      ],
    ),
    const SizedBox(height: 12),
    Row(
      children: [
        Expanded(
          child: _buildMacroBadge(
            "Carbs",
            "${totalCarbs.toStringAsFixed(0)} g",
            Colors.blue,
            Icons.bakery_dining,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMacroBadge(
            "Fats",
            "${totalFats.toStringAsFixed(0)} g",
            Colors.purple,
            Icons.emoji_food_beverage,
          ),
        ),
      ],
    ),
  ],
),
          const SizedBox(height: 12),

          if (cheatMealResult != null) ...[
            const Divider(),
            Text(
              "Surplus: ${(cheatMealResult!['surplus'] as num?)?.toStringAsFixed(1) ?? '0'} kcal",
            ),
            Text("Severity: ${cheatMealResult!['severity'] ?? '-'}"),
            Text("Strategy: ${cheatMealResult!['strategy'] ?? '-'}"),
            Text("Window: ${cheatMealResult!['window_days'] ?? 0} days"),
          ],
        ],
      ),
    ),
  ),
                      if (docs.isEmpty)
                        const Center(
                          child: Text("No cheat meals yet",
                              style: TextStyle(
                                  fontSize: 16, color: Colors.black54)),
                        ),

                      // Meal cards
                      for (var doc in docs)
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: ListTile(
                            tileColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            title: Text(doc['food_name'] ?? '',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500, fontSize: 16)),
                            subtitle: Text("${doc['calories']} kcal",
                                style: const TextStyle(color: Colors.black54)),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteCheatMeal(doc.id),
                            ),
                          ),
                        ),

                      const SizedBox(height: 20),

                      // Add cheat meal form
                      Form(
                        key: _formKey,
                        child: Card(
                          elevation: 3,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          color: Colors.grey.shade100,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                _buildTextField("Food Name", nameController,
                                    required: true),
                                const SizedBox(height: 12),
                                _buildTextField("Calories", caloriesController,
                                    required: true),
                                const SizedBox(height: 12),
                                _buildTextField("Protein (g)", proteinController,
                                    required: true),
                                const SizedBox(height: 12),
                                _buildTextField("Carbs (g)", carbsController,
                                    required: true),
                                const SizedBox(height: 12),
                                _buildTextField("Fats (g)", fatsController,
                                    required: true),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: saving ? null : _saveCheatMeal,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blueGrey,
                                    minimumSize: const Size(double.infinity, 50),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: saving
                                      ? const CircularProgressIndicator(
                                          color: Colors.white)
                                      : const Text(
                                          "Save Cheat Meal",
                                          style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white),
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}