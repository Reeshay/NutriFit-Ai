import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:nutrifit/notification.dart';
import 'home_page.dart';
import 'dart:async';

class PersonalInformation extends StatefulWidget {
  const PersonalInformation({super.key});

  @override
  State<PersonalInformation> createState() => _PersonalInfoPageState();
}

class _PersonalInfoPageState extends State<PersonalInformation> {
  final _formKey = GlobalKey<FormState>();
  double? timelineWeeks;
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

  double? bmi;
  double? bmr;
  double? tdee;
  final User? currentUser = FirebaseAuth.instance.currentUser;

  bool isLoading = false;

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
Future<void> checkAndUpdateMealPlan() async {
  final userDoc = await FirebaseFirestore.instance
      .collection("users")
      .doc(currentUser!.uid)
      .get();

  final userData = userDoc.data();

  final response = await http.post(
    Uri.parse("http://192.168.18.197:8000/check_progress"), // change URL
    headers: {"Content-Type": "application/json"},
    body: jsonEncode(userData),
  );

  final data = jsonDecode(response.body);

  if (data["status"] == "updated") {
    await FirebaseFirestore.instance
        .collection("users")
        .doc(currentUser!.uid)
        .collection("meal_plan")
        .doc("current_plan")
        .set({
      "plan": data["meal_plan"],
      "last_updated": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // update timestamp
    await FirebaseFirestore.instance
        .collection("users")
        .doc(currentUser!.uid)
        .update({
      "meal_plan_last_updated": DateTime.now().toIso8601String(),
    });
  }
}
  Future<void> _loadUserInfo() async {
    if (currentUser == null) return;

    final doc = await FirebaseFirestore.instance
        .collection("users")
        .doc(currentUser!.uid)
        .get();

    if (doc.exists) {
      final data = doc.data()!;
      setState(() {
        nameController.text = data["name"] ?? "";
        ageController.text = data["age"] ?? "";
        heightController.text = data["height"] ?? "";
        weightController.text = data["weight"] ?? "";
        targetWeightController.text = data["targetWeight"] ?? "";
        targetTimeLineController.text = data["targetTimeLine"] ?? "";
        gender = data["gender"] ?? "Male";
        activitylevel = data["activitylevel"] ?? "Sedentary";
        fitnessGoal = ["Weight Loss", "Weight Gain", "Maintain"]
                .contains(data["goal"])
            ? data["goal"]
            : "Weight Loss";
        selectedAllergies = List<String>.from(data["allergies"] ?? []);
selectedHealthConditions = List<String>.from(data["healthConditions"] ?? []);
bool isProfileCompleted = data["isProfileCompleted"] ?? false;

if (!isProfileCompleted && !hasShownProfileReminder) {
  notificationService.showNotification(
    "⚠️ Complete Your Profile",
    "Please complete your profile to unlock your full Nutrifit experience.",
    Duration()
  );

  hasShownProfileReminder = true;
}

        fieldLoading.updateAll((key, value) => false);
      });
    } else {
      fieldLoading.updateAll((key, value) => false);
    }
  }

  void validateWithBackend() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 500), () async {
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
          Uri.parse("http://192.168.18.197:8000/profile_setup"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(payload),
        );

        final data = jsonDecode(response.body);

        setState(() {
          backendErrors.clear();
          if (data["status"] == "error") {
            backendErrors.addAll(Map<String, String?>.from(data["errors"] ?? {}));
          } else {
            if ((data["goal_warning"] as String?)?.isNotEmpty ?? false) {
              backendErrors["goal_warning"] = data["goal_warning"];
            }
            if (data["warnings"] != null) {
  backendErrors.addAll(
    Map<String, String?>.from(data["warnings"])
  );
}
          }
        });

        _formKey.currentState?.validate();
      } catch (e) {
        // silently fail
      }
    });
  }
Future<void> _saveUserInfo() async {
  if (!_formKey.currentState!.validate()) return;

  if (backendErrors.isNotEmpty) {
    _showWarningDialog(backendErrors.values.join("\n"));
    return;
  }

  setState(() => isLoading = true);

  try {
    // 🔹 Prepare info for backend
    Map<String, dynamic> info = {
      "uid": currentUser?.uid,
      "name": nameController.text,
      "age": ageController.text,
      "height": heightController.text,
      "weight": weightController.text,
      "targetWeight": targetWeightController.text,
      "gender": gender,
      "activitylevel": activitylevel,
      "goal": fitnessGoal,
      "targetTimeLine": targetTimeLineController.text,
      "allergies": selectedAllergies,
      "healthConditions": selectedHealthConditions,
    };
Future<void> resetEatenFoods() async {
  final foods = await FirebaseFirestore.instance
      .collection("users")
      .doc(currentUser!.uid)
      .collection("eaten_foods")
      .get();

  for (var doc in foods.docs) {
    await doc.reference.delete();
  }
}
Future<void> resetProgress() async {
  final progressDocs = await FirebaseFirestore.instance
      .collection("users")
      .doc(currentUser!.uid)
      .collection("progress")
      .get();

  for (var doc in progressDocs.docs) {
    await doc.reference.delete();
  }
}

  await resetEatenFoods();   
  await resetProgress();
    // 🔹 Call backend once
    final metrics = await _sendToPythonBackend(info);
    if (metrics == null) return;

    // 🔹 Map the meal plan
    Map<String, dynamic> mealPlan =
        Map<String, dynamic>.from(metrics["meal_plan"]);

    const dayKeys = [
      "day_1",
      "day_2",
      "day_3",
      "day_4",
      "day_5",
      "day_6",
      "day_7"
    ];
    const dayNames = [
      "Monday",
      "Tuesday",
      "Wednesday",
      "Thursday",
      "Friday",
      "Saturday",
      "Sunday"
    ];
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
    Map<String, dynamic> mappedPlan = {};
    for (int i = 0; i < dayKeys.length; i++) {
      if (mealPlan.containsKey(dayKeys[i])) {
        mappedPlan[dayNames[i]] = mealPlan[dayKeys[i]];
      }
    }

    // 🔹 Save mapped plan to Firebase
    await FirebaseFirestore.instance
        .collection("users")
        .doc(currentUser!.uid)
        .collection("meal_plan")
        .doc("current_plan")
        .set({
      "plan": mappedPlan,
      "meal_plan_last_updated": DateTime.now().toIso8601String(),
      "timeline_weeks": metrics["timeline_weeks"],
    }, SetOptions(merge: true));

    // 🔹 Update metrics in user document
   await FirebaseFirestore.instance
    .collection("users")
    .doc(currentUser!.uid)
    .set({
  ...info,   
  "weight": weightController.text,
  "weightHistory": FieldValue.arrayUnion([weightEntry]),
  "isProfileCompleted": true,
  "bmi": metrics["bmi"],
  "bmr": metrics["bmr"],
  "tdee": metrics["tdee"],
  "timeline_weeks": metrics["timeline_weeks"],
   "meal_plan_last_updated": DateTime.now().toIso8601String(),
  "profile_updated_at": FieldValue.serverTimestamp(),
}, SetOptions(merge: true));
    // 🔹 Send same mappedPlan back to Python backend
    await _sendToPythonBackend({
      ...info,
      "meal_plan": mappedPlan, // ✅ mappedPlan sent
    });

    // 🔹 Navigate to Home
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => HomePage()),
      (route) => false,
    );
  } finally {
    setState(() => isLoading = false);
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
      Uri.parse("http://192.168.18.197:8000/profile_setup"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(serverData),
    );

    final data = jsonDecode(response.body);
    

    if (data["status"] == "success") {
      setState(() {
        bmi = (data["bmi"] as num).toDouble();
        bmr = (data["bmr"] as num).toDouble();
        tdee = (data["tdee"] as num).toDouble();

        // Extract and store timeline_weeks in the state
        timelineWeeks = (data["timeline_weeks"] as num?)?.toDouble(); // Store the value here
      });

      return {
        "bmi": bmi,
        "bmr": bmr,
        "tdee": tdee,
        "warning": data["warning"] ?? "",
        "goal_warning": data["goal_warning"] ?? "",
        "timeline_weeks": timelineWeeks,  
        "meal_plan": data["meal_plan"] ?? {},
        "plan": data["mappedPlan"],
      };
    } else if (data["status"] == "error") {
      _showWarningDialog(data["message"] ?? "Unknown backend error");
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

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const HomePage()),
          (route) => false,
        );
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Personal Information", style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.black87,
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
                        onPressed: isLoading ? null : _saveUserInfo,
                        child: isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
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
            onChanged: (_) => validateWithBackend(),
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
          "Target Timeline (Optional)",
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 60,
          child: TextFormField(
            controller: targetTimeLineController,
            readOnly: true,
            validator: (_) => backendErrors["timeline"],
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              errorMaxLines: 5,
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
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }
}
