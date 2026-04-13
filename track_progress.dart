import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:nutrifit/notification.dart';

class TrackProgress extends StatefulWidget {
  const TrackProgress({super.key});

  @override
  State<TrackProgress> createState() => _TrackProgressState();
}

class _TrackProgressState extends State<TrackProgress> {
  final NotificationService notificationService = NotificationService();
  bool hasShownProgressReminder = false;
  String selectedPeriod = "weekly";
  bool loading = true;
  int caloriesBurned = 0;
  double workoutHours= 0.0;
double totalHours = 0;
  double progressPercentage = 0.0;
  double proteinPercentage = 0.0;
  double fatsPercentage = 0.0;
  double carbsPercentage = 0.0;
  List<double> weeklyWeightTrend = List.filled(4, 0.0);
  List<double> monthlyWeightTrend = [];
  List<int> monthlyWeightMonthIndices = [];
  List<double> rawWeights =
      []; // raw weight values from Firestore, used to build trend
  List<double> weeklyCalories = List.filled(7, 0.0);
  List<double> weeklyTrend = List.filled(7, 0.0);
  List<double> weeklyTarget = List.filled(7, 0.0);
  List<String> progressStatus = List.filled(7, "on track");
  List<double> weeklyAllEaten = List.filled(7, 0.0);
  List<double> monthlyCalories = [];
  List<double> monthlyTrend = [];
  List<double> monthlyTarget = [];
  List<double> monthlyAllEaten = [];

  @override
  void initState() {
    super.initState();
    notificationService.init();
    _fetchFirestoreAndSendToBackend();
  }

  Map<String, dynamic> _sanitizeForJson(Map<String, dynamic> data) {
    final Map<String, dynamic> sanitized = {};
    data.forEach((key, value) {
      if (value is Timestamp) {
        sanitized[key] = value.toDate().toIso8601String();
      } else if (value is Map) {
        sanitized[key] = _sanitizeForJson(Map<String, dynamic>.from(value));
      } else if (value is List) {
        sanitized[key] = value.map((e) {
          if (e is Timestamp) return e.toDate().toIso8601String();
          if (e is Map) return _sanitizeForJson(Map<String, dynamic>.from(e));
          return e;
        }).toList();
      } else {
        sanitized[key] = value;
      }
    });
    return sanitized;
  }

  Future<void> _fetchFirestoreAndSendToBackend() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => loading = false);
      return;
    }
 workoutHours = 0.0;
    final firestore = FirebaseFirestore.instance;

    try {
      final userDoc = await firestore.collection('users').doc(uid).get();

      Map<String, dynamic> userData = userDoc.exists ? userDoc.data()! : {};

      // ✅ Updated: fetch weightHistory from the array in userData
      List<dynamic> weightArray = userData['weightHistory'] ?? [];
      List<Map<String, dynamic>> weights = weightArray
          .map((w) => Map<String, dynamic>.from(w))
          .toList();

      print(weights);

      final List<double> extractedWeights = weights
          .map((w) => (w['weight'] as num?)?.toDouble() ?? 0.0)
          .where((v) => v > 0)
          .toList();

      final List<double> weeklyTrend4 = List.filled(4, 0.0);

      final recent = extractedWeights.reversed
          .take(4)
          .toList()
          .reversed
          .toList();

      for (int i = 0; i < recent.length; i++) {
        weeklyTrend4[i] = recent[i];
      }

    final Map<int, double> monthWeightMap = {};

for (int i = 0; i < weights.length; i++) {
  final w = weights[i];
  final weight = (w['weight'] as num?)?.toDouble() ?? 0.0;
  if (weight == 0) continue;

  final date = DateTime.parse(w['date'].toString());
  final monthIndex = date.month - 1;
  monthWeightMap[monthIndex] = weight;
}

// ✅ 12 months ka fixed array — jahan data nahi wahan 0.0
final List<double> monthlyTrendData = List.generate(
  12, (i) => monthWeightMap[i] ?? 0.0
);

setState(() {
  rawWeights = extractedWeights;
  weeklyWeightTrend = weeklyTrend4;
  monthlyWeightTrend = monthlyTrendData; // 12 size
});
final exerciseVideosSnap = await firestore
    .collection('users')
    .doc(uid)
    .collection('exercise_videos')
    .get();
    for (var doc in exerciseVideosSnap.docs) {
  final data = doc.data();
  final duration = (data['duration'] ?? 0).toDouble();
  workoutHours += duration;
}
      final mealPlanSnap = await firestore
          .collection('users')
          .doc(uid)
          .collection('meal_plan')
          .doc('current_plan')
          .get();

      final exerciseSnap = await firestore
          .collection('users')
          .doc(uid)
          .collection('exercise_plan')
          .doc('current_plan')
          .get();

      Map<String, dynamic> mealPlan = mealPlanSnap.exists
          ? mealPlanSnap.data()!
          : {};
      Map<String, dynamic> exercisePlan = exerciseSnap.exists
          ? exerciseSnap.data()!
          : {};

      setState(() {
        caloriesBurned = (exercisePlan['caloriesBurned'] ?? 0)
            .toDouble()
            .toInt();
        
      });

      final eatenSnap = await firestore
          .collection('users')
          .doc(uid)
          .collection('eaten_foods')
          .get();

      List<Map<String, dynamic>> eatenFoods = eatenSnap.docs
          .map((doc) => _sanitizeForJson(doc.data()))
          .toList();

      final fullMealPlan = mealPlan['plan'] ?? {};

      await _sendToBackend(
        mealPlan: _sanitizeForJson(fullMealPlan),
        exercisePlan: _sanitizeForJson(exercisePlan),
        eatenFoods: eatenFoods,
        profileUpdatedAt: userData['profile_updated_at'],
        weights: weights,
      );
    } catch (e) {
      debugPrint("Firestore error: $e");
      setState(() => loading = false);
    }
  }

Future<void> _downloadReport() async {
  final pdf = pw.Document();

  final isWeekly = selectedPeriod == "weekly";
  final title = isWeekly ? "Weekly Progress Report" : "Monthly Progress Report";
  final now = DateTime.now();
  final dateStr = "${now.day}/${now.month}/${now.year}";

  // Weight data
  final weightData = isWeekly ? weeklyWeightTrend : monthlyWeightTrend;
  final weightLabels = isWeekly
      ? ["W1", "W2", "W3", "W4"]
      : ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => [

        // ── Title ──────────────────────────────────────────
        pw.Text(title, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text("Generated: $dateStr", style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey)),
        pw.SizedBox(height: 20),
        pw.Divider(),
        pw.SizedBox(height: 16),

        // ── Stat Cards Row ─────────────────────────────────
        pw.Text("Summary", style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 12),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
          children: [
            _pdfStatCard("Burned", "$caloriesBurned kcal", PdfColors.orange),
            _pdfStatCard("Eaten",
              "${(isWeekly ? weeklyAllEaten : monthlyAllEaten).fold(0.0, (a, b) => a + b).toInt()} kcal",
              PdfColors.pink),
            _pdfStatCard("Workout", "${workoutHours.toStringAsFixed(2)} hrs", PdfColors.blue),
          ],
        ),
        pw.SizedBox(height: 24),

        // ── Macros ─────────────────────────────────────────
        pw.Text("Macros Progress", style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 12),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
          children: [
            _pdfMacroCircle("Calories", progressPercentage, PdfColors.green),
            _pdfMacroCircle("Protein", proteinPercentage, PdfColors.blue),
            _pdfMacroCircle("Fats", fatsPercentage, PdfColors.orange),
            _pdfMacroCircle("Carbs", carbsPercentage, PdfColors.teal),
          ],
        ),
        pw.SizedBox(height: 24),

        // ── Calories Table ─────────────────────────────────
        pw.Text(
          isWeekly ? "Daily Calories" : "Weekly Calories",
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.Table.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.green),
          rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          headers: isWeekly
              ? ["Day", "Eaten (kcal)", "Target (kcal)", "% Achieved"]
              : ["Week", "Eaten (kcal)", "Target (kcal)", "% Achieved"],
          data: isWeekly
              ? List.generate(7, (i) {
                  final days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
                  final eaten = i < weeklyAllEaten.length ? weeklyAllEaten[i] : 0.0;
                  final target = i < weeklyTarget.length ? weeklyTarget[i] : 0.0;
                  final pct = target > 0 ? ((eaten / target) * 100).clamp(0.0, 100.0) : 0.0;
                  return [days[i], "${eaten.toInt()}", "${target.toInt()}", "${pct.toStringAsFixed(1)}%"];
                })
              : List.generate(monthlyAllEaten.length, (i) {
                  final eaten = monthlyAllEaten[i];
                  final target = i < monthlyTarget.length ? monthlyTarget[i] : 0.0;
                  final pct = target > 0 ? ((eaten / target) * 100).clamp(0.0, 100.0) : 0.0;
                  return ["Week ${i + 1}", "${eaten.toInt()}", "${target.toInt()}", "${pct.toStringAsFixed(1)}%"];
                }),
        ),
        pw.SizedBox(height: 24),

        // ── Weight Trend Table ─────────────────────────────
        pw.Text("Weight Trend", style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.Table.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.blue),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          headers: [isWeekly ? "Week" : "Month", "Weight (kg)"],
          data: List.generate(weightData.length, (i) {
            final label = i < weightLabels.length ? weightLabels[i] : "${i + 1}";
            final w = weightData[i];
            return [label, w > 0 ? "${w.toStringAsFixed(1)} kg" : "-"];
          }),
        ),
        pw.SizedBox(height: 24),

        // ── Calories Bar Chart (manual bars — pw.Chart has plotting issues) ──
        pw.Text(
          isWeekly ? "Daily Calories Chart" : "Weekly Calories Chart",
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300)),
          child: pw.Column(
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                children: List.generate(
                  isWeekly ? 7 : monthlyAllEaten.length,
                  (i) {
                    final eaten = isWeekly
                        ? (i < weeklyAllEaten.length ? weeklyAllEaten[i] : 0.0)
                        : (i < monthlyAllEaten.length ? monthlyAllEaten[i] : 0.0);
                    final target = isWeekly
                        ? (i < weeklyTarget.length ? weeklyTarget[i] : 0.0)
                        : (i < monthlyTarget.length ? monthlyTarget[i] : 0.0);
                    final pct = target > 0 ? (eaten / target * 100).clamp(0.0, 100.0) : 0.0;
                    final barH = (pct / 100 * 80).clamp(2.0, 80.0);
                    final labels = isWeekly
                        ? ["M", "T", "W", "T", "F", "S", "S"]
                        : List.generate(monthlyAllEaten.length, (i) => "W${i+1}");
                    return pw.Column(
                      mainAxisAlignment: pw.MainAxisAlignment.end,
                      children: [
                        pw.Text("${pct.toStringAsFixed(0)}%", style: const pw.TextStyle(fontSize: 7, color: PdfColors.green)),
                        pw.SizedBox(height: 2),
                        pw.Container(
                          width: 18,
                          height: barH,
                          decoration: pw.BoxDecoration(
                            color: pct >= 80 ? PdfColors.green : pct >= 50 ? PdfColors.orange : PdfColors.red,
                            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(labels[i], style: const pw.TextStyle(fontSize: 8)),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 24),

        // ── Weight Trend Chart (manual bars — pw.Chart has plotting issues) ──
        if (weightData.any((v) => v > 0)) ...[
          pw.Text("Weight Trend Chart", style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300)),
            child: pw.Column(
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                  children: List.generate(weightData.length, (i) {
                    final w = weightData[i];
                    final nonZero = weightData.where((v) => v > 0).toList();
                    final maxW = nonZero.isEmpty ? 1.0 : nonZero.reduce((a, b) => a > b ? a : b);
                    final barH = w > 0 ? (w / maxW * 80).clamp(4.0, 80.0) : 0.0;
                    final label = i < weightLabels.length ? weightLabels[i] : "${i+1}";
                    return pw.Column(
                      mainAxisAlignment: pw.MainAxisAlignment.end,
                      children: [
                        if (w > 0)
                          pw.Text("${w.toStringAsFixed(1)}", style: const pw.TextStyle(fontSize: 7, color: PdfColors.blue)),
                        pw.SizedBox(height: 2),
                        pw.Container(
                          width: 18,
                          height: barH,
                          decoration: pw.BoxDecoration(
                            color: w > 0 ? PdfColors.blue : PdfColors.grey200,
                            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
                      ],
                    );
                  }),
                ),
              ],
            ),
          ),
        ],

        pw.SizedBox(height: 16),
        pw.Divider(),
        pw.SizedBox(height: 8),
        pw.Text(
          "NutriFit App — Auto Generated Report",
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
          textAlign: pw.TextAlign.center,
        ),
      ],
    ),
  );

  await Printing.sharePdf(
    bytes: await pdf.save(),
    filename: isWeekly ? "weekly_report.pdf" : "monthly_report.pdf",
  );
}

pw.Widget _pdfStatCard(String label, String value, PdfColor color) {
  return pw.Container(
    width: 150,
    padding: const pw.EdgeInsets.all(12),
    decoration: pw.BoxDecoration(
      color: color,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(label, style: const pw.TextStyle(color: PdfColors.white, fontSize: 11)),
        pw.SizedBox(height: 6),
        pw.Text(value, style: pw.TextStyle(color: PdfColors.white, fontSize: 14, fontWeight: pw.FontWeight.bold)),
      ],
    ),
  );
}

pw.Widget _pdfMacroCircle(String label, double percentage, PdfColor color) {
  final clamped = percentage.clamp(0.0, 100.0);
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.Container(
        width: 70, height: 70,
        decoration: pw.BoxDecoration(
          shape: pw.BoxShape.circle,
          color: color.shade(80),
        ),
        child: pw.Center(
          child: pw.Text(
            "${clamped.toStringAsFixed(0)}%",
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
          ),
        ),
      ),
      pw.SizedBox(height: 4),
      pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
    ],
  );
}

  Future<void> _sendToBackend({
    required Map<String, dynamic> mealPlan,
    required Map<String, dynamic> exercisePlan,
    required List<Map<String, dynamic>> eatenFoods,
    required dynamic profileUpdatedAt,
    required List<Map<String, dynamic>> weights,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final url = Uri.parse('http://192.168.18.197:8000/track_progress');

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "meal_plan": mealPlan,
          "exercise_plan": exercisePlan,
          "eaten_foods": eatenFoods,
          "period": selectedPeriod,
          "profile_updated_at": profileUpdatedAt?.toString(),
          "weights": weights,
        }),
      );

      if (response.statusCode != 200) {
        debugPrint("Backend returned ${response.statusCode}");
        setState(() => loading = false);
        return;
      }

      final data = jsonDecode(response.body);

      if (data['hasUnmatchedFoods'] == true) {
 if (data['hasUnmatchedFoods'] == true) {
  final foods = (data['unmatchedFoods'] as List).join(", ");

  if (!mounted) return;

  ScaffoldMessenger.of(context).showMaterialBanner(
    MaterialBanner(
      backgroundColor: Colors.orange.shade50,
      content: Text(
        "You are not following meal plan: $foods",
        style: const TextStyle(color: Colors.black),
      ),
      leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
      actions: [
        TextButton(
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
          },
          child: const Text("DISMISS"),
        ),
      ],
    ),
  );
}}

      if ((data['progressPercentage'] ?? 0) < 99 && !hasShownProgressReminder) {
        NotificationService().showNotification(
          "Nutrifit",
          "Stay consistent — follow your meal plan",
          Duration(),
        );
        hasShownProgressReminder = true;
      }
      final monthlyData = data['monthlyData'];
      debugPrint("Backend returned: $data");

      if (uid != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('progress')
            .doc(selectedPeriod)
            .set({
              "data": data,
              "ongoingWeek": data['ongoingWeek'],
              "updatedAt": FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
      }

      final weekdaysOrder = [
        "Monday",
        "Tuesday",
        "Wednesday",
        "Thursday",
        "Friday",
        "Saturday",
        "Sunday",
      ];

      setState(() {
        // Weight trend is already computed from raw Firestore data
        // before the backend call — no need to overwrite from backend response.
        // weeklyWeightTrend and monthlyWeightTrend are already set correctly.
        weeklyCalories = weekdaysOrder.map<double>((day) {
          final val = (data['weeklyCalories']?[day] ?? 0);
          return val is num
              ? val.toDouble()
              : double.tryParse(val.toString()) ?? 0.0;
        }).toList();

        weeklyAllEaten = weekdaysOrder.map<double>((day) {
          final val = (data['weeklyAllEaten']?[day] ?? 0);
          return val is num
              ? val.toDouble()
              : double.tryParse(val.toString()) ?? 0.0;
        }).toList();

        weeklyTarget = weekdaysOrder.map<double>((day) {
          final val = (data['weeklyTarget']?[day] ?? 0);
          return val is num
              ? val.toDouble()
              : double.tryParse(val.toString()) ?? 0.0;
        }).toList();

        weeklyTrend = weekdaysOrder.map<double>((day) {
          final val = (data['weeklyTrend']?[day] ?? 0);
          return val is num
              ? val.toDouble()
              : double.tryParse(val.toString()) ?? 0.0;
        }).toList();

        progressStatus = List<String>.from(
          data['progressStatus'] ?? List.filled(7, "on track"),
        );

        progressPercentage = (data['progressPercentage'] ?? 0).toDouble();
        proteinPercentage = (data['proteinPercentage'] ?? 0).toDouble();
        fatsPercentage = (data['fatsPercentage'] ?? 0).toDouble();
        carbsPercentage = (data['carbsPercentage'] ?? 0).toDouble();

        // --- MONTHLY ---
        // --- MONTHLY ---
        final monthlyData =
            (data['monthlyData'] as Map<String, dynamic>?) ?? {};

        monthlyCalories = monthlyData.values
            .map<double>((w) => (w['calories'] ?? 0).toDouble())
            .toList();

        monthlyTarget = monthlyData.values
            .map<double>((w) => (w['target'] ?? 0).toDouble())
            .toList();

        monthlyAllEaten = monthlyData.values
            .map<double>((w) => (w['allEaten'] ?? 0).toDouble())
            .toList();

        monthlyTrend = monthlyData.values
            .map<double>((w) => (w['trend'] ?? 0).toDouble())
            .toList();
        loading = false;
      });
    } catch (e) {
      debugPrint("Backend error: $e");
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    List<double> weeklyMonthlyCalories = [];
    List<double> weeklyMonthlyTarget = [];

    int daysCount = selectedPeriod == "weekly" ? 7 : 4;
    int chartPoints = selectedPeriod == "weekly" ? 7 : 4;

    if (selectedPeriod == "monthly") {
      daysCount = monthlyCalories.length;

      weeklyMonthlyCalories = monthlyCalories;
      weeklyMonthlyTarget = monthlyTarget;
    }
    final todayIndex = DateTime.now().weekday - 1; // 0=Monday
    final caloriesData = selectedPeriod == "weekly"
        ? weeklyCalories
        : weeklyMonthlyCalories;

    final targetData = selectedPeriod == "weekly"
        ? weeklyTarget
        : weeklyMonthlyTarget;
    List<double> trendData = selectedPeriod == "weekly"
        ? weeklyTrend
        : monthlyTrend;

    List<double> caloriesChartData = selectedPeriod == "weekly"
        ? weeklyAllEaten
        : monthlyAllEaten;
    if (selectedPeriod == "monthly") {
      trendData = monthlyTrend;
      caloriesChartData = monthlyCalories;
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: loading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text(
                      "Fetching your weekly progress...",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                 Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Progress",
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.download, color: Colors.green),
                              tooltip: "Download Report",
                              onPressed: loading ? null : _downloadReport,
                            ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            color: Colors.grey.shade100,
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selectedPeriod,
                              icon: const Icon(Icons.keyboard_arrow_down),
                              items: const [
                                DropdownMenuItem(
                                  value: "weekly",
                                  child: Text("Weekly"),
                                ),
                                DropdownMenuItem(
                                  value: "monthly",
                                  child: Text("Monthly"),
                                ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() {
                                    selectedPeriod = value;
                                    loading = true;
                                  });

                                  _fetchFirestoreAndSendToBackend();
                                }
                              },
                            ),
                          ),
                       ),
                      ],
                    ),
                  ],
                ),
                    const SizedBox(height: 6),
                    Text(
                      selectedPeriod == "weekly"
                          ? "Weekly overview"
                          : "Monthly overview",
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            icon: Icons.local_fire_department,
                            value: "$caloriesBurned kcal",
                            label: "Burned",
                            gradient: const [Colors.orange, Colors.deepOrange],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatCard(
                            icon: Icons.fastfood,
                            value:
                                "${(selectedPeriod == "weekly" ? weeklyAllEaten : monthlyAllEaten).fold(0.0, (a, b) => a + b).toInt()} kcal",
                            label: "Eaten",
                            gradient: const [Colors.pink, Colors.redAccent],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatCard(
                            icon: Icons.timer,
                            value: "${workoutHours.toStringAsFixed(2)} hrs",
                            label: "Workout",
                            gradient: const [
                              Colors.blue,
                              Colors.lightBlueAccent,
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      height: 180,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // 🔥 LEFT - Big Calories Circle
                          Expanded(
                            flex: 2,
                            child: Center(
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  SizedBox(
                                    width: 140,
                                    height: 140,
                                    child: CircularProgressIndicator(
                                      value:
                                          (progressPercentage.clamp(0, 100)) /
                                          100,
                                      strokeWidth: 12,
                                      color: Colors.green,
                                      backgroundColor: Colors.grey.shade300,
                                    ),
                                  ),
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.local_fire_department,
                                        color: Colors.green,
                                        size: 26,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        "${progressPercentage.toStringAsFixed(2)}%",
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const Text(
                                        "Calories",
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(width: 20),

                          // 🥗 RIGHT - Protein, Fats, Carbs
                          Expanded(
                            flex: 1,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _smallMacroCircle(
                                  title: "Protein",
                                  value: proteinPercentage,
                                  color: Colors.blue,
                                  icon: Icons.set_meal,
                                ),

                                _smallMacroCircle(
                                  title: "Fats",
                                  value: fatsPercentage,
                                  color: Colors.orange,
                                  icon: Icons.opacity,
                                ),

                                _smallMacroCircle(
                                  title: "Carbs",
                                  value: carbsPercentage,
                                  color: Colors.green,
                                  icon: Icons.grain,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      selectedPeriod == "weekly"
                          ? "Daily Calories"
                          : "Weekly Calories",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 200,

                      child: BarChart(
                        BarChartData(
                          maxY: 100,
                          gridData: FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,

                                getTitlesWidget: (value, _) {
                                  if (selectedPeriod == "weekly") {
                                    const days = [
                                      'M',
                                      'T',
                                      'W',
                                      'T',
                                      'F',
                                      'S',
                                      'S',
                                    ];
                                    return Text(days[value.toInt()]);
                                  }

                                  // Monthly → show weeks
                                  if (value.toInt() == 0) return Text("W1");
                                  if (value.toInt() == 1) return Text("W2");
                                  if (value.toInt() == 2) return Text("W3");
                                  if (value.toInt() == 3) return Text("W4");

                                  return const SizedBox.shrink();
                                },
                              ),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                interval: 20,
                                reservedSize: 30,
                                getTitlesWidget: (value, _) {
                                  switch (value.toInt()) {
                                    case 0:
                                      return const Text("0%");
                                    case 20:
                                      return const Text("20%");
                                    case 40:
                                      return const Text("40%");
                                    case 60:
                                      return const Text("60%");
                                    case 80:
                                      return const Text("80%");
                                    case 100:
                                      return const Text("100%");
                                    default:
                                      return const SizedBox.shrink();
                                  }
                                },
                              ),
                            ),
                            topTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                          ),
                          barGroups: List.generate(daysCount, (i) {
                            final eaten = i < caloriesData.length
                                ? caloriesData[i]
                                : 0;
                            final target = i < targetData.length
                                ? targetData[i]
                                : 0;

                            final eatenPercent = target > 0
                                ? (eaten / target) * 100.0
                                : 0.0;

                            final displayPercent = eatenPercent > 100.0
                                ? 100.0
                                : eatenPercent;

                            return BarChartGroupData(
                              x: i,
                              barRods: [
                                BarChartRodData(
                                  toY: displayPercent,
                                  width: 14,
                                  color: Colors.green,
                                  borderRadius: BorderRadius.circular(4),
                                  backDrawRodData: BackgroundBarChartRodData(
                                    show: true,
                                    toY: 100,
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                              ],
                            );
                          }),
                          barTouchData: BarTouchData(
                            enabled: true,
                            touchTooltipData: BarTouchTooltipData(
                              getTooltipItem:
                                  (group, groupIndex, rod, rodIndex) {
                                    final eaten =
                                        groupIndex < caloriesData.length
                                        ? caloriesData[groupIndex]
                                        : 0;

                                    final target =
                                        groupIndex < targetData.length
                                        ? targetData[groupIndex]
                                        : 0;
                                    double percent = target > 0
                                        ? (eaten / target) * 100
                                        : 0;
                                    if (percent > 100.0) percent = 100.0;
                                    return BarTooltipItem(
                                      "${percent.toStringAsFixed(2)}%",
                                      const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    );
                                  },
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      "Performance Trend",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 260,
                      child: LineChart(
                        LineChartData(
                          minY: 0.0,
                          gridData: FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            leftTitles: AxisTitles(
                              axisNameWidget: const Text(
                                "Calories",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 50,
                                interval: selectedPeriod == "weekly"
                                    ? 200
                                    : 300,
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              axisNameWidget: const Text(
                                "Days",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              sideTitles: SideTitles(
                                showTitles: true,
                                interval: 1,
                                getTitlesWidget: (value, meta) {
                                  if (selectedPeriod == "weekly") {
                                    const days = [
                                      'M',
                                      'T',
                                      'W',
                                      'T',
                                      'F',
                                      'S',
                                      'S',
                                    ];
                                    return SideTitleWidget(
                                      meta: meta,
                                      child: Text(days[value.toInt()]),
                                    );
                                  }

                                  String text = "";
                                  if (value.toInt() == 0) text = "W1";
                                  if (value.toInt() == 1) text = "W2";
                                  if (value.toInt() == 2) text = "W3";
                                  if (value.toInt() == 3) text = "W4";

                                  if (text.isEmpty)
                                    return const SizedBox.shrink();

                                  return SideTitleWidget(
                                    meta: meta,
                                    child: Text(text),
                                  );
                                },
                              ),
                            ),

                            topTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                          ),
                          lineBarsData: [
                            LineChartBarData(
                              isCurved: true,
                              color: Colors.redAccent,
                              barWidth: 3,
                              dotData: FlDotData(show: true),
                              belowBarData: BarAreaData(
                                show: true,
                                color: Colors.redAccent.withOpacity(0.2),
                              ),
                              spots: List.generate(
                                caloriesChartData.length,
                                (i) =>
                                    FlSpot(i.toDouble(), caloriesChartData[i]),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    const Text(
                      "Weight Trend",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),

                    Builder(
                      builder: (context) {
                        // Pick the correct data list
                        final weightData = selectedPeriod == "weekly"
                            ? weeklyWeightTrend
                            : monthlyWeightTrend;

                        // Filter out zeros so they don't skew the Y axis
                        final nonZero = weightData.where((v) => v > 0).toList();

                        // Dynamic Y axis: 2 kg padding above and below actual values
                        final double minWeight = nonZero.isEmpty
                            ? 0
                            : (nonZero.reduce((a, b) => a < b ? a : b) - 2)
                                  .clamp(0, double.infinity);
                        final double maxWeight = nonZero.isEmpty
                            ? 10
                            : nonZero.reduce((a, b) => a > b ? a : b) + 2;

                        // For monthly bottom labels: show month abbreviation of each week
                        // We use current date to build a rough Week1=this month label
                        final now = DateTime.now();
                        final monthNames = [
                          'Jan',
                          'Feb',
                          'Mar',
                          'Apr',
                          'May',
                          'Jun',
                          'Jul',
                          'Aug',
                          'Sep',
                          'Oct',
                          'Nov',
                          'Dec',
                        ];

                        return SizedBox(
                          height: 260,
                          child: weightData.every((v) => v == 0)
                              ? const Center(
                                  child: Text(
                                    "No weight data available",
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                )
                              : LineChart(
                                  LineChartData(
  minX: 0,   
  maxX: selectedPeriod == "monthly" ? 11 : 3,  
  minY: minWeight,
  maxY: maxWeight,
  gridData: FlGridData(
    show: true,
    drawVerticalLine: false,
  ),
  borderData: FlBorderData(show: false),  titlesData: FlTitlesData(
                                      bottomTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          interval: 1,
                                          getTitlesWidget: (value, meta) {
                                            final idx = value.toInt();
                                            if (selectedPeriod == "weekly") {
                                              // Week 1 – Week 4 labels
                                              if (idx < 0 || idx > 3)
                                                return const SizedBox.shrink();
                                              return SideTitleWidget(
                                                meta: meta,
                                                child: Text(
                                                  "W${idx + 1}",
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              );
                                           } else {
  if (idx < 0 || idx > 11)
    return const SizedBox.shrink();

  const monthNames = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec'
  ];

  return SideTitleWidget(
    meta: meta,
    child: Text(
      monthNames[idx],
      style: const TextStyle(fontSize: 10),
    ),
  );
}
                                          },
                                        ),
                                      ),
                                      leftTitles: AxisTitles(
                                        axisNameWidget: const Text(
                                          "kg",
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          reservedSize: 42,
                                          // Dynamic interval based on range
                                          interval:
                                              ((maxWeight - minWeight) / 4)
                                                  .clamp(0.5, 10),
                                          getTitlesWidget: (value, meta) {
                                            return Text(
                                              value.toStringAsFixed(1),
                                              style: const TextStyle(
                                                fontSize: 10,
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      topTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: false,
                                        ),
                                      ),
                                      rightTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: false,
                                        ),
                                      ),
                                    ),
                                    lineBarsData: [
                                      LineChartBarData(
                                        isCurved:
                                            false, // ✅ straight line = properly connected
                                        isStrokeCapRound:
                                            true, // optional smoother edges
                                        color: Colors.blue,
                                        barWidth: 3,
                                        //dotData: FlDotData(show: true),
                                        belowBarData: BarAreaData(
                                          show: true,
                                          color: Colors.blue.withOpacity(0.2),
                                        ),
              spots: weightData
    .asMap()
    .entries
    .where((e) => e.value > 0) // ✅ 0.0 wale months skip
    .map((e) => FlSpot(e.key.toDouble(), e.value))
    .toList(),
                                      ),
                                    ],
                                    lineTouchData: LineTouchData(
                                      touchTooltipData: LineTouchTooltipData(
                                        getTooltipItems: (spots) =>
                                            spots.map((s) {
                                              return LineTooltipItem(
                                                "${s.y.toStringAsFixed(1)} kg",
                                                const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              );
                                            }).toList(),
                                      ),
                                    ),
                                  ),
                                ),
                        );
                      },
                    ),
                  ],
                ),
                  )
      ),
    );
  }
}

// ================= STAT CARD WIDGET =================
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final List<Color> gradient;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.gradient,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.white,
            child: Icon(icon, size: 18, color: gradient.last),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

Widget _smallMacroCircle({
  required String title,
  required double value,
  required Color color,
  required IconData icon,
}) {
  return Row(
    children: [
      SizedBox(
        width: 50,
        height: 50,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: (value.clamp(0, 100)) / 100,
              strokeWidth: 6,
              color: color,
              backgroundColor: Colors.grey.shade300,
            ),
            Icon(icon, size: 14, color: color),
          ],
        ),
      ),
      const SizedBox(width: 6),

      // 👇 THIS FIXES OVERFLOW
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              "${value.toStringAsFixed(2)}%",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ],
        ),
      ),
    ],
  );
}