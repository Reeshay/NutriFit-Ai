import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:nutrifit/notification.dart';
import 'package:nutrifit/get_started.dart';
import 'home_page.dart';
import 'dart:async';

class PersonalInformation extends StatefulWidget {
  const PersonalInformation({super.key});

  @override
  State<PersonalInformation> createState() => _PersonalInfoPageState();
}

class _PersonalInfoPageState extends State<PersonalInformation> {
  final _formKey = GlobalKey<FormState>();
  int? timelineWeeks;
  double? caloriesBurned;
final NotificationService notificationService = NotificationService();

  final nameController = TextEditingController();
  final ageController = TextEditingController();
  final weightController = TextEditingController();
  final heightController = TextEditingController();
  final targetTimeLineController = TextEditingController();
  final targetWeightController = TextEditingController();
bool hasShownProfileReminder = false;
final List<String> allergyOptions = [
  "Egg",
  "Mushroom",
  "Seafood",
  "Wheat",
  "Nuts",
  "Gluten",
  "Dairy"
];

final List<String> healthConditionOptions = [
  "Diabetes",
  "Hypertension",
  "Heart Disease"
];

  List<String> selectedAllergies = [];
List<String> selectedHealthConditions = [];
  String gender = "Male";
  String activitylevel = "Sedentary";
  String fitnessGoal = "Weight Loss";

  Map<String, List<String>> foodPreferences = {
    "breakfast": [],
    "lunch": [],
    "dinner": [],
  };

  static const List<String> _breakfastFoods = 
     ["Toasted Plain Waffles", "Chocolate Pudding", "Vanilla Wafers", "Apple Pie", "Banana Pudding",
                   "Sweet Roll", "Plain Muffin", "Yogurt", "Buttermilk Pancakes", "Pecan Pie", "Jelly Doughnut",
                   "Diet Cheesecake", "Pancakes", "Cupcakes with Frosting (Low Fat)", "Brownie", "Fruit Waffle",
                   "Peanut Butter Cookies", "Fruit and Nuts Muffin", "Peanut Butter Fudge", "Cupcake", "Cookie",
                   "French Toast", "Bread Stuffing", "Cheese Spread", "Protein Powder", "Chocolate Sponge Cake", "Oats",
                   "Boiled egg", "Egg omelette", "Paratha", "Brown bread", "Cereal", "Halwa", "Kheer", "Lassi", "Chai",
                   "Roti", "Garlic Naan", "Vanilla Yogurt", "Milk", "Buttermilk", "Green tea", "Coffee",
                   "Hot cocoa milk", "Milkshake", "Lemonade", "Orange juice", "Mango juice", "Pineapple juice",
                   "Grapefruit juice", "Vegetable juice", "Detox Water", "Skim Chocolate Milk", "Fruit smoothie",
                   "Biscuits", "Dried Fruit Mix", "Dried Apricot", "Raisins", "Figs", "Banana", "Apple", "Orange",
                   "Grapes", "Strawberries", "Kiwi", "Pineapple", "Mango", "Peach", "Pear", "Plum", "Avocado",
                   "Berries", "Fruit Salad", "Raspberries", "Coconut", "Fruit chaat"];

  static const List<String> _lunchFoods = ["Cabbage Salad or Coleslaw with Dressing", "Chicken or Turkey Salad",
               "Lettuce Salad with Avocado, Tomato, and/or Carrots", "Chicken or Turkey Garden Salad",
               "Mixed Salad Greens", "Vegetable Salad", "Fruit chaat", "Chickpea Salad", "Spaghetti", "Brown Rice",
               "Pasta with Meat Sauce", "Mushroom Risotto", "Egg Noodles", "Noodles", "Lasagna with Chicken or Turkey",
               "Whole Wheat Spaghetti", "Macaroni with Cheese", "White Rice", "Brown and Wild Rice",
               "Chicken Fried Rice", "Rice Pilaf", "Rice Noodles", "Fried Rice", "Spaghetti with Meatballs",
               "Shrimp Fried Rice", "Lasagna with Meat", "Vegetable Macaroni", "Chicken Soup", "Tomato Soup",
               "Vegetable Soup", "Chicken Rice Soup", "Beef Stock", "Chicken Chili", "Beef Noodle Soup",
               "Chicken Noodle Soup", "Chicken curry", "Beef Curry", "Mutton Curry", "Chicken biryani", "Beef biryani",
               "Mutton biryani", "Cooked lentils", "Nihari", "Haleem", "Chicken breast", "Chicken thigh",
               "Chicken wing", "Chicken drumstick", "Grilled chicken", "Roasted chicken", "Beef steak", "Lamb chop",
               "Fried fish", "Chicken patties", "Chicken corn soup", "Mashed potato", "Plain pancakes", "Palak paneer",
               "Egg fried rice", "Cooked mixed vegetable"];

  static const List<String> _dinnerFoods = ["Lasagna with Meat and Spinach", "Beef Curry", "Mutton Curry", "Chicken Curry", "Lamb Curry",
                "Beef biryani", "Chicken biryani", "Mutton biryani", "Nihari", "Haleem", "Chicken Sajji",
                "Murgh Mussallam", "Chapali Kabab", "Shami Kabab", "Dal makhani", "Shahi paneer", "Malai kofta",
                "Sarson ka saag", "Kashmiri rogan josh", "Dum aloo", "Matar paneer", "Chicken chow mein",
                "Stuffed eggplant", "Aloo keema", "Tawa chicken", "Fish tikka", "Grilled fish", "Lobster", "Shrimp",
                "Beef steak", "Lamb chop", "Fried mutton chop", "Roast beef", "Grilled chicken", "Roasted chicken",
                "Chicken thigh", "Chicken wing", "Chicken drumstick", "Chicken breast", "Beef meatballs",
                "Chicken meatballs", "Beef sausage", "Chicken sausage", "Salami", "Corned beef", "Pizza",
                "Cheese pizza", "Pepperoni pizza", "French bread pizza", "Cheeseburger", "Veggie burger",
                "Chicken nuggets", "Fish fillet", "Tempura roll", "Chicken spring roll", "Beef chow mein",
                "Egg roll with chicken", "Roti", "Kidney bean curry", "Kofta curry", "Chicken pulao", "Fried fish",
                "Chocolate cake", "Custard", "Vanilla fudge", "Ice cream cone", "Garlic Naan Bread", "Roti"];

  double? bmi;
  double? bmr;
  double? tdee;
  final User? currentUser = FirebaseAuth.instance.currentUser;

  bool isLoading = false;
  bool isValidating = false;
  bool _wasProfileAlreadyCompleted = false;

  Map<String, bool> fieldLoading = {
    "name": true,
    "age": true,
    "height": true,
    "weight": true,
    "targetWeight": true,
    "targetTimeLine": true,
    "gender": true,
    "activitylevel": true,
    "fitnessGoal": true,
  };

  Map<String, String?> backendErrors = {};

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }
bool _areRequiredFieldsFilled() {
  return nameController.text.trim().isNotEmpty &&
      ageController.text.trim().isNotEmpty &&
      heightController.text.trim().isNotEmpty &&
      weightController.text.trim().isNotEmpty &&
      targetWeightController.text.trim().isNotEmpty &&
      gender.isNotEmpty &&
      activitylevel.isNotEmpty &&
      fitnessGoal.isNotEmpty;
}
  Future<void> _loadUserInfo() async {
  if (currentUser == null) {
    setState(() => fieldLoading.updateAll((key, value) => false));
    return;
  }

  try {
    final doc = await FirebaseFirestore.instance
        .collection("users")
        .doc(currentUser!.uid)
        .get();

    if (doc.exists) {
      final data = doc.data()!;
      
      setState(() {
        nameController.text = data["name"] ?? "";
        ageController.text = data["age"]?.toString() ?? "";
        _wasProfileAlreadyCompleted = data["isProfileCompleted"] == true;
        heightController.text = data["height"]?.toString() ?? "";
        weightController.text = data["weight"]?.toString() ?? "";
        targetWeightController.text = data["targetWeight"]?.toString() ?? "";
        targetTimeLineController.text = data["targetTimeLine"] ?? "";
        gender = data["gender"] ?? "Male";
        activitylevel = data["activitylevel"] ?? "Sedentary";
        fitnessGoal = ["Weight Loss", "Weight Gain", "Maintain"]
                .contains(data["goal"])
            ? data["goal"]
            : "Weight Loss";
        selectedAllergies = List<String>.from(data["allergies"] ?? []);
        selectedHealthConditions = List<String>.from(data["healthConditions"] ?? []);
        if (data["food_preferences"] != null) {
          final fp = Map<String, dynamic>.from(data["food_preferences"]);
          foodPreferences["breakfast"] = List<String>.from(fp["breakfast"] ?? []);
          foodPreferences["lunch"] = List<String>.from(fp["lunch"] ?? []);
          foodPreferences["dinner"] = List<String>.from(fp["dinner"] ?? []);
        }
        fieldLoading.updateAll((key, value) => false);
      });
    } else {
      setState(() => fieldLoading.updateAll((key, value) => false));
    }
  } catch (e) {
    setState(() => fieldLoading.updateAll((key, value) => false));
    debugPrint("Error loading user info: $e");
  }
}

  void validateWithBackend() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() => isValidating = true);
      final payload = {
        "age": ageController.text,
        "height": heightController.text,
        "weight": weightController.text,
        "targetWeight": targetWeightController.text,
        "gender": gender,
        "activitylevel": activitylevel,
        "goal": fitnessGoal,
        if (targetTimeLineController.text.isNotEmpty)
          "timeline": targetTimeLineController.text,
      };

      try {
        final response = await http.post(
          Uri.parse("https://nutrifit-backend-production-1761.up.railway.app/profile_validate"),
          //Uri.parse("http://192.168.18.197:8000/profile_validate"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(payload),
        );

        final data = jsonDecode(response.body);

      setState(() {
        isValidating = false;
  backendErrors.clear();
  if (data["status"] == "error") {
    backendErrors.addAll(Map<String, String?>.from(data["errors"] ?? {}));
  } else {
    if (data["warnings"] != null) {
      backendErrors.addAll(Map<String, String?>.from(data["warnings"]));
    }
  }
});

// setState ke BAAD validate call karo — ab errors map updated hai
WidgetsBinding.instance.addPostFrameCallback((_) {
  _formKey.currentState?.validate();
});

      } catch (e) {
        setState(() => isValidating = false);
      }
    });
  }
// ---- Reset helpers (class-level, not nested) ----
Future<void> _resetEatenFoods() async {
  final foods = await FirebaseFirestore.instance
      .collection("users")
      .doc(currentUser!.uid)
      .collection("eaten_foods")
      .get();
  // Parallel delete — fast even with many docs
  await Future.wait(foods.docs.map((doc) => doc.reference.delete()));
}

Future<void> _resetProgress() async {
  final progressDocs = await FirebaseFirestore.instance
      .collection("users")
      .doc(currentUser!.uid)
      .collection("progress")
      .get();
  // Parallel delete
  await Future.wait(progressDocs.docs.map((doc) => doc.reference.delete()));
}
// -------------------------------------------------

Future<void> _saveUserInfo() async {
  
  if (!_formKey.currentState!.validate()) return;

  if (backendErrors.isNotEmpty) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _formKey.currentState?.validate();
  });
  return;
}

  final emptyMeals = <String>[];
  if (foodPreferences["breakfast"]!.isEmpty) emptyMeals.add("Breakfast");
  if (foodPreferences["lunch"]!.isEmpty) emptyMeals.add("Lunch");
  if (foodPreferences["dinner"]!.isEmpty) emptyMeals.add("Dinner");

  if (emptyMeals.isNotEmpty) {
    _showFoodPreferenceError(emptyMeals);
    return;
  }

  setState(() => isLoading = true);

  try {
    Map<String, dynamic> info = {
  "uid": currentUser?.uid,
  "name": nameController.text,
  "age": int.tryParse(ageController.text) ?? 0,
  "height": double.tryParse(heightController.text) ?? 0.0,
  "weight": double.tryParse(weightController.text) ?? 0.0,
  "targetWeight": double.tryParse(targetWeightController.text) ?? 0.0,
  "gender": gender,
  "activitylevel": activitylevel,
  "goal": fitnessGoal,
  "targetTimeLine": targetTimeLineController.text,
  "allergies": selectedAllergies,
  "healthConditions": selectedHealthConditions,
  "food_preferences": _buildFoodPreferencesPayload(),
};

  final userDoc = await FirebaseFirestore.instance
    .collection("users")
    .doc(currentUser!.uid)
    .get();

  bool wasProfileCompleted = userDoc.data()?["isProfileCompleted"] ?? false;

  if (!wasProfileCompleted) {
    // Run both resets in parallel — no need to wait sequentially
    await Future.wait([_resetEatenFoods(), _resetProgress()]);
  }
    // 🔹 Call backend once
    final metrics = await _sendToPythonBackend(info);
    if (metrics == null) return;

    // 🔹 Map the meal plan
   
DateTime now = DateTime.now();
String getMonthName(int month) {
  const months = [
    "January", "February", "March", "April",
    "May", "June", "July", "August",
    "September", "October", "November", "December"
  ];
  return months[month - 1];
}
String monthName = getMonthName(now.month);
int weekNumber = ((now.day - 1) ~/ 7) + 1;

Map<String, dynamic> weightEntry = {
  "weight": double.tryParse(weightController.text) ?? 0,
  "month": monthName,
  "week": "Week $weekNumber",
  "date": now.toIso8601String(),
};
    

    await FirebaseFirestore.instance
    .collection("users")
    .doc(currentUser!.uid)
    .set({
  ...info,
  "age": int.tryParse(ageController.text) ?? 0,           
  "height": double.tryParse(heightController.text) ?? 0.0, 
  "weight": double.tryParse(weightController.text) ?? 0.0, 
  "targetWeight": double.tryParse(targetWeightController.text) ?? 0.0, 
  "weightHistory": FieldValue.arrayUnion([weightEntry]),
  "isProfileCompleted": true,
  "bmi": metrics["bmi"],
  "bmr": metrics["bmr"],
  "tdee": metrics["tdee"],
  "calories_burned": metrics["calories_burned"],
  "timeline_weeks": (metrics["timeline_weeks"] as num?)?.toInt(),
  "timelineWeeks": (metrics["timeline_weeks"] as num?)?.toInt(),
  "meal_plan_last_updated": DateTime.now().toIso8601String(),
  "profile_updated_at": FieldValue.serverTimestamp(),
  "food_preferences": _buildFoodPreferencesPayload(),
}, SetOptions(merge: true));
   await _generateAndStoreExercisePlan(
  goal: fitnessGoal,
  activityLevel: activitylevel,
  timelineWeeks: (metrics["timeline_weeks"] as num?)?.toInt() ?? 4,
  userId: currentUser!.uid,
);

final mealResult = await _generateAndStoreMealPlan(
  userId: currentUser!.uid,
  info: info,
  timelineWeeks: (metrics["timeline_weeks"] as num?)?.toInt() ?? 4,
);

if (mealResult["success"] != true) {
  if (mounted) {
    _showMealPlanErrorDialog(mealResult["message"] ?? "Could not generate meal plan. Please adjust food preferences.");
  }
  return;
}

   // 🔔 Send goal-specific motivational notifications
    final String userName = nameController.text.trim().split(" ").first;
    final bool isNewProfile = !_wasProfileAlreadyCompleted;

    if (isNewProfile) {
      // Welcome notification — only on first-time profile setup
      await notificationService.showNotification(
        "Welcome aboard, $userName! 🎉",
        "Your personalized meal & exercise plan is ready. Your transformation starts today!",
        Duration.zero,
      );
    } else {
      // Profile updated notification
      await notificationService.showNotification(
        "Profile Updated ✅",
        "Your plans have been refreshed based on your new goals. Stay consistent!",
        Duration.zero,
      );
    }

    // Goal-specific motivational nudge
    if (fitnessGoal == "Weight Loss") {
      await notificationService.showNotification(
        "Weight Loss Journey Begins 🔥",
        "Every meal logged and every workout done brings you closer to your goal. You've got this!",
        Duration.zero,
      );
    } else if (fitnessGoal == "Weight Gain") {
      await notificationService.showNotification(
        "Muscle Building Mode ON 💪",
        "Fuel your body right and train hard. Your personalized plan is designed to help you bulk up safely.",
        Duration.zero,
      );
    } else if (fitnessGoal == "Maintain") {
      await notificationService.showNotification(
        "Stay Strong, Stay Consistent 🏅",
        "Maintaining your weight is a victory too. Keep following your plan and feel your best every day.",
        Duration.zero,
      );
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomePage()),
      (_) => false,
    );

  } finally {
    setState(() => isLoading = false);
  }
}
Future<Map<String, dynamic>> _generateAndStoreMealPlan({
  required String userId,
  required Map<String, dynamic> info,
  required int timelineWeeks,
}) async {
  try {
    final url = Uri.parse("https://nutrifit-backend-production-1761.up.railway.app/meal_plan");
    //final url = Uri.parse("http://192.168.18.197:8000/meal_plan");
    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
     body: jsonEncode({
  "uid": userId,
  "name": info["name"],
  "age": info["age"],
  "height_cm": info["height"],
  "weight_kg": info["weight"],
  "targetWeight": info["targetWeight"],
  "activity_level": info["activitylevel"],
  "gender": info["gender"],
  "target_goal": info["goal"],
  "allergies": info["allergies"],
  "health_conditions": info["healthConditions"],
  "timeline_weeks": timelineWeeks,
  "food_preferences": info["food_preferences"],
}),
    );
    print("MEAL PLAN API RESPONSE: ${response.statusCode}");
    print("MEAL PLAN BODY: ${response.body}");
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      print("MEAL PLAN STATUS: ${data['status']}");
      if (data["status"] == "success") {
        print("FIRESTORE WRITE STARTING");
        final mealPlan = Map<String, dynamic>.from(data["meal_plan"]);

        const dayKeys = ["day_1","day_2","day_3","day_4","day_5","day_6","day_7"];
        const dayNames = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"];

        Map<String, dynamic> mappedPlan = {};
        for (int i = 0; i < dayKeys.length; i++) {
          if (mealPlan.containsKey(dayKeys[i])) {
            mappedPlan[dayNames[i]] = mealPlan[dayKeys[i]];
          }
        }

        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('meal_plan')
            .doc('current_plan')
            .set({
          'plan': mappedPlan,
          'meal_plan_last_updated': DateTime.now().toIso8601String(),
          'timeline_weeks': timelineWeeks,
          'food_preferences': info["food_preferences"],
        });
        print("FIRESTORE WRITE DONE");
        return {"success": true};
      } else {
        return {
          "success": false,
          "message": data["message"] ?? "Could not generate meal plan. Please adjust food preferences."
        };
      }
    }
    return {
      "success": false,
      "message": "Server error. Please try again."
    };
  } catch (e) {
    debugPrint("Meal plan generate error: $e");
    return {
      "success": false,
      "message": "Could not generate meal plan. Please adjust food preferences."
    };
  }
}
Future<void> _generateAndStoreExercisePlan({
  required String goal,
  required String activityLevel,
  required int timelineWeeks,
  required String userId,
}) async {
  try {
    final url = Uri.parse("https://nutrifit-backend-production-1761.up.railway.app/exercise_plan");
    //final url = Uri.parse("http://192.168.18.197:8000/exercise_plan");
    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "goal": goal,
        "activitylevel": activityLevel,
        "timeline_weeks": timelineWeeks,
      }),
    );


    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body)["plan"] as Map<String, dynamic>;

      final daysOfWeek = [
        "Monday", "Tuesday", "Wednesday", "Thursday",
        "Friday", "Saturday", "Sunday"
      ];

      Map<String, dynamic> mappedPlan = {};
      int index = 0;
      decoded.forEach((key, value) {
        if (index < daysOfWeek.length) {
          mappedPlan[daysOfWeek[index]] = value;
          index++;
        }
      });

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('exercise_plan')
          .doc('current_plan')
          .set({
        'created_at': FieldValue.serverTimestamp(),
        'timeline_weeks': timelineWeeks,
        'plan': mappedPlan,
      });
    }
  } catch (e) {
    debugPrint("Exercise plan generate error: $e");
    // silently fail — user ko block mat karo
  }
}

Future<Map<String, dynamic>?> _sendToPythonBackend(Map<String, dynamic> info) async {
  try {
    final serverData = {
  "uid": currentUser?.uid,
  "name": info["name"],
  "age": info["age"],
  "height": info["height"],
  "weight": info["weight"],
  "targetWeight": info["targetWeight"],
  "activitylevel": info["activitylevel"],
  "gender": info["gender"],
  "goal": info["goal"],
  "allergies": info["allergies"],
  "health_conditions": info["healthConditions"],
  if ((info["targetTimeLine"] ?? "").toString().isNotEmpty)
    "timeline": info["targetTimeLine"],
};
    final response = await http.post(
      Uri.parse("https://nutrifit-backend-production-1761.up.railway.app/profile_setup"),
      //Uri.parse("http://192.168.18.197:8000/profile_setup"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(serverData),
    );

    final data = jsonDecode(response.body);
    
    if (data["status"] == "success") {
  setState(() {
    bmi = (data["bmi"] as num).toDouble();
    bmr = (data["bmr"] as num).toDouble();
    tdee = (data["tdee"] as num).toDouble();
    caloriesBurned = (data["calories_burned"] as num).toDouble();
    timelineWeeks = (data["timeline_weeks"] as num?)?.toInt();
    print("FULL BACKEND RESPONSE: $data");
  });

  return {
    "bmi": bmi,
    "bmr": bmr,
    "calories_burned": caloriesBurned,
    "tdee": tdee,
    "warning": data["warning"] ?? "",
    "goal_warning": data["goal_warning"] ?? "",
    "timeline_weeks": (data["timeline_weeks"] as num?)?.toInt(),
    "meal_plan": data["meal_plan"] ?? {},
    "plan": data["mappedPlan"],
  };
   } else if (data["status"] == "error") {
  setState(() {
    backendErrors.clear();
    backendErrors.addAll(Map<String, String?>.from(data["errors"] ?? {}));
  });
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _formKey.currentState?.validate();
  });
  return null;
}
  } catch (e) {
    _showWarningDialog("Error connecting to backend. Try again.");
  }
  return null;
}

  void _showWarningDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Warning"),
        content: SingleChildScrollView(
          child: Text(message),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  void _showFoodPreferenceError(List<String> emptyMeals) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: const Color(0xFF1E1E1E),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFFFF6B35),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.restaurant_menu, color: Colors.white, size: 32),
              ),
              const SizedBox(height: 16),
              const Text(
                "Food Selection Required",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                "Please select at least 1 food for each meal type to generate your meal plan.",
                style: TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B35).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFF6B35).withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Missing meals:",
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    ...emptyMeals.map((meal) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Color(0xFFFF6B35), size: 16),
                          const SizedBox(width: 8),
                          Text(
                            meal,
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    )),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B35),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text("OK", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> _buildFoodPreferencesPayload() {
    return {
      "breakfast": foodPreferences["breakfast"]!,
      "lunch": foodPreferences["lunch"]!,
      "dinner": foodPreferences["dinner"]!,
    };
  }

  void _showMealPlanErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Meal Plan Error"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
  onWillPop: () async => _wasProfileAlreadyCompleted,
  child: Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: _wasProfileAlreadyCompleted,
          backgroundColor: Colors.grey,
          elevation: 0,
          title: const Text(
            "Profile Setup",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.white),
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const GetStartedPage()),
                  (_) => false,
                );
              },
            ),
          ],
        ),
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage("images/profile_setup.jpeg"),
              fit: BoxFit.cover,
            ),
          ),
          child: Container(
            color: Colors.black54,
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  children: [
                    _buildTextFieldWithLoader("Full Name", nameController, fieldLoading["name"]!, keyName: "name"),
                    const SizedBox(height: 16),
                    _buildTextFieldWithLoader("Age", ageController, fieldLoading["age"]!, keyboardType: TextInputType.number, keyName: "age"),
                    const SizedBox(height: 16),
                    _buildDropdownWithLoader("Gender", gender, ["Male", "Female"], (val) {
                      if (val != null) gender = val;
                      validateWithBackend();
                      setState(() {});
                    }, fieldLoading["gender"]!, keyName: "gender"),
                    const SizedBox(height: 16),
                    _buildTextFieldWithLoader("Height (ft)", heightController, fieldLoading["height"]!, keyboardType: TextInputType.number, keyName: "height"),
                    const SizedBox(height: 16),
                    _buildTextFieldWithLoader("Weight (kg)", weightController, fieldLoading["weight"]!, keyboardType: TextInputType.number, keyName: "weight"),
                    const SizedBox(height: 16),
                    _buildDropdownWithLoader(
                      "Fitness Goal",
                      fitnessGoal,
                      ["Weight Loss", "Weight Gain", "Maintain"],
                      (val) {
                        if (val != null) fitnessGoal = val;
                        validateWithBackend();
                        setState(() {});
                      },
                      fieldLoading["fitnessGoal"]!,
                      keyName: "goal",
                    ),
                    
                    const SizedBox(height: 16),
                    _buildTextFieldWithLoader("Target Weight (kg)", targetWeightController, fieldLoading["targetWeight"]!, keyboardType: TextInputType.number, keyName: "targetWeight"),
                    const SizedBox(height: 16),
                    _buildDropdownWithLoader(
                      "Activity Level",
                      activitylevel,
                      ["Sedentary", "Lightly Active", "Moderately Active", "Very Active", "Extra Active"],
                      (val) {
                        if (val != null) activitylevel = val;
                        validateWithBackend();
                        setState(() {});
                      },
                      fieldLoading["activitylevel"]!,
                      keyName: "activitylevel",
                    ),
                    
                    _buildAllergySection(),
_buildHealthConditionSection(),
_buildFoodPreferenceSection(),
                    _buildDatePicker(),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: (isLoading || isValidating || !_areRequiredFieldsFilled()) ? null : _saveUserInfo,
                        child: isLoading
    ? const CircularProgressIndicator(color: Colors.white)
    : isValidating
        ? const Text("Validating...", style: TextStyle(fontSize: 18, color: Colors.white70))
        : const Text("Save & Continue", style: TextStyle(fontSize: 18, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextFieldWithLoader(String label, TextEditingController controller, bool loading, {TextInputType keyboardType = TextInputType.text, String? keyName}) {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            style: const TextStyle(color: Colors.white),
            onChanged: (_) {
  setState(() {});
  validateWithBackend();
},
            validator: (_) => keyName != null ? backendErrors[keyName] : null,
            decoration: InputDecoration(
              errorMaxLines: 5,
              labelText: label,
              labelStyle: const TextStyle(color: Colors.white70),
              filled: true,
              fillColor: Colors.white24,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        if (loading) const SizedBox(width: 10),
        if (loading)
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          ),
      ],
    );
  }

  Widget _buildDropdownWithLoader(String label, String value, List<String> items, Function(String?) onChanged, bool loading, {String? keyName}) {
    if (!items.contains(value)) {
      value = items.isNotEmpty ? items[0] : '';
    }

    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            value: value,
            dropdownColor: Colors.black87,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              errorMaxLines: 5,
              labelText: label,
              labelStyle: const TextStyle(color: Colors.white70),
              filled: true,
              fillColor: Colors.white24,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            items: items.map((item) => DropdownMenuItem(
              value: item,
              child: Text(item, style: const TextStyle(color: Colors.white)),
            )).toList(),
            onChanged: onChanged,
            validator: (_) => keyName != null ? backendErrors[keyName] : null,
          ),
        ),
        if (loading) const SizedBox(width: 10),
        if (loading)
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          ),
      ],
    );
  }
Widget _buildHealthConditionSection() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text("Select Health Conditions",
          style: TextStyle(color: Colors.white70, fontSize: 14)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        children: healthConditionOptions.map((item) {
          final isSelected = selectedHealthConditions.contains(item);
          return FilterChip(
            label: Text(item),
            labelStyle: const TextStyle(color: Colors.white),
            selected: isSelected,
            checkmarkColor: Colors.white,
            selectedColor: Colors.black,
            backgroundColor: Colors.black,
            onSelected: (selected) {
              setState(() {
                if (selected) {
                  selectedHealthConditions.add(item);
                } else {
                  selectedHealthConditions.remove(item);
                }
              });
            },
          );
        }).toList(),
      ),
      const SizedBox(height: 16),
    ],
  );
}

Widget _buildFoodPreferenceSection() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text("Food Preferences (Optional)",
          style: TextStyle(color: Colors.white70, fontSize: 14)),
      const SizedBox(height: 4),
      const Text("Uncheck foods you don't want in your meal plan",
          style: TextStyle(color: Colors.white38, fontSize: 11)),
      const SizedBox(height: 8),
      _buildFoodExpansionTile("Breakfast", "breakfast", _breakfastFoods),
      const SizedBox(height: 8),
      _buildFoodExpansionTile("Lunch", "lunch", _lunchFoods),
      const SizedBox(height: 8),
      _buildFoodExpansionTile("Dinner", "dinner", _dinnerFoods),
      const SizedBox(height: 16),
    ],
  );
}

Widget _buildFoodExpansionTile(String title, String mealType, List<String> foods) {
  final selected = foodPreferences[mealType] ?? [];
  final allSelected = selected.length == foods.length;

  return Container(
    decoration: BoxDecoration(
      color: Colors.white12,
      borderRadius: BorderRadius.circular(12),
    ),
    child: ExpansionTile(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          Text("${selected.length}/${foods.length}",
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
      iconColor: Colors.white,
      collapsedIconColor: Colors.white70,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  setState(() {
                    if (allSelected) {
                      foodPreferences[mealType] = [];
                    } else {
                      foodPreferences[mealType] = List<String>.from(foods);
                    }
                  });
                },
                child: Text(
                  allSelected ? "Deselect All" : "Select All",
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        ...([...foods]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()))).map((food) {
          final isSelected = selected.contains(food);
          return CheckboxListTile(
            value: isSelected,
            title: Text(food, style: const TextStyle(color: Colors.white, fontSize: 13)),
            activeColor: Colors.white,
            checkColor: Colors.black,
            dense: true,
            onChanged: (val) {
              setState(() {
                if (val == true) {
                  foodPreferences[mealType]!.add(food);
                } else {
                  foodPreferences[mealType]!.remove(food);
                }
              });
            },
          );
        }),
        const SizedBox(height: 8),
      ],
    ),
  );
}
  Widget _buildAllergySection() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text("Select Allergies",
          style: TextStyle(color: Colors.white70, fontSize: 14)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        children: allergyOptions.map((item) {
          final isSelected = selectedAllergies.contains(item);
          return FilterChip(
            label: Text(item),
            labelStyle: const TextStyle(color: Colors.white),
            selected: isSelected,
            checkmarkColor: Colors.white,
            selectedColor: Colors.black,
            backgroundColor: Colors.black,
            onSelected: (selected) {
              setState(() {
                if (selected) {
                  selectedAllergies.add(item);
                } else {
                  selectedAllergies.remove(item);
                }
              });
            },
          );
        }).toList(),
      ),
      const SizedBox(height: 16),
    ],
  );
}
  Widget _buildDatePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Target Timeline",
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 8),
       TextFormField(
  controller: targetTimeLineController,
  readOnly: true,
  style: const TextStyle(color: Colors.white),
  decoration: InputDecoration(
    filled: true,
    fillColor: Colors.white24,
    hintText: "Pick a date",
    hintStyle: const TextStyle(color: Colors.white54),
    suffixIcon: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (targetTimeLineController.text.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () {
              setState(() {
                targetTimeLineController.clear();
                validateWithBackend();
              });
            },
          ),
        IconButton(
          icon: const Icon(Icons.calendar_month, color: Colors.white),
          onPressed: () async {
            DateTime? picked = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (picked != null) {
              setState(() {
                targetTimeLineController.text =
                    picked.toString().split(" ")[0];
                validateWithBackend();
              });
            }
          },
        ),
      ],
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: backendErrors["timeline"] != null
          ? const BorderSide(color: Colors.red, width: 1.5)
          : BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  ),
),
if (backendErrors["timeline"] != null) ...[
  const SizedBox(height: 8),
  Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Text(
      backendErrors["timeline"]!,
      style: const TextStyle(color: Colors.red, fontSize: 12),
    ),
  ),
],
const SizedBox(height: 16),
      ],
    );
  }
}