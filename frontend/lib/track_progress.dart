import 'dart:math' as math;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
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
  String selectedPeriod = "daily";
  bool loading = true;
  List<Map<String, dynamic>> _exerciseLogs = [];
bool _logsLoading = false;
  double caloriesBurned = 0.0;
  double workoutHours = 0.0;
  double totalHours = 0;
 
double progressPercentage = 0.0;
double exerciseProgressPercentage = 0.0;
int completedExercises = 0;
int totalPlannedExercises = 0;
  double proteinPercentage = 0.0;
  double fatsPercentage = 0.0;
  double carbsPercentage = 0.0;
  List<double> weeklyWeightTrend = List.filled(4, 0.0);
  List<bool> exerciseCompleted = [];
List<Map<String, dynamic>> todayExercises = [];
List<double> todayExerciseRepsProgress = [];
List<Map<String, dynamic>> perExerciseProgress = [];
  List<double> monthlyWeightTrend = [];
  List<int> monthlyWeightMonthIndices = [];
  List<double> rawWeights = [];
  List<double> weeklyCalories = List.filled(7, 0.0);
  List<double> weeklyTrend = List.filled(7, 0.0);
  List<double> weeklyTarget = List.filled(7, 0.0);
  List<String> progressStatus = List.filled(7, "on track");
  List<double> weeklyAllEaten = List.filled(7, 0.0);
  double totalAllEaten = 0.0;
  List<double> monthlyCalories = [];
  List<double> monthlyTrend = [];
  List<double> monthlyTarget = [];
  List<double> monthlyAllEaten = [];


  List<String> dailyMealsNames = [];
  List<double> dailyMealsEaten = [];
  List<double> dailyMealsTarget = [];
  List<String> dailyMealsStatus = [];
  double dailyTotalEaten = 0.0;
  double dailyTotalTarget = 0.0;
  // Meal plan foods per meal (today's plan from Firestore)
Map<String, List<Map<String, dynamic>>> dailyMealFoods = {};
// Time windows for each meal
static const Map<String, List<int>> _mealHours = {
  'breakfast': [5, 11],
  'lunch':     [11, 16],
  'dinner':    [16, 24],
};
Map<String, Map<String, double>> dailyFoodEatenGrams = {};

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
Future<void> _saveNewMealPlanToFirestore(dynamic newPlan, String updatedAt) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  final firestore = FirebaseFirestore.instance;

  const dayKeys = ["day_1","day_2","day_3","day_4","day_5","day_6","day_7"];
  const dayNames = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"];
  Map<String, dynamic> mappedPlan = {};
  final planMap = Map<String, dynamic>.from(newPlan);
  for (int i = 0; i < dayKeys.length; i++) {
    if (planMap.containsKey(dayKeys[i])) {
      mappedPlan[dayNames[i]] = planMap[dayKeys[i]];
    }
  }

  await firestore
      .collection('users')
      .doc(uid)
      .collection('meal_plan')
      .doc('current_plan')
      .set({
    'plan': mappedPlan,
    'last_updated': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  await firestore.collection('users').doc(uid).update({
    'meal_plan_last_updated': updatedAt,
  });

notificationService.showNotification(
  "New Plan Ready 📋",
  "Your dedication deserves better results — we've crafted a new plan just for you!",
  const Duration(seconds: 2),
);

  debugPrint("Adaptive meal plan Firestore mein save ho gaya");
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

      List<dynamic> weightArray = userData['weightHistory'] ?? [];
      List<Map<String, dynamic>> weights =
          weightArray.map((w) => Map<String, dynamic>.from(w)).toList();

      print(weights);

      final List<double> extractedWeights = weights
          .map((w) => (w['weight'] as num?)?.toDouble() ?? 0.0)
          .where((v) => v > 0)
          .toList();

      final List<double> weeklyTrend4 = List.filled(4, 0.0);

      final recent =
          extractedWeights.reversed.take(4).toList().reversed.toList();

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

      final List<double> monthlyTrendData =
          List.generate(12, (i) => monthWeightMap[i] ?? 0.0);

      if (!mounted) return;
      setState(() {
        rawWeights = extractedWeights;
        weeklyWeightTrend = weeklyTrend4;
        monthlyWeightTrend = monthlyTrendData;
      });
     final exerciseVideosSnap = await firestore
    .collection('users')
    .doc(uid)
    .collection('exercise_videos')
    .get();

final List<Map<String, dynamic>> exerciseVideos = exerciseVideosSnap.docs
    .map((doc) => _sanitizeForJson(doc.data()))
    .toList();
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

      Map<String, dynamic> mealPlan =
          mealPlanSnap.exists ? mealPlanSnap.data()! : {};
      Map<String, dynamic> exercisePlan =
          exerciseSnap.exists ? exerciseSnap.data()! : {};

     if (!mounted) return;
      setState(() {
        caloriesBurned = (userData['calories_burned'] ?? 0).toDouble();
      });

      final eatenSnap = await firestore
          .collection('users')
          .doc(uid)
          .collection('eaten_foods')
          .get();

      List<Map<String, dynamic>> eatenFoods =
          eatenSnap.docs.map((doc) => _sanitizeForJson(doc.data())).toList();

      final fullMealPlan = mealPlan['plan'] ?? {};

      await _sendToBackend(
        mealPlan: _sanitizeForJson(fullMealPlan),
        exercisePlan: _sanitizeForJson(exercisePlan),
        eatenFoods: eatenFoods,
        exerciseVideos: exerciseVideos,  
        profileUpdatedAt: userData['profile_updated_at'],
        weights: weights,
        userData: userData,
      );
      await _fetchTodayMealFoods();
await _fetchTodayExercises();
if(!mounted) return;
    } catch (e) {
      debugPrint("Firestore error: $e");
      
      setState(() => loading = false);
    }
  }

  void _showStackedAlerts(BuildContext context, List<Map<String, dynamic>> alerts) {
    final overlay = Overlay.of(context);
    final List<OverlayEntry> entries = [];
    final double topOffset = MediaQuery.of(context).padding.top + 16.0;

    for (int i = 0; i < alerts.length; i++) {
      final alert = alerts[i];
      late OverlayEntry entry;
      entry = OverlayEntry(
        builder: (ctx) {
          final double entryTop = topOffset + (i * 88.0);
          return Positioned(
            top: entryTop,
            left: 16,
            right: 16,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: alert['color'] as Color,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 8,
                      color: Colors.black.withValues(alpha: 0.25),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      alert['icon'] as IconData,
                      color: Colors.white,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            alert['title'] as String,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            alert['message'] as String,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () {
                        entry.remove();
                        entries.remove(entry);
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
      entries.add(entry);
      overlay.insert(entry);
    }

    Future.delayed(const Duration(seconds: 5), () {
      for (final e in entries.toList()) {
        if (e.mounted) {
          e.remove();
        }
      }
    });
  }

  void _showDownloadModal(BuildContext context) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Download Report",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _DownloadModalOption(
            icon: Icons.picture_as_pdf_rounded,
            label: "Download PDF",
            subtitle: "Formatted report with charts",
            color: Colors.red.shade700,
            bgColor: Colors.red.shade50,
            onTap: () {
              Navigator.pop(context);
              _downloadReport();
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
Future<void> _fetchTodayExercises() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  final daysOrder = [
    'Monday','Tuesday','Wednesday',
    'Thursday','Friday','Saturday','Sunday'
  ];
  final todayName = daysOrder[DateTime.now().weekday - 1];

  try {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('exercise_plan')
        .doc('current_plan')
        .get();

    if (!doc.exists || doc.data()?['plan'] == null) return;

    final plan = Map<String, dynamic>.from(doc.data()!['plan']);

    // plan keys: "Day 1", "Day 2"... ya weekday names
    // weekday index se match karo
    final keys = plan.keys.toList();
    final todayIndex = DateTime.now().weekday - 1;
    if (todayIndex >= keys.length) return;

    final todayKey = keys[todayIndex];
    final exercises = (plan[todayKey] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    // Firestore se completed status fetch karo
    final completedDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('exercise_completed')
        .doc(DateTime.now().toIso8601String().substring(0, 10))
        .get();

    final completedList = completedDoc.exists
        ? List<bool>.from(
            (completedDoc.data()?['completed'] as List? ?? [])
                .map((e) => e as bool))
        : List<bool>.filled(exercises.length, false);

    // length mismatch handle karo
    final safeCompleted = List<bool>.generate(
      exercises.length,
      (i) => i < completedList.length ? completedList[i] : false,
    );

    if (!mounted) return;
    final videosSnap = await FirebaseFirestore.instance
    .collection('users')
    .doc(uid)
    .collection('exercise_videos')
    .get();

final todayDate = DateTime.now();
final todayVideos = videosSnap.docs
    .map((d) => _sanitizeForJson(d.data()))
    .where((v) {
      try {
        final dt = DateTime.parse(v['createdAt'].toString());
        return dt.year == todayDate.year &&
               dt.month == todayDate.month &&
               dt.day == todayDate.day;
      } catch (_) { return false; }
    }).toList();

// Per-exercise reps progress calculate karo
final List<double> repsProgress = exercises.map((ex) {
  final plannedReps = (ex['repetitions'] ?? 0).toDouble();
  final plannedSets = (ex['sets'] ?? 0).toDouble();
  final exName = (ex['exercise_name'] ?? '').toLowerCase().trim();
  final matched = todayVideos.where((v) {
    final vEx = (v['exercise'] ?? '').toString().toLowerCase().trim();
    return vEx == exName || exName.contains(vEx) || vEx.contains(exName) ||
           exName.split(' ').any((w) => vEx.contains(w));
  });
  final doneReps = matched.fold(0.0, (sum, v) => sum + (v['reps'] ?? 0).toDouble());
  
  return plannedReps > 0 ? (doneReps / (plannedReps*plannedSets)).clamp(0.0, 1.0) : 0.0;
}).toList();

setState(() {
  todayExercises = exercises;
  exerciseCompleted = safeCompleted;
  todayExerciseRepsProgress = repsProgress; 
});
  } catch (e) {
    debugPrint("Exercise fetch error: $e");
  }
}
Future<void> _toggleExerciseComplete(int index) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  final updated = List<bool>.from(exerciseCompleted);
  updated[index] = !updated[index];

  setState(() => exerciseCompleted = updated);

  await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('exercise_completed')
      .doc(DateTime.now().toIso8601String().substring(0, 10))
      .set({'completed': updated}, SetOptions(merge: true));
}
void _showExerciseLogsModal(BuildContext context) {
  _fetchExerciseLogs().then((_) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return DraggableScrollableSheet(
            initialChildSize: 0.75,
            maxChildSize: 0.95,
            minChildSize: 0.4,
            builder: (_, scrollCtrl) => Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Handle bar
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.fitness_center, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          "Exercise Logs",
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        Text(
                          "${_exerciseLogs.length} sessions",
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  // List
                  Expanded(
                    child: _logsLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _exerciseLogs.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.videocam_off_rounded,
                                        size: 56, color: Colors.grey.shade300),
                                    const SizedBox(height: 12),
                                    Text("No exercise sessions yet",
                                        style: TextStyle(color: Colors.grey.shade400)),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                controller: scrollCtrl,
                                padding: const EdgeInsets.all(16),
                                itemCount: _exerciseLogs.length,
                                itemBuilder: (_, i) {
                                  final log = _exerciseLogs[i];
                                  final reps = log['reps'] ?? 0;
                                  final dur = (log['duration'] ?? 0.0).toDouble();
                                  final createdAt = log['createdAt'] ?? '';

                                  DateTime? date;
                                  try { date = DateTime.parse(createdAt.toString()); } catch (_) {}

                                  // Exercise ke hisaab se color aur icon
                                  final exerciseMap = {
                                    'bench':    {'icon': Icons.fitness_center, 'color': const Color(0xFF1565C0), 'label': 'Bench Press'},
                                    'squat':    {'icon': Icons.accessibility_new, 'color': const Color(0xFF2E7D32), 'label': 'Squat'},
                                    'deadlift': {'icon': Icons.sports_martial_arts, 'color': const Color(0xFF6A1B9A), 'label': 'Deadlift'},
                                  };
                                  final exerciseField = (log['exercise'] ?? '').toString().toLowerCase();
final key = exerciseMap.containsKey(exerciseField) ? exerciseField : 'bench';
                                  final meta = exerciseMap[key]!;
                                  final color = meta['color'] as Color;
                                  final icon  = meta['icon'] as IconData;
                                  final label = meta['label'] as String;

                                  final durMins = (dur * 60).toStringAsFixed(0);

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.grey.shade200),
                                      boxShadow: [
                                        BoxShadow(
                                          color: color.withOpacity(0.08),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Row(
                                        children: [
                                          // Left icon
                                          Container(
                                            width: 48, height: 48,
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [color.withOpacity(0.15), color.withOpacity(0.05)],
                                              ),
                                              borderRadius: BorderRadius.circular(14),
                                            ),
                                            child: Icon(icon, color: color, size: 22),
                                          ),
                                          const SizedBox(width: 14),
                                          // Middle content
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  label,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold, fontSize: 15),
                                                ),
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    _logChip(Icons.repeat_rounded, "$reps reps", Colors.blue),
                                                    const SizedBox(width: 8),
                                                    _logChip(Icons.timer_outlined, "$durMins min", Colors.orange),
                                                  ],
                                                ),
                                                if (date != null) ...[
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    "${date.day}/${date.month}/${date.year}  ${date.hour.toString().padLeft(2,'0')}:${date.minute.toString().padLeft(2,'0')}",
                                                    style: TextStyle(
                                                      fontSize: 11, color: Colors.grey.shade400),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  });
}

// Helper chip widget
Widget _logChip(IconData icon, String text, Color color) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 3),
      Text(text, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
    ],
  );
}
Future<void> _fetchExerciseLogs() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  setState(() => _logsLoading = true);

  try {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('exercise_videos')
        .orderBy('createdAt', descending: true)
        .get();

    final allLogs = snap.docs.map((d) => _sanitizeForJson(d.data())).toList();

    final now = DateTime.now();
    List<Map<String, dynamic>> filtered;

    if (selectedPeriod == "daily") {
      filtered = allLogs.where((log) {
        try {
          final date = DateTime.parse(log['createdAt'].toString());
          return date.year == now.year &&
                 date.month == now.month &&
                 date.day == now.day;
        } catch (_) {
          return false;
        }
      }).toList();
    } else if (selectedPeriod == "weekly") {
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final weekStartDate = DateTime(weekStart.year, weekStart.month, weekStart.day);
      filtered = allLogs.where((log) {
        try {
          final date = DateTime.parse(log['createdAt'].toString());
          return !date.isBefore(weekStartDate);
        } catch (_) {
          return false;
        }
      }).toList();
    } else {
      // monthly
      filtered = allLogs.where((log) {
        try {
          final date = DateTime.parse(log['createdAt'].toString());
          return date.year == now.year && date.month == now.month;
        } catch (_) {
          return false;
        }
      }).toList();
    }

    setState(() {
      _exerciseLogs = filtered;
      _logsLoading = false;
    });
  } catch (e) {
    setState(() => _logsLoading = false);
    debugPrint("Exercise logs error: $e");
  }
}

  Future<void> _downloadReport() async {
  final pdf = pw.Document();

  final isWeekly = selectedPeriod == "weekly";
  final isDaily = selectedPeriod == "daily";

  final int totalAllEatenInt = (isDaily
          ? dailyTotalEaten
          : isWeekly
              ? weeklyAllEaten.fold(0.0, (a, b) => a + b)
              : monthlyAllEaten.fold(0.0, (a, b) => a + b))
      .toInt();

  final title = isDaily
      ? "Daily Progress Report"
      : isWeekly
          ? "Weekly Progress Report"
          : "Monthly Progress Report";
  final now = DateTime.now();
  final dateStr = "${now.day}/${now.month}/${now.year}";

  final weightData = isWeekly ? weeklyWeightTrend : monthlyWeightTrend;
  final weightLabels = isWeekly
      ? ["W1", "W2", "W3", "W4"]
      : [
          "Jan", "Feb", "Mar", "Apr", "May", "Jun",
          "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
        ];

  // ── Bar chart data ──────────────────────────────────────────────────────
  final int barCount = isDaily
      ? dailyMealsNames.length
      : isWeekly
          ? 7
          : monthlyAllEaten.length;

  final List<String> barLabels = isDaily
      ? dailyMealsNames
          .map((n) => n[0].toUpperCase() + n.substring(1, n.length > 3 ? 4 : n.length))
          .toList()
      : isWeekly
          ? ["M", "T", "W", "T", "F", "S", "S"]
          : List.generate(monthlyAllEaten.length, (i) => "W${i + 1}");

  // ── Performance trend data ──────────────────────────────────────────────
  final List<double> trendData = isDaily
      ? dailyMealsEaten
      : isWeekly
          ? weeklyAllEaten
          : monthlyAllEaten;

  final double trendMax = trendData.isEmpty
      ? 1.0
      : trendData.reduce((a, b) => a > b ? a : b).clamp(1.0, double.infinity);

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => [
        // ── Title ────────────────────────────────────────────────────────
        pw.Text(title,
            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text("Generated: $dateStr",
            style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey)),
        pw.SizedBox(height: 20),
        pw.Divider(),
        pw.SizedBox(height: 16),

        // ── Summary — 3 cards (Burned, Eaten, Workout) ───────────────────
        pw.Text("Summary",
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 12),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
          children: [
            _pdfStatCard("Burned", "${caloriesBurned.toStringAsFixed(0)} kcal", PdfColors.orange),
            _pdfStatCard("Eaten",  "$totalAllEatenInt kcal",                    PdfColors.pink),
            _pdfStatCard("Workout","${workoutHours.toStringAsFixed(2)} hrs",     PdfColors.blue),
          ],
        ),
        pw.SizedBox(height: 28),

        // ── Macros — large Calories left, 3 small right ──────────────────
        pw.Text("Macros Progress",
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 12),
        pw.SizedBox(
          height: 160,
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // Large Calories circle
              pw.Expanded(
                flex: 2,
                child: pw.Center(
                  child: _pdfLargeCalorieCircle(progressPercentage),
                ),
              ),
              pw.SizedBox(width: 20),
              // 3 small macro circles stacked
              pw.Expanded(
                flex: 1,
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                  children: [
                    _pdfSmallMacroCircle("Protein", proteinPercentage, PdfColors.blue),
_pdfSmallMacroCircle("Fats",    fatsPercentage,    PdfColors.orange),
_pdfSmallMacroCircle("Carbs",   carbsPercentage,   PdfColors.green),
                  ],
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 28),

        // ── Daily Meal Cards (only for daily mode) ───────────────────────
        if (isDaily) ...[
          pw.Text("Today's Meals",
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          ...List.generate(dailyMealsNames.length, (i) {
            final mealKey = dailyMealsNames[i];
            final eaten   = i < dailyMealsEaten.length  ? dailyMealsEaten[i]  : 0.0;
            final target  = i < dailyMealsTarget.length ? dailyMealsTarget[i] : 0.0;
            final status  = i < dailyMealsStatus.length ? dailyMealsStatus[i] : 'on track';
            final pct     = target > 0 ? (eaten / target).clamp(0.0, 1.0) : 0.0;
            final pdfColor = status == 'over'
                ? PdfColors.red
                : status == 'under'
                    ? PdfColors.orange
                    : PdfColors.green;
            final barFillW = (pct * 200).clamp(2.0, 200.0);

            return pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 10),
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Header row
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        mealKey[0].toUpperCase() + mealKey.substring(1),
                        style: pw.TextStyle(
                            fontSize: 13, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: pw.BoxDecoration(
                          color: pdfColor.shade(80),
                          borderRadius:
                              const pw.BorderRadius.all(pw.Radius.circular(12)),
                        ),
                        child: pw.Text(status,
                            style: pw.TextStyle(
                                fontSize: 10,
                                color: PdfColors.white,
                                fontWeight: pw.FontWeight.bold)),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 8),
                  // Linear progress bar
                  pw.Stack(
                    children: [
                      pw.Container(
                        width: 200,
                        height: 8,
                        decoration: pw.BoxDecoration(
                          color: PdfColors.grey200,
                          borderRadius:
                              const pw.BorderRadius.all(pw.Radius.circular(4)),
                        ),
                      ),
                      pw.Container(
                        width: barFillW,
                        height: 8,
                        decoration: pw.BoxDecoration(
                          color: pdfColor,
                          borderRadius:
                              const pw.BorderRadius.all(pw.Radius.circular(4)),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 6),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("${eaten.toInt()} kcal eaten",
                          style: const pw.TextStyle(
                              fontSize: 10, color: PdfColors.grey)),
                      pw.Text("Target: ${target.toInt()} kcal",
                          style: const pw.TextStyle(
                              fontSize: 10, color: PdfColors.grey)),
                    ],
                  ),
                ],
              ),
            );
          }),
          pw.SizedBox(height: 8),
          // Total Today green bar
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: PdfColors.green,
              borderRadius:
                  const pw.BorderRadius.all(pw.Radius.circular(10)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("Total Today",
                    style: pw.TextStyle(
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 13)),
                pw.Text(
                    "${dailyTotalEaten.toInt()} / ${dailyTotalTarget.toInt()} kcal",
                    style: pw.TextStyle(
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 13)),
              ],
            ),
          ),
          pw.SizedBox(height: 28),
        ],

        // ── Calories Data Table ──────────────────────────────────────────
        pw.Text(
          isDaily
              ? "Today's Meal Calories"
              : isWeekly
                  ? "Daily Calories"
                  : "Weekly Calories",
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.Table.fromTextArray(
          headerStyle:
              pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.green),
          rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          headers: (isDaily || isWeekly)
              ? ["Meal", "Eaten (kcal)", "Target (kcal)", "% Achieved"]
              : ["Week", "Eaten (kcal)", "Target (kcal)", "% Achieved"],
          data: isDaily
              ? List.generate(dailyMealsNames.length, (i) {
                  final eaten = i < dailyMealsEaten.length ? dailyMealsEaten[i] : 0.0;
                  final target = i < dailyMealsTarget.length ? dailyMealsTarget[i] : 0.0;
                  final pct = target > 0 ? ((eaten / target) * 100).clamp(0.0, 100.0) : 0.0;
                  final name = dailyMealsNames[i];
                  return [
                    name[0].toUpperCase() + name.substring(1),
                    "${eaten.toInt()}",
                    "${target.toInt()}",
                    "${pct.toStringAsFixed(1)}%"
                  ];
                })
              : isWeekly
                  ? List.generate(7, (i) {
                      final days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
                      final eaten = i < weeklyAllEaten.length ? weeklyAllEaten[i] : 0.0;
                      final target = i < weeklyTarget.length ? weeklyTarget[i] : 0.0;
                      final pct = target > 0
                          ? ((eaten / target) * 100).clamp(0.0, 100.0)
                          : 0.0;
                      return [days[i], "${eaten.toInt()}", "${target.toInt()}", "${pct.toStringAsFixed(1)}%"];
                    })
                  : List.generate(monthlyAllEaten.length, (i) {
                      final eaten = monthlyAllEaten[i];
                      final target = i < monthlyTarget.length ? monthlyTarget[i] : 0.0;
                      final pct = target > 0
                          ? ((eaten / target) * 100).clamp(0.0, 100.0)
                          : 0.0;
                      return ["Week ${i + 1}", "${eaten.toInt()}", "${target.toInt()}", "${pct.toStringAsFixed(1)}%"];
                    }),
        ),
        pw.SizedBox(height: 28),

        // ── Calories Bar Chart (with background rod) ─────────────────────
        pw.Text(
          isDaily
              ? "Today's Meal Calories Chart"
              : isWeekly
                  ? "Daily Calories Chart"
                  : "Weekly Calories Chart",
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration:
              pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300)),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
            children: List.generate(barCount, (i) {
              final eaten = isDaily
                  ? (i < dailyMealsEaten.length ? dailyMealsEaten[i] : 0.0)
                  : isWeekly
                      ? (i < weeklyAllEaten.length ? weeklyAllEaten[i] : 0.0)
                      : (i < monthlyAllEaten.length ? monthlyAllEaten[i] : 0.0);
              final target = isDaily
                  ? (i < dailyMealsTarget.length ? dailyMealsTarget[i] : 0.0)
                  : isWeekly
                      ? (i < weeklyTarget.length ? weeklyTarget[i] : 0.0)
                      : (i < monthlyTarget.length ? monthlyTarget[i] : 0.0);
              final pct = target > 0 ? (eaten / target * 100).clamp(0.0, 100.0) : 0.0;
              final barH = (pct / 100 * 80).clamp(0.0, 80.0);
              final barColor = pct >= 80
                  ? PdfColors.green
                  : pct >= 50
                      ? PdfColors.orange
                      : PdfColors.red;
              final label = i < barLabels.length ? barLabels[i] : "${i + 1}";

              return pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Text("${pct.toStringAsFixed(0)}%",
                      style: pw.TextStyle(fontSize: 7, color: barColor)),
                  pw.SizedBox(height: 2),
                  // Background rod + actual bar stacked
                  pw.Stack(
                    alignment: pw.Alignment.bottomCenter,
                    children: [
                      pw.Container(
                        width: 18,
                        height: 80,
                        decoration: pw.BoxDecoration(
                          color: PdfColors.grey200,
                          borderRadius:
                              const pw.BorderRadius.all(pw.Radius.circular(3)),
                        ),
                      ),
                      pw.Container(
                        width: 18,
                        height: barH > 0 ? barH : 2,
                        decoration: pw.BoxDecoration(
                          color: barColor,
                          borderRadius:
                              const pw.BorderRadius.all(pw.Radius.circular(3)),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
                ],
              );
            }),
          ),
        ),
        pw.SizedBox(height: 28),

        
        // ── Weight Trend Table ───────────────────────────────────────────
        pw.Text("Weight Trend",
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.Table.fromTextArray(
          headerStyle:
              pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.blue),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          headers: [isWeekly ? "Week" : "Month", "Weight (kg)"],
          data: List.generate(weightData.length, (i) {
            final label = i < weightLabels.length ? weightLabels[i] : "${i + 1}";
            final w = weightData[i];
            return [label, w > 0 ? "${w.toStringAsFixed(1)} kg" : "-"];
          }),
        ),
        pw.SizedBox(height: 28),

        // ── Weight Trend Chart ───────────────────────────────────────────
        if (weightData.any((v) => v > 0)) ...[
          pw.Text("Weight Trend Chart",
              style:
                  pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300)),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
              children: List.generate(weightData.length, (i) {
                final w = weightData[i];
                final nonZero = weightData.where((v) => v > 0).toList();
                final maxW = nonZero.isEmpty
                    ? 1.0
                    : nonZero.reduce((a, b) => a > b ? a : b);
                final barH = w > 0 ? (w / maxW * 80).clamp(4.0, 80.0) : 0.0;
                final label =
                    i < weightLabels.length ? weightLabels[i] : "${i + 1}";
                return pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    if (w > 0)
                      pw.Text("${w.toStringAsFixed(1)}",
                          style: const pw.TextStyle(
                              fontSize: 7, color: PdfColors.blue)),
                    pw.SizedBox(height: 2),
                    pw.Stack(
                      alignment: pw.Alignment.bottomCenter,
                      children: [
                        pw.Container(
                          width: 18,
                          height: 80,
                          decoration: pw.BoxDecoration(
                            color: PdfColors.grey200,
                            borderRadius: const pw.BorderRadius.all(
                                pw.Radius.circular(3)),
                          ),
                        ),
                        pw.Container(
                          width: 18,
                          height: barH > 0 ? barH : 2,
                          decoration: pw.BoxDecoration(
                            color: w > 0 ? PdfColors.blue : PdfColors.grey200,
                            borderRadius: const pw.BorderRadius.all(
                                pw.Radius.circular(3)),
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
                  ],
                );
              }),
            ),
          ),
        ],

        // ── Exercise Progress ─────────────────────────────────────────────
        pw.SizedBox(height: 28),
        pw.Text("Exercise Progress",
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 12),
        pw.Container(
          padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Center(
                child: _pdfExerciseCircle(exerciseProgressPercentage),
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                exerciseProgressPercentage >= 100
                    ? "💪 All done!"
                    : exerciseProgressPercentage > 0
                        ? "Keep going!"
                        : "Not started",
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: exerciseProgressPercentage >= 100
                      ? PdfColors.green
                      : PdfColors.blue,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                "$completedExercises / $totalPlannedExercises exercises completed",
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
              ),
            ],
          ),
        ),
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
    filename: isDaily
        ? "daily_report.pdf"
        : isWeekly
            ? "weekly_report.pdf"
            : "monthly_report.pdf",
  );
}

// ── New helper: Large Calories circle (dashboard style) ─────────────────────
pw.Widget _pdfLargeCalorieCircle(double percentage) {
  final clamped = percentage.clamp(0.0, 100.0);
  return pw.Stack(
    alignment: pw.Alignment.center,
    children: [
      pw.Container(
        width: 130,
        height: 130,
        decoration: pw.BoxDecoration(
          shape: pw.BoxShape.circle,
          color: PdfColors.grey200,
        ),
      ),
      pw.Container(
        width: 130,
        height: 130,
        decoration: pw.BoxDecoration(
          shape: pw.BoxShape.circle,
          color: PdfColors.green,
        ),
        child: pw.Center(
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text(
                "${clamped.toStringAsFixed(1)}%",
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                "Calories",
                style: const pw.TextStyle(
                  fontSize: 11,
                  color: PdfColors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

// ── Small macro circle — progress ring style matching dashboard ──────────────
pw.Widget _pdfSmallMacroCircle(String label, double percentage, PdfColor color) {
  final clamped = percentage.clamp(0.0, 100.0);
  return pw.Row(
    children: [
      pw.SizedBox(
        width: 50,
        height: 50,
        child: pw.Stack(
          alignment: pw.Alignment.center,
          children: [
            // Background grey full circle
            pw.Container(
              width: 50,
              height: 50,
              decoration: const pw.BoxDecoration(
                shape: pw.BoxShape.circle,
                color: PdfColors.grey300,
              ),
            ),
            // Colored arc progress
            pw.CustomPaint(
              size: const PdfPoint(50, 50),
              painter: (canvas, size) {
                final cx = size.x / 2;
                final cy = size.y / 2;
                final r = size.x / 2;
                final sweepRad = 2 * math.pi * (clamped / 100);
                final startAngle = -math.pi / 2; // top
                final endAngle = startAngle + sweepRad;
                canvas
                  ..setFillColor(color)
                  ..moveTo(cx, cy)
                  ..lineTo(
                    cx + r * math.cos(startAngle),
                    cy + r * math.sin(startAngle),
                  )
                  ..bezierArc(
                    cx + r * math.cos(startAngle),
                    cy + r * math.sin(startAngle),
                    r,
                    r,
                    cx + r * math.cos(endAngle),
                    cy + r * math.sin(endAngle),
                    large: sweepRad > math.pi,
                    sweep: true,
                  )
                  ..lineTo(cx, cy)
                  ..fillPath();
              },
            ),
            // Inner white circle to create ring cutout effect
            pw.Container(
              width: 36,
              height: 36,
              decoration: const pw.BoxDecoration(
                shape: pw.BoxShape.circle,
                color: PdfColors.white,
              ),
            ),
          ],
        ),
      ),
      pw.SizedBox(width: 6),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label,
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
          pw.Text("${clamped.toStringAsFixed(2)}%",
              style: pw.TextStyle(
                  fontSize: 11, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    ],
  );
}
  // ── Exercise round circle for PDF ────────────────────────────────────────────
pw.Widget _pdfExerciseCircle(double percentage) {
  final clamped = percentage.clamp(0.0, 100.0);
  final sweepRad = 2 * math.pi * (clamped / 100);
  final startAngle = -math.pi / 2;
  final endAngle = startAngle + sweepRad;
  final pdfColor = clamped >= 80
      ? PdfColors.green
      : clamped >= 40
          ? PdfColors.orange
          : PdfColors.red;

  return pw.Stack(
    alignment: pw.Alignment.center,
    children: [
      // Grey background circle
      pw.Container(
        width: 120,
        height: 120,
        decoration: const pw.BoxDecoration(
          shape: pw.BoxShape.circle,
          color: PdfColors.grey300,
        ),
      ),
      // Colored arc (pie slice approach)
      pw.CustomPaint(
        size: const PdfPoint(120, 120),
        painter: (canvas, size) {
          final cx = size.x / 2;
          final cy = size.y / 2;
          final r = size.x / 2;
          canvas
            ..setFillColor(pdfColor)
            ..moveTo(cx, cy)
            ..lineTo(
              cx + r * math.cos(startAngle),
              cy + r * math.sin(startAngle),
            )
            ..bezierArc(
              cx + r * math.cos(startAngle),
              cy + r * math.sin(startAngle),
              r,
              r,
              cx + r * math.cos(endAngle),
              cy + r * math.sin(endAngle),
              large: sweepRad > math.pi,
              sweep: true,
            )
            ..lineTo(cx, cy)
            ..fillPath();
        },
      ),
      // Inner white ring cutout
      pw.Container(
        width: 84,
        height: 84,
        decoration: const pw.BoxDecoration(
          shape: pw.BoxShape.circle,
          color: PdfColors.white,
        ),
      ),
      // Center text
      pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            "${clamped.toStringAsFixed(0)}%",
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
              color: pdfColor,
            ),
          ),
          pw.Text(
            "Exercise",
            style: const pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey,
            ),
          ),
        ],
      ),
    ],
  );
}

// ── Small stat row for exercise section ─────────────────────────────────────
pw.Widget _pdfExerciseStatRow(String label, String value, PdfColor color) {
  return pw.Row(
    children: [
      pw.Container(
        width: 10,
        height: 10,
        decoration: pw.BoxDecoration(
          shape: pw.BoxShape.circle,
          color: color,
        ),
      ),
      pw.SizedBox(width: 8),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label,
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey)),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 11, fontWeight: pw.FontWeight.bold, color: color)),
        ],
      ),
    ],
  );
}

  Future<void> _downloadWordReport() async {
  final isWeekly = selectedPeriod == "weekly";
final isDaily  = selectedPeriod == "daily";
 final title = isDaily  ? "Daily Progress Report"
            : isWeekly ? "Weekly Progress Report"
            : "Monthly Progress Report";
  final now = DateTime.now();
  final dateStr = "${now.day}/${now.month}/${now.year}";
  final filename =
      isWeekly ? "weekly_report.docx" : "monthly_report.docx";
 
  // ── Calorie table rows ───────────────────────────────────────────────────
  final calRows = StringBuffer();
  if (isWeekly) {
    final days = [
      "Monday", "Tuesday", "Wednesday", "Thursday",
      "Friday", "Saturday", "Sunday"
    ];
    for (int i = 0; i < 7; i++) {
      final eaten = i < weeklyAllEaten.length ? weeklyAllEaten[i] : 0.0;
      final target = i < weeklyTarget.length ? weeklyTarget[i] : 0.0;
      final pct =
          target > 0 ? ((eaten / target) * 100).clamp(0.0, 100.0) : 0.0;
      final rowBg = i % 2 == 0 ? "F9F9F9" : "FFFFFF";
      calRows.write('''
        <w:tr>
          <w:tc><w:tcPr><w:tcW w:w="2340" w:type="dxa"/><w:shd w:val="clear" w:fill="$rowBg"/></w:tcPr><w:p><w:r><w:t>${days[i]}</w:t></w:r></w:p></w:tc>
          <w:tc><w:tcPr><w:tcW w:w="2340" w:type="dxa"/><w:shd w:val="clear" w:fill="$rowBg"/></w:tcPr><w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:t>${eaten.toInt()}</w:t></w:r></w:p></w:tc>
          <w:tc><w:tcPr><w:tcW w:w="2340" w:type="dxa"/><w:shd w:val="clear" w:fill="$rowBg"/></w:tcPr><w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:t>${target.toInt()}</w:t></w:r></w:p></w:tc>
          <w:tc><w:tcPr><w:tcW w:w="2340" w:type="dxa"/><w:shd w:val="clear" w:fill="$rowBg"/></w:tcPr><w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/><w:color w:val="${pct >= 80 ? "2E7D32" : pct >= 50 ? "E65100" : "C62828"}"/></w:rPr><w:t>${pct.toStringAsFixed(1)}%</w:t></w:r></w:p></w:tc>
        </w:tr>''');
    }
  } else {
    for (int i = 0; i < monthlyAllEaten.length; i++) {
      final eaten = monthlyAllEaten[i];
      final target = i < monthlyTarget.length ? monthlyTarget[i] : 0.0;
      final pct =
          target > 0 ? ((eaten / target) * 100).clamp(0.0, 100.0) : 0.0;
      final rowBg = i % 2 == 0 ? "F9F9F9" : "FFFFFF";
      calRows.write('''
        <w:tr>
          <w:tc><w:tcPr><w:tcW w:w="2340" w:type="dxa"/><w:shd w:val="clear" w:fill="$rowBg"/></w:tcPr><w:p><w:r><w:t>Week ${i + 1}</w:t></w:r></w:p></w:tc>
          <w:tc><w:tcPr><w:tcW w:w="2340" w:type="dxa"/><w:shd w:val="clear" w:fill="$rowBg"/></w:tcPr><w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:t>${eaten.toInt()}</w:t></w:r></w:p></w:tc>
          <w:tc><w:tcPr><w:tcW w:w="2340" w:type="dxa"/><w:shd w:val="clear" w:fill="$rowBg"/></w:tcPr><w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:t>${target.toInt()}</w:t></w:r></w:p></w:tc>
          <w:tc><w:tcPr><w:tcW w:w="2340" w:type="dxa"/><w:shd w:val="clear" w:fill="$rowBg"/></w:tcPr><w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/><w:color w:val="${pct >= 80 ? "2E7D32" : pct >= 50 ? "E65100" : "C62828"}"/></w:rPr><w:t>${pct.toStringAsFixed(1)}%</w:t></w:r></w:p></w:tc>
        </w:tr>''');
    }
  }
 
  // ── Weight table rows ────────────────────────────────────────────────────
  final weightData = isWeekly ? weeklyWeightTrend : monthlyWeightTrend;
  final weightLabels = isWeekly
      ? ["W1", "W2", "W3", "W4"]
      : ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
         "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  final weightRows = StringBuffer();
  for (int i = 0; i < weightData.length; i++) {
    final label = i < weightLabels.length ? weightLabels[i] : "${i + 1}";
    final w = weightData[i];
    final rowBg = i % 2 == 0 ? "F9F9F9" : "FFFFFF";
    weightRows.write('''
      <w:tr>
        <w:tc><w:tcPr><w:tcW w:w="4680" w:type="dxa"/><w:shd w:val="clear" w:fill="$rowBg"/></w:tcPr><w:p><w:r><w:t>$label</w:t></w:r></w:p></w:tc>
        <w:tc><w:tcPr><w:tcW w:w="4680" w:type="dxa"/><w:shd w:val="clear" w:fill="$rowBg"/></w:tcPr><w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr>${w > 0 ? "<w:b/>" : ""}</w:rPr><w:t>${w > 0 ? "${w.toStringAsFixed(1)} kg" : "—"}</w:t></w:r></w:p></w:tc>
      </w:tr>''');
  }
 final totalAllEatenInt = (isDaily  ? dailyTotalEaten
                        : isWeekly ? weeklyAllEaten.fold(0.0, (a,b)=>a+b)
                        : monthlyAllEaten.fold(0.0, (a,b)=>a+b)).toInt();

final planMatchedInt   = (isDaily  ? dailyTotalEaten   
                        : isWeekly ? weeklyCalories.fold(0.0, (a,b)=>a+b)
                        : monthlyCalories.fold(0.0, (a,b)=>a+b)).toInt();
  final totalEaten = (isWeekly ? weeklyAllEaten : monthlyAllEaten)
      .fold(0.0, (a, b) => a + b)
      .toInt();
 
  // ── Build DrawingML bar chart (calories % achieved) ──────────────────────
  // Chart dimensions in EMU (English Metric Units): 1 inch = 914400 EMU
  // Chart width = 6 inches, height = 3 inches
  final chartCx = 5486400; // 6 inches
  final chartCy = 2743200; // 3 inches
 
  final calData = isWeekly ? weeklyAllEaten : monthlyAllEaten;
  final tgtData = isWeekly ? weeklyTarget : monthlyTarget;
  final barLabels = isWeekly
      ? ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
      : List.generate(monthlyAllEaten.length, (i) => "W${i + 1}");
 
  // Build series data points for eaten % of target (clamped 0-100)
  final numBars = calData.length;
  final pctValues = List.generate(numBars, (i) {
    final e = i < calData.length ? calData[i] : 0.0;
    final t = i < tgtData.length ? tgtData[i] : 0.0;
    return t > 0 ? (e / t * 100).clamp(0.0, 100.0) : 0.0;
  });
 
  String _chartNumRef(List<double> vals, String cacheId) {
    final pts = StringBuffer();
    for (int i = 0; i < vals.length; i++) {
      pts.write('<c:pt idx="$i"><c:v>${vals[i].toStringAsFixed(2)}</c:v></c:pt>');
    }
    return '''
      <c:numRef>
        <c:f>Sheet1!A1</c:f>
        <c:numCache>
          <c:formatCode>General</c:formatCode>
          <c:ptCount val="${vals.length}"/>
          $pts
        </c:numCache>
      </c:numRef>''';
  }
 
  String _chartCatRef(List<String> labels) {
    final pts = StringBuffer();
    for (int i = 0; i < labels.length; i++) {
      pts.write('<c:pt idx="$i"><c:v>${labels[i]}</c:v></c:pt>');
    }
    return '''
      <c:strRef>
        <c:f>Sheet1!B1</c:f>
        <c:strCache>
          <c:ptCount val="${labels.length}"/>
          $pts
        </c:strCache>
      </c:strRef>''';
  }
 
  // ── chart1.xml – Calories % Achieved bar chart ───────────────────────────
  final chart1Xml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart"
              xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
              xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <c:chart>
    <c:autoTitleDeleted val="0"/>
    <c:title>
      <c:tx><c:rich><a:bodyPr/><a:lstStyle/>
        <a:p><a:r><a:rPr lang="en-US" b="1"/><a:t>${isWeekly ? "Daily" : "Weekly"} Calorie Achievement (%)</a:t></a:r></a:p>
      </c:rich></c:tx>
      <c:overlay val="0"/>
    </c:title>
    <c:plotArea>
      <c:layout/>
      <c:barChart>
        <c:barDir val="col"/>
        <c:grouping val="clustered"/>
        <c:ser>
          <c:idx val="0"/>
          <c:order val="0"/>
          <c:tx><c:strRef><c:f>Sheet1!C1</c:f>
            <c:strCache><c:ptCount val="1"/><c:pt idx="0"><c:v>% Achieved</c:v></c:pt></c:strCache>
          </c:strRef></c:tx>
          <c:spPr>
            <a:solidFill><a:srgbClr val="4CAF50"/></a:solidFill>
            <a:ln><a:solidFill><a:srgbClr val="2E7D32"/></a:solidFill></a:ln>
          </c:spPr>
          <c:dLbls>
            <c:numFmt formatCode="0.0&quot;%&quot;" sourceLinked="0"/>
            <c:spPr><a:noFill/><a:ln><a:noFill/></a:ln></c:spPr>
            <c:showLegendKey val="0"/>
            <c:showVal val="1"/>
            <c:showCatName val="0"/>
            <c:showSerName val="0"/>
            <c:showPercent val="0"/>
            <c:showBubbleSize val="0"/>
          </c:dLbls>
          <c:cat>${_chartCatRef(barLabels)}</c:cat>
          <c:val>${_chartNumRef(pctValues, "pct")}</c:val>
        </c:ser>
        <c:axId val="1"/>
        <c:axId val="2"/>
      </c:barChart>
      <c:catAx>
        <c:axId val="1"/>
        <c:scaling><c:orientation val="minMax"/></c:scaling>
        <c:delete val="0"/>
        <c:axPos val="b"/>
        <c:crossAx val="2"/>
      </c:catAx>
      <c:valAx>
        <c:axId val="2"/>
        <c:scaling><c:orientation val="minMax"/><c:max val="100"/></c:scaling>
        <c:delete val="0"/>
        <c:axPos val="l"/>
        <c:numFmt formatCode="0&quot;%&quot;" sourceLinked="0"/>
        <c:crossAx val="1"/>
      </c:valAx>
    </c:plotArea>
    <c:legend>
      <c:legendPos val="b"/>
    </c:legend>
    <c:plotVisOnly val="1"/>
  </c:chart>
</c:chartSpace>''';
 
  // ── chart2.xml – Weight trend line chart ─────────────────────────────────
  final wNonZeroIdx =
      weightData.asMap().entries.where((e) => e.value > 0).toList();
  final wIdxList = wNonZeroIdx.map((e) => e.key.toDouble()).toList();
  final wValList = wNonZeroIdx.map((e) => e.value).toList();
  final wLabelList =
      wNonZeroIdx.map((e) => weightLabels[e.key]).toList();
 
  String _lineNumRef(List<double> vals) {
    final pts = StringBuffer();
    for (int i = 0; i < vals.length; i++) {
      pts.write('<c:pt idx="$i"><c:v>${vals[i].toStringAsFixed(1)}</c:v></c:pt>');
    }
    return '''
      <c:numRef>
        <c:f>Sheet1!D1</c:f>
        <c:numCache>
          <c:formatCode>0.0</c:formatCode>
          <c:ptCount val="${vals.length}"/>
          $pts
        </c:numCache>
      </c:numRef>''';
  }
 
  String _lineCatRef(List<String> labels) {
    final pts = StringBuffer();
    for (int i = 0; i < labels.length; i++) {
      pts.write('<c:pt idx="$i"><c:v>${labels[i]}</c:v></c:pt>');
    }
    return '''
      <c:strRef>
        <c:f>Sheet1!E1</c:f>
        <c:strCache>
          <c:ptCount val="${labels.length}"/>
          $pts
        </c:strCache>
      </c:strRef>''';
  }
 
  final chart2Xml = wValList.isEmpty
      ? null
      : '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart"
              xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
              xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <c:chart>
    <c:autoTitleDeleted val="0"/>
    <c:title>
      <c:tx><c:rich><a:bodyPr/><a:lstStyle/>
        <a:p><a:r><a:rPr lang="en-US" b="1"/><a:t>Weight Trend (kg)</a:t></a:r></a:p>
      </c:rich></c:tx>
      <c:overlay val="0"/>
    </c:title>
    <c:plotArea>
      <c:layout/>
      <c:lineChart>
        <c:grouping val="standard"/>
        <c:ser>
          <c:idx val="0"/>
          <c:order val="0"/>
          <c:tx><c:strRef><c:f>Sheet1!F1</c:f>
            <c:strCache><c:ptCount val="1"/><c:pt idx="0"><c:v>Weight (kg)</c:v></c:pt></c:strCache>
          </c:strRef></c:tx>
          <c:spPr>
            <a:ln w="25400"><a:solidFill><a:srgbClr val="2196F3"/></a:solidFill></a:ln>
          </c:spPr>
          <c:marker>
            <c:symbol val="circle"/>
            <c:size val="5"/>
            <c:spPr>
              <a:solidFill><a:srgbClr val="2196F3"/></a:solidFill>
              <a:ln><a:solidFill><a:srgbClr val="1565C0"/></a:solidFill></a:ln>
            </c:spPr>
          </c:marker>
          <c:dLbls>
            <c:numFmt formatCode="0.0" sourceLinked="0"/>
            <c:spPr><a:noFill/><a:ln><a:noFill/></a:ln></c:spPr>
            <c:showLegendKey val="0"/>
            <c:showVal val="1"/>
            <c:showCatName val="0"/>
            <c:showSerName val="0"/>
            <c:showPercent val="0"/>
            <c:showBubbleSize val="0"/>
          </c:dLbls>
          <c:smooth val="0"/>
          <c:cat>${_lineCatRef(wLabelList)}</c:cat>
          <c:val>${_lineNumRef(wValList)}</c:val>
        </c:ser>
        <c:axId val="3"/>
        <c:axId val="4"/>
      </c:lineChart>
      <c:catAx>
        <c:axId val="3"/>
        <c:scaling><c:orientation val="minMax"/></c:scaling>
        <c:delete val="0"/>
        <c:axPos val="b"/>
        <c:crossAx val="4"/>
      </c:catAx>
      <c:valAx>
        <c:axId val="4"/>
        <c:scaling><c:orientation val="minMax"/></c:scaling>
        <c:delete val="0"/>
        <c:axPos val="l"/>
        <c:numFmt formatCode="0.0" sourceLinked="0"/>
        <c:crossAx val="3"/>
      </c:valAx>
    </c:plotArea>
    <c:legend><c:legendPos val="b"/></c:legend>
    <c:plotVisOnly val="1"/>
  </c:chart>
</c:chartSpace>''';
 
  // ── Relationship IDs for charts ───────────────────────────────────────────
  // rId1 = chart1, rId2 = chart2
  final hasWeightChart = chart2Xml != null;
 
  // ── Drawing XML (inline chart embeds into document body) ──────────────────
  String _chartDrawing(String rId, int chartCxLocal, int chartCyLocal,
      int docPrId, String docPrName) {
    return '''
    <w:drawing>
      <wp:inline distT="0" distB="0" distL="0" distR="0"
        xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing">
        <wp:extent cx="$chartCxLocal" cy="$chartCyLocal"/>
        <wp:effectExtent l="0" t="0" r="0" b="0"/>
        <wp:docPr id="$docPrId" name="$docPrName"/>
        <wp:cNvGraphicFramePr>
          <a:graphicFrameLocks xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" noChangeAspect="1"/>
        </wp:cNvGraphicFramePr>
        <a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
          <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart">
            <c:chart xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart"
                     xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
                     r:id="$rId"/>
          </a:graphicData>
        </a:graphic>
      </wp:inline>
    </w:drawing>''';
  }
 
  // ── document.xml ─────────────────────────────────────────────────────────
  final documentXml =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:wpc="http://schemas.microsoft.com/office/word/2010/wordprocessingCanvas"
  xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
  xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
  xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart">
  <w:body>
 
    <!-- Title -->
    <w:p><w:pPr><w:jc w:val="center"/>
      <w:pBdr><w:bottom w:val="single" w:sz="6" w:space="1" w:color="4CAF50"/></w:pBdr>
      <w:spacing w:after="120"/>
    </w:pPr>
      <w:r><w:rPr><w:b/><w:sz w:val="48"/><w:color w:val="2E7D32"/></w:rPr><w:t>$title</w:t></w:r>
    </w:p>
    <w:p><w:pPr><w:jc w:val="center"/></w:pPr>
      <w:r><w:rPr><w:color w:val="757575"/><w:sz w:val="20"/></w:rPr><w:t>Generated: $dateStr</w:t></w:r>
    </w:p>
    <w:p><w:pPr><w:spacing w:after="200"/></w:pPr></w:p>
 
    <!-- Summary -->
    <w:p><w:pPr><w:spacing w:after="120"/></w:pPr>
      <w:r><w:rPr><w:b/><w:sz w:val="28"/><w:color w:val="1A1A1A"/></w:rPr><w:t>Summary</w:t></w:r>
    </w:p>
    <w:tbl>
      <w:tblPr><w:tblW w:w="9360" w:type="dxa"/>
        <w:tblBorders>
          <w:insideH w:val="single" w:sz="4" w:color="EEEEEE"/>
          <w:insideV w:val="single" w:sz="4" w:color="EEEEEE"/>
        </w:tblBorders>
      </w:tblPr>
      <w:tblGrid><w:gridCol w:w="3120"/><w:gridCol w:w="3120"/><w:gridCol w:w="3120"/></w:tblGrid>
      <w:tr>
        <w:tc><w:tcPr><w:tcW w:w="3120" w:type="dxa"/><w:shd w:val="clear" w:fill="FF9800"/>
          <w:tcMar><w:top w:w="100" w:type="dxa"/><w:bottom w:w="100" w:type="dxa"/><w:left w:w="120" w:type="dxa"/><w:right w:w="120" w:type="dxa"/></w:tcMar>
        </w:tcPr>
          <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/><w:color w:val="FFFFFF"/><w:sz w:val="20"/></w:rPr><w:t>🔥 Burned</w:t></w:r></w:p>
          <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/><w:sz w:val="28"/><w:color w:val="FFFFFF"/></w:rPr><w:t>${caloriesBurned.toStringAsFixed(0)} kcal</w:t></w:r></w:p>
        </w:tc>
        <w:tc><w:tcPr><w:tcW w:w="3120" w:type="dxa"/><w:shd w:val="clear" w:fill="E91E63"/>
          <w:tcMar><w:top w:w="100" w:type="dxa"/><w:bottom w:w="100" w:type="dxa"/><w:left w:w="120" w:type="dxa"/><w:right w:w="120" w:type="dxa"/></w:tcMar>
        </w:tcPr>
          <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/><w:color w:val="FFFFFF"/><w:sz w:val="20"/></w:rPr><w:t>🍽 Eaten</w:t></w:r></w:p>
          <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/><w:sz w:val="28"/><w:color w:val="FFFFFF"/></w:rPr><w:t>$totalEaten kcal</w:t></w:r></w:p>
        </w:tc>
        <w:tc><w:tcPr><w:tcW w:w="3120" w:type="dxa"/><w:shd w:val="clear" w:fill="2196F3"/>
          <w:tcMar><w:top w:w="100" w:type="dxa"/><w:bottom w:w="100" w:type="dxa"/><w:left w:w="120" w:type="dxa"/><w:right w:w="120" w:type="dxa"/></w:tcMar>
        </w:tcPr>
          <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/><w:color w:val="FFFFFF"/><w:sz w:val="20"/></w:rPr><w:t>⏱ Workout</w:t></w:r></w:p>
          <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/><w:sz w:val="28"/><w:color w:val="FFFFFF"/></w:rPr><w:t>${workoutHours.toStringAsFixed(2)} hrs</w:t></w:r></w:p>
        </w:tc>
      </w:tr>
    </w:tbl>
 
    <w:p><w:pPr><w:spacing w:after="200"/></w:pPr></w:p>
 
    <!-- Macros -->
    <w:p><w:pPr><w:spacing w:after="120"/></w:pPr>
      <w:r><w:rPr><w:b/><w:sz w:val="28"/><w:color w:val="1A1A1A"/></w:rPr><w:t> Macros Progress</w:t></w:r>
    </w:p>
    <w:tbl>
      <w:tblPr><w:tblW w:w="9360" w:type="dxa"/></w:tblPr>
      <w:tblGrid><w:gridCol w:w="2340"/><w:gridCol w:w="2340"/><w:gridCol w:w="2340"/><w:gridCol w:w="2340"/></w:tblGrid>
      <w:tr>
        <w:tc><w:tcPr><w:tcW w:w="2340" w:type="dxa"/><w:shd w:val="clear" w:fill="4CAF50"/>
          <w:tcMar><w:top w:w="100" w:type="dxa"/><w:bottom w:w="100" w:type="dxa"/><w:left w:w="120" w:type="dxa"/><w:right w:w="120" w:type="dxa"/></w:tcMar>
        </w:tcPr>
          <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:color w:val="FFFFFF"/><w:sz w:val="18"/></w:rPr><w:t>Calories</w:t></w:r></w:p>
          <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/><w:sz w:val="28"/><w:color w:val="FFFFFF"/></w:rPr><w:t>${progressPercentage.toStringAsFixed(1)}%</w:t></w:r></w:p>
        </w:tc>
        <w:tc><w:tcPr><w:tcW w:w="2340" w:type="dxa"/><w:shd w:val="clear" w:fill="2196F3"/>
          <w:tcMar><w:top w:w="100" w:type="dxa"/><w:bottom w:w="100" w:type="dxa"/><w:left w:w="120" w:type="dxa"/><w:right w:w="120" w:type="dxa"/></w:tcMar>
        </w:tcPr>
          <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:color w:val="FFFFFF"/><w:sz w:val="18"/></w:rPr><w:t>Protein</w:t></w:r></w:p>
          <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/><w:sz w:val="28"/><w:color w:val="FFFFFF"/></w:rPr><w:t>${proteinPercentage.toStringAsFixed(1)}%</w:t></w:r></w:p>
        </w:tc>
        <w:tc><w:tcPr><w:tcW w:w="2340" w:type="dxa"/><w:shd w:val="clear" w:fill="FF9800"/>
          <w:tcMar><w:top w:w="100" w:type="dxa"/><w:bottom w:w="100" w:type="dxa"/><w:left w:w="120" w:type="dxa"/><w:right w:w="120" w:type="dxa"/></w:tcMar>
        </w:tcPr>
          <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:color w:val="FFFFFF"/><w:sz w:val="18"/></w:rPr><w:t>Fats</w:t></w:r></w:p>
          <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/><w:sz w:val="28"/><w:color w:val="FFFFFF"/></w:rPr><w:t>${fatsPercentage.toStringAsFixed(1)}%</w:t></w:r></w:p>
        </w:tc>
        <w:tc><w:tcPr><w:tcW w:w="2340" w:type="dxa"/><w:shd w:val="clear" w:fill="009688"/>
          <w:tcMar><w:top w:w="100" w:type="dxa"/><w:bottom w:w="100" w:type="dxa"/><w:left w:w="120" w:type="dxa"/><w:right w:w="120" w:type="dxa"/></w:tcMar>
        </w:tcPr>
          <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:color w:val="FFFFFF"/><w:sz w:val="18"/></w:rPr><w:t>Carbs</w:t></w:r></w:p>
          <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/><w:sz w:val="28"/><w:color w:val="FFFFFF"/></w:rPr><w:t>${carbsPercentage.toStringAsFixed(1)}%</w:t></w:r></w:p>
        </w:tc>
      </w:tr>
    </w:tbl>
 
    <w:p><w:pPr><w:spacing w:after="200"/></w:pPr></w:p>
 
    <!-- Calorie Achievement Bar Chart (DrawingML) -->
    <w:p><w:pPr><w:spacing w:after="120"/></w:pPr>
      <w:r><w:rPr><w:b/><w:sz w:val="28"/><w:color w:val="1A1A1A"/></w:rPr><w:t>📈 ${isWeekly ? "Daily" : "Weekly"} Calorie Achievement Chart</w:t></w:r>
    </w:p>
    <w:p>
      <w:r>
        ${_chartDrawing("rId1", chartCx, chartCy, 1, "CaloriesChart")}
      </w:r>
    </w:p>
 
    <w:p><w:pPr><w:spacing w:after="200"/></w:pPr></w:p>
 
    <!-- Calorie Data Table -->
    <w:p><w:pPr><w:spacing w:after="120"/></w:pPr>
      <w:r><w:rPr><w:b/><w:sz w:val="28"/><w:color w:val="1A1A1A"/></w:rPr><w:t>📋 ${isWeekly ? "Daily Calories" : "Weekly Calories"} — Data Table</w:t></w:r>
    </w:p>
    <w:tbl>
      <w:tblPr><w:tblW w:w="9360" w:type="dxa"/>
        <w:tblBorders>
          <w:top w:val="single" w:sz="4" w:color="CCCCCC"/>
          <w:left w:val="single" w:sz="4" w:color="CCCCCC"/>
          <w:bottom w:val="single" w:sz="4" w:color="CCCCCC"/>
          <w:right w:val="single" w:sz="4" w:color="CCCCCC"/>
          <w:insideH w:val="single" w:sz="4" w:color="CCCCCC"/>
          <w:insideV w:val="single" w:sz="4" w:color="CCCCCC"/>
        </w:tblBorders>
      </w:tblPr>
      <w:tblGrid><w:gridCol w:w="2340"/><w:gridCol w:w="2340"/><w:gridCol w:w="2340"/><w:gridCol w:w="2340"/></w:tblGrid>
      <w:tr>
        <w:tc><w:tcPr><w:tcW w:w="2340" w:type="dxa"/><w:shd w:val="clear" w:fill="4CAF50"/>
          <w:tcMar><w:top w:w="80" w:type="dxa"/><w:bottom w:w="80" w:type="dxa"/><w:left w:w="120" w:type="dxa"/><w:right w:w="120" w:type="dxa"/></w:tcMar>
        </w:tcPr><w:p><w:r><w:rPr><w:b/><w:color w:val="FFFFFF"/></w:rPr><w:t>${isWeekly ? "Day" : "Week"}</w:t></w:r></w:p></w:tc>
        <w:tc><w:tcPr><w:tcW w:w="2340" w:type="dxa"/><w:shd w:val="clear" w:fill="4CAF50"/>
          <w:tcMar><w:top w:w="80" w:type="dxa"/><w:bottom w:w="80" w:type="dxa"/><w:left w:w="120" w:type="dxa"/><w:right w:w="120" w:type="dxa"/></w:tcMar>
        </w:tcPr><w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/><w:color w:val="FFFFFF"/></w:rPr><w:t>Eaten (kcal)</w:t></w:r></w:p></w:tc>
        <w:tc><w:tcPr><w:tcW w:w="2340" w:type="dxa"/><w:shd w:val="clear" w:fill="4CAF50"/>
          <w:tcMar><w:top w:w="80" w:type="dxa"/><w:bottom w:w="80" w:type="dxa"/><w:left w:w="120" w:type="dxa"/><w:right w:w="120" w:type="dxa"/></w:tcMar>
        </w:tcPr><w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/><w:color w:val="FFFFFF"/></w:rPr><w:t>Target (kcal)</w:t></w:r></w:p></w:tc>
        <w:tc><w:tcPr><w:tcW w:w="2340" w:type="dxa"/><w:shd w:val="clear" w:fill="4CAF50"/>
          <w:tcMar><w:top w:w="80" w:type="dxa"/><w:bottom w:w="80" w:type="dxa"/><w:left w:w="120" w:type="dxa"/><w:right w:w="120" w:type="dxa"/></w:tcMar>
        </w:tcPr><w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/><w:color w:val="FFFFFF"/></w:rPr><w:t>% Achieved</w:t></w:r></w:p></w:tc>
      </w:tr>
      $calRows
    </w:tbl>
 
    <w:p><w:pPr><w:spacing w:after="200"/></w:pPr></w:p>
 
    <!-- Weight Chart (DrawingML line chart) -->
    ${hasWeightChart ? '''
    <w:p><w:pPr><w:spacing w:after="120"/></w:pPr>
      <w:r><w:rPr><w:b/><w:sz w:val="28"/><w:color w:val="1A1A1A"/></w:rPr><w:t>⚖️ Weight Trend Chart</w:t></w:r>
    </w:p>
    <w:p>
      <w:r>
        ${_chartDrawing("rId2", chartCx, chartCy, 2, "WeightChart")}
      </w:r>
    </w:p>
    <w:p><w:pPr><w:spacing w:after="200"/></w:pPr></w:p>
    ''' : ''}
 
    <!-- Weight Table -->
    <w:p><w:pPr><w:spacing w:after="120"/></w:pPr>
      <w:r><w:rPr><w:b/><w:sz w:val="28"/><w:color w:val="1A1A1A"/></w:rPr><w:t>⚖️ Weight Trend — Data Table</w:t></w:r>
    </w:p>
    <w:tbl>
      <w:tblPr><w:tblW w:w="9360" w:type="dxa"/>
        <w:tblBorders>
          <w:top w:val="single" w:sz="4" w:color="CCCCCC"/>
          <w:left w:val="single" w:sz="4" w:color="CCCCCC"/>
          <w:bottom w:val="single" w:sz="4" w:color="CCCCCC"/>
          <w:right w:val="single" w:sz="4" w:color="CCCCCC"/>
          <w:insideH w:val="single" w:sz="4" w:color="CCCCCC"/>
          <w:insideV w:val="single" w:sz="4" w:color="CCCCCC"/>
        </w:tblBorders>
      </w:tblPr>
      <w:tblGrid><w:gridCol w:w="4680"/><w:gridCol w:w="4680"/></w:tblGrid>
      <w:tr>
        <w:tc><w:tcPr><w:tcW w:w="4680" w:type="dxa"/><w:shd w:val="clear" w:fill="2196F3"/>
          <w:tcMar><w:top w:w="80" w:type="dxa"/><w:bottom w:w="80" w:type="dxa"/><w:left w:w="120" w:type="dxa"/><w:right w:w="120" w:type="dxa"/></w:tcMar>
        </w:tcPr><w:p><w:r><w:rPr><w:b/><w:color w:val="FFFFFF"/></w:rPr><w:t>${isWeekly ? "Week" : "Month"}</w:t></w:r></w:p></w:tc>
        <w:tc><w:tcPr><w:tcW w:w="4680" w:type="dxa"/><w:shd w:val="clear" w:fill="2196F3"/>
          <w:tcMar><w:top w:w="80" w:type="dxa"/><w:bottom w:w="80" w:type="dxa"/><w:left w:w="120" w:type="dxa"/><w:right w:w="120" w:type="dxa"/></w:tcMar>
        </w:tcPr><w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/><w:color w:val="FFFFFF"/></w:rPr><w:t>Weight (kg)</w:t></w:r></w:p></w:tc>
      </w:tr>
      $weightRows
    </w:tbl>
 
    <w:p><w:pPr><w:spacing w:after="200"/></w:pPr></w:p>
    <w:p><w:pPr>
      <w:pBdr><w:top w:val="single" w:sz="6" w:space="1" w:color="CCCCCC"/></w:pBdr>
    </w:pPr></w:p>
    <w:p><w:pPr><w:jc w:val="center"/></w:pPr>
      <w:r><w:rPr><w:color w:val="9E9E9E"/><w:sz w:val="18"/></w:rPr><w:t>NutriFit App — Auto Generated Report</w:t></w:r>
    </w:p>
 
    <w:sectPr>
      <w:pgSz w:w="12240" w:h="15840"/>
      <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>
    </w:sectPr>
  </w:body>
</w:document>''';
 
  // ── [Content_Types].xml ───────────────────────────────────────────────────
  final contentTypes = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml"
    ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/charts/chart1.xml"
    ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/>
  ${hasWeightChart ? '<Override PartName="/word/charts/chart2.xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/>' : ''}
</Types>''';
 
  // ── _rels/.rels ───────────────────────────────────────────────────────────
  final relsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1"
    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
    Target="word/document.xml"/>
</Relationships>''';
 
  // ── word/_rels/document.xml.rels ─────────────────────────────────────────
  final wordRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1"
    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart"
    Target="charts/chart1.xml"/>
  ${hasWeightChart ? '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" Target="charts/chart2.xml"/>' : ''}
</Relationships>''';
 
  // ── Pack into ZIP ─────────────────────────────────────────────────────────
  final archive = Archive();
 
  void addUtf8(String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }
 
  addUtf8('[Content_Types].xml', contentTypes);
  addUtf8('_rels/.rels', relsXml);
  addUtf8('word/document.xml', documentXml);
  addUtf8('word/_rels/document.xml.rels', wordRelsXml);
  addUtf8('word/charts/chart1.xml', chart1Xml);
  if (hasWeightChart) addUtf8('word/charts/chart2.xml', chart2Xml!);
 
  final bytes = ZipEncoder().encode(archive)!;
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes);
 
  await Share.shareXFiles(
    [
      XFile(file.path,
          mimeType:
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document')
    ],
    subject: title,
  );
}
 
// ─── EXCEL DOWNLOAD (with charts via embedded chart XML) ─────────────────────
Future<void> _downloadExcelReport() async {
  final isWeekly = selectedPeriod == "weekly";
final isDaily  = selectedPeriod == "daily";
  final title = isDaily  ? "Daily Progress Report"
            : isWeekly ? "Weekly Progress Report"
            : "Monthly Progress Report";
  final filename =
      isWeekly ? "weekly_report.xlsx" : "monthly_report.xlsx";
 
  final excel = Excel.createExcel();
 
  // ── Styles ───────────────────────────────────────────────────────────────
  final headerStyle = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
    backgroundColorHex: ExcelColor.fromHexString('#2E7D32'),
    horizontalAlign: HorizontalAlign.Center,
  );
  final subHeaderStyle = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
    backgroundColorHex: ExcelColor.fromHexString('#4CAF50'),
    horizontalAlign: HorizontalAlign.Center,
  );
  final blueHeaderStyle = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
    backgroundColorHex: ExcelColor.fromHexString('#2196F3'),
    horizontalAlign: HorizontalAlign.Center,
  );
  final greenValueStyle = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.fromHexString('#2E7D32'),
    horizontalAlign: HorizontalAlign.Center,
  );
  final orangeValueStyle = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.fromHexString('#E65100'),
    horizontalAlign: HorizontalAlign.Center,
  );
  final redValueStyle = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.fromHexString('#C62828'),
    horizontalAlign: HorizontalAlign.Center,
  );
 
  final now = DateTime.now();
 
  // ── Summary Sheet ─────────────────────────────────────────────────────────
  final summarySheet = excel['Summary'];
  excel.setDefaultSheet('Summary');
 
  summarySheet.cell(CellIndex.indexByString("A1")).value =
      TextCellValue(title);
  summarySheet.cell(CellIndex.indexByString("A1")).cellStyle =
      CellStyle(bold: true, fontSize: 16);
  summarySheet.cell(CellIndex.indexByString("A2")).value = TextCellValue(
      "Generated: ${now.day}/${now.month}/${now.year}");
 
  summarySheet.cell(CellIndex.indexByString("A4")).value =
      TextCellValue("SUMMARY");
  summarySheet.cell(CellIndex.indexByString("A4")).cellStyle = headerStyle;
  summarySheet.cell(CellIndex.indexByString("B4")).value =
      TextCellValue("VALUE");
  summarySheet.cell(CellIndex.indexByString("B4")).cellStyle = headerStyle;
 
  final totalEaten = (isWeekly ? weeklyAllEaten : monthlyAllEaten)
      .fold(0.0, (a, b) => a + b);
 
  summarySheet.cell(CellIndex.indexByString("A5")).value =
      TextCellValue("Calories Burned");
  summarySheet.cell(CellIndex.indexByString("B5")).value =
      DoubleCellValue(caloriesBurned);
  summarySheet.cell(CellIndex.indexByString("A6")).value =
      TextCellValue("Total Eaten (kcal)");
  summarySheet.cell(CellIndex.indexByString("B6")).value =
      DoubleCellValue(totalEaten);
  summarySheet.cell(CellIndex.indexByString("A7")).value =
      TextCellValue("Workout Hours");
  summarySheet.cell(CellIndex.indexByString("B7")).value =
      DoubleCellValue(workoutHours);
 
  summarySheet.cell(CellIndex.indexByString("A9")).value =
      TextCellValue("MACROS");
  summarySheet.cell(CellIndex.indexByString("A9")).cellStyle = headerStyle;
  summarySheet.cell(CellIndex.indexByString("B9")).value =
      TextCellValue("% ACHIEVED");
  summarySheet.cell(CellIndex.indexByString("B9")).cellStyle = headerStyle;
 
  summarySheet.cell(CellIndex.indexByString("A10")).value =
      TextCellValue("Calories");
  summarySheet.cell(CellIndex.indexByString("B10")).value =
      DoubleCellValue(progressPercentage);
  summarySheet.cell(CellIndex.indexByString("A11")).value =
      TextCellValue("Protein");
  summarySheet.cell(CellIndex.indexByString("B11")).value =
      DoubleCellValue(proteinPercentage);
  summarySheet.cell(CellIndex.indexByString("A12")).value =
      TextCellValue("Fats");
  summarySheet.cell(CellIndex.indexByString("B12")).value =
      DoubleCellValue(fatsPercentage);
  summarySheet.cell(CellIndex.indexByString("A13")).value =
      TextCellValue("Carbs");
  summarySheet.cell(CellIndex.indexByString("B13")).value =
      DoubleCellValue(carbsPercentage);
 
  summarySheet.setColumnWidth(0, 25);
  summarySheet.setColumnWidth(1, 20);
 
  // ── Calorie Data Sheet ────────────────────────────────────────────────────
  final calSheetName = isWeekly ? 'Daily Calories' : 'Weekly Calories';
  final calSheet = excel[calSheetName];
  final calHeaders = [
    isWeekly ? "Day" : "Week",
    "Eaten (kcal)",
    "Target (kcal)",
    "% Achieved"
  ];
  for (int c = 0; c < calHeaders.length; c++) {
    calSheet
        .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
        .value = TextCellValue(calHeaders[c]);
    calSheet
        .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
        .cellStyle = subHeaderStyle;
  }
 
  if (isWeekly) {
    final days = [
      "Monday", "Tuesday", "Wednesday", "Thursday",
      "Friday", "Saturday", "Sunday"
    ];
    for (int i = 0; i < 7; i++) {
      final eaten = i < weeklyAllEaten.length ? weeklyAllEaten[i] : 0.0;
      final target = i < weeklyTarget.length ? weeklyTarget[i] : 0.0;
      final pct =
          target > 0 ? ((eaten / target) * 100).clamp(0.0, 100.0) : 0.0;
      final pctStyle = pct >= 80
          ? greenValueStyle
          : pct >= 50
              ? orangeValueStyle
              : redValueStyle;
 
      calSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1))
          .value = TextCellValue(days[i]);
      calSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1))
          .value = DoubleCellValue(eaten);
      calSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: i + 1))
          .value = DoubleCellValue(target);
 
      final pctCell = calSheet.cell(
          CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: i + 1));
      pctCell.value = DoubleCellValue(pct);
      pctCell.cellStyle = pctStyle;
    }
  } else {
    for (int i = 0; i < monthlyAllEaten.length; i++) {
      final eaten = monthlyAllEaten[i];
      final target = i < monthlyTarget.length ? monthlyTarget[i] : 0.0;
      final pct =
          target > 0 ? ((eaten / target) * 100).clamp(0.0, 100.0) : 0.0;
      final pctStyle = pct >= 80
          ? greenValueStyle
          : pct >= 50
              ? orangeValueStyle
              : redValueStyle;
 
      calSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1))
          .value = TextCellValue("Week ${i + 1}");
      calSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1))
          .value = DoubleCellValue(eaten);
      calSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: i + 1))
          .value = DoubleCellValue(target);
 
      final pctCell = calSheet.cell(
          CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: i + 1));
      pctCell.value = DoubleCellValue(pct);
      pctCell.cellStyle = pctStyle;
    }
  }
  for (int c = 0; c < 4; c++) calSheet.setColumnWidth(c, 18);
 
  // ── Weight Sheet ──────────────────────────────────────────────────────────
  final weightSheet = excel['Weight Trend'];
  final weightData = isWeekly ? weeklyWeightTrend : monthlyWeightTrend;
  final weightLabels = isWeekly
      ? ["W1", "W2", "W3", "W4"]
      : ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
         "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
 
  weightSheet
      .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
      .value = TextCellValue(isWeekly ? "Week" : "Month");
  weightSheet
      .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
      .cellStyle = blueHeaderStyle;
  weightSheet
      .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0))
      .value = TextCellValue("Weight (kg)");
  weightSheet
      .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0))
      .cellStyle = blueHeaderStyle;
 
  for (int i = 0; i < weightData.length; i++) {
    final label = i < weightLabels.length ? weightLabels[i] : "${i + 1}";
    final w = weightData[i];
    weightSheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1))
        .value = TextCellValue(label);
    weightSheet
            .cell(
                CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1))
            .value =
        w > 0 ? DoubleCellValue(w) : TextCellValue("—");
  }
  weightSheet.setColumnWidth(0, 15);
  weightSheet.setColumnWidth(1, 15);
 
  excel.delete('Sheet1');
 
  // ── Save base xlsx via excel package ─────────────────────────────────────
  final fileBytes = excel.save();
  if (fileBytes == null) return;
 
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(fileBytes);
 
  // ── Inject DrawingML charts into the xlsx ZIP ─────────────────────────────
  // xlsx is a ZIP: we open it, add chart XMLs + relationships, then re-save.
  final inputBytes = await file.readAsBytes();
  final archive = ZipDecoder().decodeBytes(inputBytes);
 
  // Helper: count existing sheets to get their rId offsets
  // We need sheet indices for our calSheet and weightSheet
  // The excel package usually names them Sheet1.xml, Sheet2.xml etc.
  // We'll find them by iterating the archive.
  final newArchive = Archive();
 
  // Track which sheet files correspond to our named sheets
  // The excel package encodes sheet names in workbook.xml
  // We'll add charts for "Daily/Weekly Calories" (sheet index = calIdx)
  // and "Weight Trend" (weightIdx). We use a simpler approach:
  // inject chart into the FIRST data sheet (calSheet).
 
  // Find the workbook.xml to discover sheet order
  String? workbookXml;
  for (final f in archive) {
    if (f.name == 'xl/workbook.xml') {
      workbookXml = utf8.decode(f.content as List<int>);
      break;
    }
  }
 
  // Parse sheet names → rIds from workbook.xml
  // Pattern: <sheet name="..." sheetId="..." r:id="rId1"/>
  final sheetRIdMap = <String, String>{}; // name → rId
  if (workbookXml != null) {
    final sheetRegex =
        RegExp(r'<sheet[^>]+name="([^"]+)"[^>]+r:id="([^"]+)"');
    for (final m in sheetRegex.allMatches(workbookXml)) {
      sheetRIdMap[m.group(1)!] = m.group(2)!;
    }
  }
 
  final calSheetRId = sheetRIdMap[calSheetName] ?? 'rId1';
  final weightSheetRId = sheetRIdMap['Weight Trend'] ?? 'rId2';
 
  // Build chart XML for calorie % bar chart
  final calData = isWeekly ? weeklyAllEaten : monthlyAllEaten;
  final tgtData = isWeekly ? weeklyTarget : monthlyTarget;
  final barCount = calData.length;
  final barLabels = isWeekly
      ? ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
      : List.generate(barCount, (i) => "W${i + 1}");
 
  String pctPts = '';
  String labelPts = '';
  for (int i = 0; i < barCount; i++) {
    final e = i < calData.length ? calData[i] : 0.0;
    final t = i < tgtData.length ? tgtData[i] : 0.0;
    final p = t > 0 ? (e / t * 100).clamp(0.0, 100.0) : 0.0;
    pctPts += '<c:pt idx="$i"><c:v>${p.toStringAsFixed(2)}</c:v></c:pt>';
    labelPts += '<c:pt idx="$i"><c:v>${barLabels[i]}</c:v></c:pt>';
  }
 
  final calChartXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart"
              xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
              xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <c:chart>
    <c:autoTitleDeleted val="0"/>
    <c:title>
      <c:tx><c:rich><a:bodyPr/><a:lstStyle/>
        <a:p><a:r><a:rPr lang="en-US" b="1"/><a:t>${isWeekly ? "Daily" : "Weekly"} Calorie Achievement (%)</a:t></a:r></a:p>
      </c:rich></c:tx><c:overlay val="0"/>
    </c:title>
    <c:plotArea>
      <c:layout/>
      <c:barChart>
        <c:barDir val="col"/>
        <c:grouping val="clustered"/>
        <c:ser>
          <c:idx val="0"/><c:order val="0"/>
          <c:tx><c:strRef><c:f>Sheet1!A1</c:f>
            <c:strCache><c:ptCount val="1"/><c:pt idx="0"><c:v>% Achieved</c:v></c:pt></c:strCache>
          </c:strRef></c:tx>
          <c:spPr>
            <a:solidFill><a:srgbClr val="4CAF50"/></a:solidFill>
            <a:ln><a:solidFill><a:srgbClr val="2E7D32"/></a:solidFill></a:ln>
          </c:spPr>
          <c:dLbls>
            <c:numFmt formatCode="0.0&quot;%&quot;" sourceLinked="0"/>
            <c:spPr><a:noFill/><a:ln><a:noFill/></a:ln></c:spPr>
            <c:showLegendKey val="0"/><c:showVal val="1"/>
            <c:showCatName val="0"/><c:showSerName val="0"/>
            <c:showPercent val="0"/><c:showBubbleSize val="0"/>
          </c:dLbls>
          <c:cat>
            <c:strRef><c:f>'$calSheetName'!A2:A${barCount + 1}</c:f>
              <c:strCache><c:ptCount val="$barCount"/>$labelPts</c:strCache>
            </c:strRef>
          </c:cat>
          <c:val>
            <c:numRef><c:f>'$calSheetName'!D2:D${barCount + 1}</c:f>
              <c:numCache><c:formatCode>General</c:formatCode>
                <c:ptCount val="$barCount"/>$pctPts
              </c:numCache>
            </c:numRef>
          </c:val>
        </c:ser>
        <c:axId val="1"/><c:axId val="2"/>
      </c:barChart>
      <c:catAx>
        <c:axId val="1"/>
        <c:scaling><c:orientation val="minMax"/></c:scaling>
        <c:delete val="0"/><c:axPos val="b"/><c:crossAx val="2"/>
      </c:catAx>
      <c:valAx>
        <c:axId val="2"/>
        <c:scaling><c:orientation val="minMax"/><c:max val="100"/></c:scaling>
        <c:delete val="0"/><c:axPos val="l"/>
        <c:numFmt formatCode="0&quot;%&quot;" sourceLinked="0"/>
        <c:crossAx val="1"/>
      </c:valAx>
    </c:plotArea>
    <c:legend><c:legendPos val="b"/></c:legend>
    <c:plotVisOnly val="1"/>
  </c:chart>
</c:chartSpace>''';
 
  // Weight line chart
  final wNonZero =
      weightData.asMap().entries.where((e) => e.value > 0).toList();
  final wPts = wNonZero
      .map((e) =>
          '<c:pt idx="${e.key}"><c:v>${e.value.toStringAsFixed(1)}</c:v></c:pt>')
      .join('');
  final wCatPts = wNonZero
      .map((e) =>
          '<c:pt idx="${e.key}"><c:v>${weightLabels[e.key]}</c:v></c:pt>')
      .join('');
  final wCount = weightData.length;
 
  final weightChartXml = wNonZero.isEmpty
      ? null
      : '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart"
              xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
              xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <c:chart>
    <c:autoTitleDeleted val="0"/>
    <c:title>
      <c:tx><c:rich><a:bodyPr/><a:lstStyle/>
        <a:p><a:r><a:rPr lang="en-US" b="1"/><a:t>Weight Trend (kg)</a:t></a:r></a:p>
      </c:rich></c:tx><c:overlay val="0"/>
    </c:title>
    <c:plotArea>
      <c:layout/>
      <c:lineChart>
        <c:grouping val="standard"/>
        <c:ser>
          <c:idx val="0"/><c:order val="0"/>
          <c:tx><c:strRef><c:f>Sheet1!A1</c:f>
            <c:strCache><c:ptCount val="1"/><c:pt idx="0"><c:v>Weight (kg)</c:v></c:pt></c:strCache>
          </c:strRef></c:tx>
          <c:spPr>
            <a:ln w="25400"><a:solidFill><a:srgbClr val="2196F3"/></a:solidFill></a:ln>
          </c:spPr>
          <c:marker>
            <c:symbol val="circle"/><c:size val="5"/>
            <c:spPr>
              <a:solidFill><a:srgbClr val="2196F3"/></a:solidFill>
              <a:ln><a:solidFill><a:srgbClr val="1565C0"/></a:solidFill></a:ln>
            </c:spPr>
          </c:marker>
          <c:dLbls>
            <c:numFmt formatCode="0.0" sourceLinked="0"/>
            <c:spPr><a:noFill/><a:ln><a:noFill/></a:ln></c:spPr>
            <c:showLegendKey val="0"/><c:showVal val="1"/>
            <c:showCatName val="0"/><c:showSerName val="0"/>
            <c:showPercent val="0"/><c:showBubbleSize val="0"/>
          </c:dLbls>
          <c:smooth val="0"/>
          <c:cat>
            <c:strRef><c:f>'Weight Trend'!A2:A${wCount + 1}</c:f>
              <c:strCache><c:ptCount val="$wCount"/>$wCatPts</c:strCache>
            </c:strRef>
          </c:cat>
          <c:val>
            <c:numRef><c:f>'Weight Trend'!B2:B${wCount + 1}</c:f>
              <c:numCache><c:formatCode>0.0</c:formatCode>
                <c:ptCount val="$wCount"/>$wPts
              </c:numCache>
            </c:numRef>
          </c:val>
        </c:ser>
        <c:axId val="3"/><c:axId val="4"/>
      </c:lineChart>
      <c:catAx>
        <c:axId val="3"/>
        <c:scaling><c:orientation val="minMax"/></c:scaling>
        <c:delete val="0"/><c:axPos val="b"/><c:crossAx val="4"/>
      </c:catAx>
      <c:valAx>
        <c:axId val="4"/>
        <c:scaling><c:orientation val="minMax"/></c:scaling>
        <c:delete val="0"/><c:axPos val="l"/>
        <c:numFmt formatCode="0.0" sourceLinked="0"/>
        <c:crossAx val="3"/>
      </c:valAx>
    </c:plotArea>
    <c:legend><c:legendPos val="b"/></c:legend>
    <c:plotVisOnly val="1"/>
  </c:chart>
</c:chartSpace>''';
 
  // ── Now we need to inject charts into the xlsx archive ───────────────────
  // xlsx = ZIP of: xl/workbook.xml, xl/worksheets/sheet*.xml,
  //                xl/charts/chart*.xml, xl/drawings/drawing*.xml,
  //                xl/worksheets/_rels/sheet*.xml.rels, etc.
  //
  // We find the sheet number for our calorie sheet and weight sheet,
  // then add drawings + chart references.
 
  // Discover sheet number mapping from workbook.xml
  // sheetId in workbook.xml matches the file number xl/worksheets/sheetN.xml
  final sheetIdMap = <String, String>{}; // name → sheetId
  final sheetFileMap = <String, String>{}; // sheetId → worksheet filename rId
  if (workbookXml != null) {
    final sheetRegex2 =
        RegExp(r'<sheet[^>]+name="([^"]+)"[^>]+sheetId="([^"]+)"');
    for (final m in sheetRegex2.allMatches(workbookXml)) {
      sheetIdMap[m.group(1)!] = m.group(2)!;
    }
  }
 
  // Find workbook rels to map rId → sheet file
  String? wbRels;
  for (final f in archive) {
    if (f.name == 'xl/_rels/workbook.xml.rels') {
      wbRels = utf8.decode(f.content as List<int>);
      break;
    }
  }
  final rIdToTarget = <String, String>{}; // rId → worksheets/sheetN.xml
  if (wbRels != null) {
    final relRegex =
        RegExp(r'Id="([^"]+)"[^>]+Target="([^"]+)"');
    for (final m in relRegex.allMatches(wbRels)) {
      rIdToTarget[m.group(1)!] = m.group(2)!;
    }
  }
 
  // Find actual sheet file paths
  String? calSheetFile; // e.g. "worksheets/sheet2.xml"
  String? weightSheetFile;
  final calRId = sheetRIdMap[calSheetName];
  final wRId = sheetRIdMap['Weight Trend'];
  if (calRId != null) calSheetFile = rIdToTarget[calRId];
  if (wRId != null) weightSheetFile = rIdToTarget[wRId];
 
  // Extract sheet number from filename: "worksheets/sheet2.xml" → "2"
  String _sheetNum(String? path) {
    if (path == null) return '1';
    final m = RegExp(r'sheet(\d+)\.xml').firstMatch(path);
    return m?.group(1) ?? '1';
  }
 
  final calSheetNum = _sheetNum(calSheetFile);
  final weightSheetNum = _sheetNum(weightSheetFile);
 
  // Chart dimensions: 5486400 EMU wide × 3200400 EMU tall (≈6×3.5 in)
  final emCx = 5486400;
  final emCy = 3200400;
 
  String _drawingXml(String chartRId) => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing"
          xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
          xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart"
          xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <xdr:absoluteAnchor>
    <xdr:pos x="0" y="0"/>
    <xdr:ext cx="$emCx" cy="$emCy"/>
    <xdr:graphicFrame macro="">
      <xdr:nvGraphicFramePr>
        <xdr:cNvPr id="2" name="Chart 1"/>
        <xdr:cNvGraphicFramePr/>
      </xdr:nvGraphicFramePr>
      <xdr:xfrm><a:off x="0" y="0"/><a:ext cx="$emCx" cy="$emCy"/></xdr:xfrm>
      <a:graphic>
        <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart">
          <c:chart r:id="$chartRId" xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart"
                   xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"/>
        </a:graphicData>
      </a:graphic>
    </xdr:graphicFrame>
    <xdr:clientData/>
  </xdr:absoluteAnchor>
</xdr:wsDr>''';
 
  String _drawingRels(String chartFile) =>
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1"
    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart"
    Target="../charts/$chartFile"/>
</Relationships>''';
 
  String _sheetDrawingRel(String drawingFile) =>
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId100"
    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing"
    Target="../drawings/$drawingFile"/>
</Relationships>''';
 
  // Copy all original files, patching worksheets to add <drawing> tag
  for (final f in archive) {
    final name = f.name;
    final content = f.content as List<int>;
    String? patched;
 
    // Patch calorie sheet XML to reference drawing1
    if (calSheetFile != null && name == 'xl/$calSheetFile') {
      final xml = utf8.decode(content);
      if (!xml.contains('<drawing')) {
        patched = xml.replaceFirst(
            '</worksheet>',
            '<drawing r:id="rId100"/></worksheet>');
      }
    }
 
    // Patch weight sheet XML to reference drawing2
    if (weightChartXml != null &&
        weightSheetFile != null &&
        name == 'xl/$weightSheetFile') {
      final xml = utf8.decode(content);
      if (!xml.contains('<drawing')) {
        patched = xml.replaceFirst(
            '</worksheet>',
            '<drawing r:id="rId100"/></worksheet>');
      }
    }
 
    // Patch [Content_Types].xml to add chart + drawing content types
    if (name == '[Content_Types].xml') {
      var xml = utf8.decode(content);
      if (!xml.contains('drawingml.chart')) {
        xml = xml.replaceFirst(
          '</Types>',
          '<Override PartName="/xl/charts/chart1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/>'
          '${weightChartXml != null ? '<Override PartName="/xl/charts/chart2.xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/>' : ''}'
          '<Override PartName="/xl/drawings/drawing1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>'
          '${weightChartXml != null ? '<Override PartName="/xl/drawings/drawing2.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>' : ''}'
          '</Types>',
        );
      }
      patched = xml;
    }
 
    if (patched != null) {
      final b = utf8.encode(patched);
      newArchive.addFile(ArchiveFile(name, b.length, b));
    } else {
      newArchive.addFile(ArchiveFile(name, content.length, content));
    }
  }
 
  void addUtf8File(String path, String content) {
    final b = utf8.encode(content);
    newArchive.addFile(ArchiveFile(path, b.length, b));
  }
 
  // Add chart files
  addUtf8File('xl/charts/chart1.xml', calChartXml);
  if (weightChartXml != null) {
    addUtf8File('xl/charts/chart2.xml', weightChartXml);
  }
 
  // Add drawing files
  addUtf8File('xl/drawings/drawing1.xml', _drawingXml('rId1'));
  if (weightChartXml != null) {
    addUtf8File('xl/drawings/drawing2.xml', _drawingXml('rId1'));
  }
 
  // Add drawing rels
  addUtf8File(
      'xl/drawings/_rels/drawing1.xml.rels', _drawingRels('chart1.xml'));
  if (weightChartXml != null) {
    addUtf8File(
        'xl/drawings/_rels/drawing2.xml.rels', _drawingRels('chart2.xml'));
  }
 
  // Add/merge worksheet _rels for drawing reference
  // Check if _rels for these sheets already exist
  bool calRelsExists = archive.any(
      (f) => f.name == 'xl/worksheets/_rels/sheet$calSheetNum.xml.rels');
  bool wRelsExists = weightChartXml != null &&
      archive.any((f) =>
          f.name ==
          'xl/worksheets/_rels/sheet$weightSheetNum.xml.rels');
 
  if (!calRelsExists) {
    addUtf8File(
      'xl/worksheets/_rels/sheet$calSheetNum.xml.rels',
      _sheetDrawingRel('drawing1.xml'),
    );
  } else {
    // Merge: find existing rels and append drawing relationship
    for (final f in archive) {
      if (f.name ==
          'xl/worksheets/_rels/sheet$calSheetNum.xml.rels') {
        var xml = utf8.decode(f.content as List<int>);
        if (!xml.contains('drawing1.xml')) {
          xml = xml.replaceFirst(
            '</Relationships>',
            '<Relationship Id="rId100" '
                'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" '
                'Target="../drawings/drawing1.xml"/></Relationships>',
          );
          final b = utf8.encode(xml);
          // Replace file in newArchive
          newArchive.files.removeWhere((af) =>
              af.name ==
              'xl/worksheets/_rels/sheet$calSheetNum.xml.rels');
          newArchive.addFile(ArchiveFile(f.name, b.length, b));
        }
        break;
      }
    }
  }
 
  if (weightChartXml != null && !wRelsExists) {
    addUtf8File(
      'xl/worksheets/_rels/sheet$weightSheetNum.xml.rels',
      _sheetDrawingRel('drawing2.xml'),
    );
  } else if (weightChartXml != null) {
    for (final f in archive) {
      if (f.name ==
          'xl/worksheets/_rels/sheet$weightSheetNum.xml.rels') {
        var xml = utf8.decode(f.content as List<int>);
        if (!xml.contains('drawing2.xml')) {
          xml = xml.replaceFirst(
            '</Relationships>',
            '<Relationship Id="rId100" '
                'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" '
                'Target="../drawings/drawing2.xml"/></Relationships>',
          );
          final b = utf8.encode(xml);
          newArchive.files.removeWhere((af) =>
              af.name ==
              'xl/worksheets/_rels/sheet$weightSheetNum.xml.rels');
          newArchive.addFile(ArchiveFile(f.name, b.length, b));
        }
        break;
      }
    }
  }
 
  // Re-encode ZIP and save
  final newBytes = ZipEncoder().encode(newArchive)!;
  await file.writeAsBytes(newBytes);
 
  await Share.shareXFiles(
    [
      XFile(file.path,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
    ],
    subject: title,
  );
}
  pw.Widget _pdfStatCard(
      String label, String value, PdfColor color) {
    return pw.Container(
      width: 150,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: color,
        borderRadius:
            const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(label,
              style: const pw.TextStyle(
                  color: PdfColors.white, fontSize: 11)),
          pw.SizedBox(height: 6),
          pw.Text(value,
              style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  pw.Widget _pdfMacroCircle(
      String label, double percentage, PdfColor color) {
    final clamped = percentage.clamp(0.0, 100.0);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(
          width: 70,
          height: 70,
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
Future<void> _fetchTodayMealFoods() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  final daysOrder = [
    'Monday','Tuesday','Wednesday',
    'Thursday','Friday','Saturday','Sunday'
  ];
  final todayName = daysOrder[DateTime.now().weekday - 1];

  try {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('meal_plan')
        .doc('current_plan')
        .get(GetOptions(source: Source.cache))
    .catchError((_) => FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('meal_plan')
        .doc('current_plan')
        .get(GetOptions(source: Source.server)));

    if (!doc.exists || doc.data()?['plan'] == null) return;

    final plan = Map<String, dynamic>.from(doc.data()!['plan']);
    final todayData = plan[todayName];
    if (todayData == null) return;

    final meals = Map<String, dynamic>.from(todayData['meals'] ?? {});
    final Map<String, List<Map<String, dynamic>>> foods = {};

    for (final mealKey in ['breakfast', 'lunch', 'dinner']) {
      if (meals.containsKey(mealKey)) {
        final items = (meals[mealKey]['items'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        foods[mealKey] = items;
      }
    }

    // Ab eaten_foods se aaj ka data match karo
final today = DateTime.now();
final todayStr =
    "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

final today2 = DateTime.now();
const mealWindows = {
  'breakfast': [5, 11],
  'lunch':     [11, 16],
  'dinner':    [16, 24],
};

final eatenSnap = await FirebaseFirestore.instance
    .collection('users')
    .doc(uid)
    .collection('eaten_foods')
    .where('consumed', isEqualTo: true)
    .get();

final Map<String, Map<String, double>> eatenGramsMap = {};

for (final doc in eatenSnap.docs) {
  final data = doc.data();

  // created_at se date nikalo
  DateTime? foodDate;
  final createdAt = data['created_at'];
  if (createdAt is Timestamp) {
    foodDate = createdAt.toDate();
  } else if (createdAt is String) {
    foodDate = DateTime.tryParse(createdAt);
  }
  if (foodDate == null) continue;

  // Sirf aaj ka
  if (foodDate.year  != today2.year  ||
      foodDate.month != today2.month ||
      foodDate.day   != today2.day) continue;

  final hour     = foodDate.hour;
  final foodName = (data['food_name'] ?? '').toString().toLowerCase().trim();
 final grams = (data['quantity_g'] ?? data['grams'] ?? 0).toDouble();

  // Hour se meal type determine karo
  String mealKey = '';
  mealWindows.forEach((meal, window) {
    if (hour >= window[0] && hour < window[1]) mealKey = meal;
  });
  if (mealKey.isEmpty) continue;

  eatenGramsMap.putIfAbsent(mealKey, () => {});
  eatenGramsMap[mealKey]![foodName] =
      (eatenGramsMap[mealKey]![foodName] ?? 0) + grams;
}

if (mounted) {
  setState(() {
    dailyMealFoods      = foods;
    dailyFoodEatenGrams = eatenGramsMap;
  });
}
  } catch (e) {
    debugPrint("Meal foods fetch error: $e");
  }
}
  Future<void> _sendToBackend({
  required Map<String, dynamic> mealPlan,
  required Map<String, dynamic> exercisePlan,
  required List<Map<String, dynamic>> eatenFoods,
  required List<Map<String, dynamic>> exerciseVideos,
  required dynamic profileUpdatedAt,
  required List<Map<String, dynamic>> weights,
  required Map<String, dynamic> userData, 
})
   async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final url =
        Uri.parse('https://nutrifit-backend-production-1761.up.railway.app/track_progress');
        //Uri.parse('http://192.168.18.197:8000/track_progress');

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
  "meal_plan": mealPlan,
  "exercise_plan": exercisePlan,
  "eaten_foods": eatenFoods,
  "exercise_videos": exerciseVideos,
  "period": selectedPeriod,
  "profile_updated_at": profileUpdatedAt?.toString(),
  "weights": weights,
  "goal": userData['goal'] ?? '',
"weight": userData['weight'] ?? 0,
"age": userData['age'] ?? 0,
"gender": userData['gender'] ?? '',
"activitylevel": userData['activitylevel'] ?? '',
"height_cm": userData['height_cm'] ?? 0,
"allergies": userData['allergies'] ?? [],
"health_condition": userData['healthConditions'] ?? [],
"meal_plan_last_updated": userData['meal_plan_last_updated'] ?? '',
}),
      );

      if (response.statusCode != 200) {
        debugPrint("Backend returned ${response.statusCode}");
        if (mounted) setState(() => loading = false);
        return;
      }
     final data = jsonDecode(response.body);
final newMealPlan = data["new_meal_plan"];
final newUpdatedAt = data["new_meal_plan_updated_at"];

if (newMealPlan != null && newUpdatedAt != null) {
  await _saveNewMealPlanToFirestore(newMealPlan, newUpdatedAt);
}

// ✅ NEW: Agar daily calories exceed hui toh auto compensation plan Firestore mein save karo
if (selectedPeriod == "daily") {
  final totalEatenNow = (data['totalAllEaten'] ?? 0).toDouble();
  final dailyTargetNow = (data['dailyTarget'] ?? 0).toDouble();

  if (dailyTargetNow > 0 && totalEatenNow > dailyTargetNow * 1.15) {
    
    if (uid != null) {
      // Check karo ke aaj ka compensation plan already save hua hai ya nahi
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);

      final existingSnap = await FirebaseFirestore.instance
    .collection('users')
    .doc(uid)
    .collection('meals')
    .where('is_cheat', isEqualTo: true)
    .where('date_str', isEqualTo: todayStr)
    .limit(1)
    .get();

if (existingSnap.docs.isEmpty) {
        // Cheat meal endpoint call karo same userData se
        final cheatPayload = {
          "user": {
            "user_id": uid,
            "name": userData['name'] ?? '',
            "age": userData['age']?.toString() ?? '0',
            "weight": userData['weight']?.toString() ?? '0',
            "height": userData['height']?.toString() ?? '0',
            "gender": userData['gender'] ?? '',
            "goal": userData['goal'] ?? 'maintain',
            "activitylevel": userData['activitylevel'] ?? 'moderately active',
            "bmi": userData['bmi'] ?? 0,
            "bmr": userData['bmr'] ?? 0,
            "tdee": userData['tdee'] ?? 0,
            "daily_calories_target": dailyTargetNow,
            "daily_protein_target": 0,
            "daily_carbs_target": 0,
            "daily_fats_target": 0,
          },
          "all_meals": eatenFoods.map((f) => {
            "food_name": f['food_name'] ?? '',
            "calories": (f['calories'] ?? 0).toDouble(),
            "protein_g": (f['protein_g'] ?? 0).toDouble(),
            "carbs_g": (f['carbs_g'] ?? 0).toDouble(),
            "fat_g": (f['fat_g'] ?? 0).toDouble(),
            "is_cheat": false,
          }).toList(),
          "cheat_meal": {
            "food_name": "Daily Overage",
            "calories": totalEatenNow - dailyTargetNow,
            "protein_g": 0,
            "carbs_g": 0,
            "fat_g": 0,
            "is_cheat": true,
            "created_at": DateTime.now().toIso8601String(),
          },
        };

        try {
          final cheatResponse = await http.post(
            Uri.parse('https://nutrifit-backend-production-1761.up.railway.app/cheatmeal'),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode(cheatPayload),
          );

          if (cheatResponse.statusCode == 200) {
            final cheatData = jsonDecode(cheatResponse.body);

            if (cheatData['status'] == 'success') {
            await FirebaseFirestore.instance
    .collection('users')
    .doc(uid)
    .collection('meals')
    .add({
  'food_name': 'Daily Overage',
  'calories': totalEatenNow - dailyTargetNow,
  'protein_g': 0,
  'carbs_g': 0,
  'fat_g': 0,
  'is_cheat': true,
  'date_str': todayStr,
  'created_at': FieldValue.serverTimestamp(),
  'surplus': cheatData['surplus'] ?? 0,
  'severity': cheatData['severity'] ?? '',
  'strategy': cheatData['strategy'] ?? '',
  'window_days': cheatData['window_days'] ?? 0,
  'compensation_days': cheatData['compensation_days'] ?? [],
});
              debugPrint("Auto compensation plan Firestore mein save ho gaya");

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: Colors.red.shade700,
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.all(16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    content: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: Colors.white, size: 24),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            "Calories exceeded! Compensation plan ready. Check Meal Plan → View Compensation Plan.",
                            style: TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    duration: const Duration(seconds: 5),
                  ),
                );
              }
            }
          }
        } catch (e) {
          debugPrint("Auto compensation error: $e");
        }
      }
    }
  }
}

// ── Adaptive Plan fields: print + Firestore save ────────────────────────
final adaptive = (data["adaptivePlan"] as Map<String, dynamic>?) ?? {};
final bool fourteenDaysPassed = adaptive["14_days_passed"] == true;
final int noOfDaysPassed      = (adaptive["no_of_days_passed"] as num?)?.toInt() ?? 0;
final bool progress           = adaptive["progress"] == true;

debugPrint("───── Adaptive Plan Debug ─────");
debugPrint("14_days_passed   : $fourteenDaysPassed");
debugPrint("no_of_days_passed: $noOfDaysPassed");
debugPrint("progress         : $progress");
debugPrint("───────────────────────────────");

if (uid != null) {
  await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .update({
    '14_days_passed'    : fourteenDaysPassed,
    'no_of_days_passed' : noOfDaysPassed,
    'progress'          : progress,
  });
  debugPrint("Adaptive fields Firestore mein save ho gaye.");
}

if (!mounted) return;

// ── Multiple alerts simultaneously (stacked via Overlay) ──
final List<Map<String, dynamic>> activeAlerts = [];

if (data['hasLateMeals'] == true) {
  final alerts = (data['lateMealAlerts'] as List).join("\n");
  activeAlerts.add({
    'title': 'Meal Time Missed!',
    'message': '$alerts — You are eating late. This can harm your daily progress. Eat on time!',
    'icon': Icons.alarm_off_rounded,
    'color': Colors.red.shade600,
  });
  NotificationService().showNotification(
    "Meal Time Reminder",
    "It's time for your meal! Eating on schedule helps you stay on track.",
    const Duration(seconds: 2),
  );
}

if (data['hasUnmatchedFoods'] == true) {
  final foods = (data['unmatchedFoods'] as List).join(", ");
  activeAlerts.add({
    'title': 'Unplanned Food Detected!',
    'message': '$foods — These foods are not in your meal plan. Avoid them to stay on track.',
    'icon': Icons.warning_amber_rounded,
    'color': Colors.orange.shade700,
  });
  NotificationService().showNotification(
    "Unplanned Food Detected",
    "You ate something not in your meal plan. Try to stick to your goals!",
    const Duration(seconds: 2),
  );
}

if (activeAlerts.isNotEmpty) {
  _showStackedAlerts(context, activeAlerts);
}
      if ((data['progressPercentage'] ?? 0) < 99 &&
          !hasShownProgressReminder) {
        String progressMsg;
        if (data['progressPercentage'] == 0) {
  progressMsg = "You haven't logged anything yet today — start with your first meal!";}
else if (data['progressPercentage'] < 50) {
  progressMsg = "You're just getting started today — log a meal to build momentum!";
} else if (data['progressPercentage'] < 80) {
  progressMsg = "You're making good progress — keep logging to reach your goal!";
} else {
  progressMsg = "You're almost there — one more log and you'll hit today's target!";
}

NotificationService().showNotification(
  "Keep Logging 🎯",
  progressMsg,
  Duration(),
);
        hasShownProgressReminder = true;
      }

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

        // Save matched/unmatched counts for gamification (daily only)
        if (selectedPeriod == "daily") {
          final dailyMeals =
              (data['dailyMeals'] as Map<String, dynamic>?) ?? {};

          int matchedCount = 0;
          dailyMeals.forEach((slot, info) {
            if ((info['eaten_calories'] ?? 0) > 0) matchedCount++;
          });

          final unmatchedList = List.from(data['unmatchedFoods'] ?? []);
          final lateList = List.from(data['lateMealAlerts'] ?? []);
          final unmatchedCount = unmatchedList.length + lateList.length;

          await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .update({
            "matchedFoodCount": matchedCount,
            "unmatchedFoodCount": unmatchedCount,
          });
        }
      }
      if (!mounted) return;
      setState(() {
        progressPercentage = (data['progressPercentage'] ?? 0).toDouble();
final exP = data['exerciseProgress'] ?? {};
exerciseProgressPercentage = (exP['exerciseProgressPercentage'] ?? 0).toDouble();
completedExercises = (exP['completedExercises'] ?? 0).toInt();
totalPlannedExercises = (exP['totalPlannedExercises'] ?? 0).toInt();
// Per-exercise breakdown backend se
perExerciseProgress = List<Map<String, dynamic>>.from(
    (exP['perExercise'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));
todayExerciseRepsProgress = perExerciseProgress
    .map<double>((e) => ((e['percentage'] ?? 0.0) as num).toDouble() / 100.0)
    .toList();
        proteinPercentage =
            (data['proteinPercentage'] ?? 0).toDouble();
        fatsPercentage =
            (data['fatsPercentage'] ?? 0).toDouble();
        carbsPercentage =
            (data['carbsPercentage'] ?? 0).toDouble();

  totalAllEaten = (data['totalAllEaten'] ?? 0).toDouble();
workoutHours = (data['workoutHours'] ?? 0).toDouble();
        // ── DAILY ──────────────────────────────────────────
        if (selectedPeriod == "daily") {
          // AFTER:
final dailyMeals =
    (data['dailyMeals'] as Map<String, dynamic>?) ?? {};
const mealOrder = ['breakfast', 'lunch', 'dinner'];
final orderedNames = mealOrder
    .where((m) => dailyMeals.containsKey(m))
    .toList();
dailyMealsNames  = orderedNames;
dailyMealsEaten  = orderedNames
    .map<double>((m) => (dailyMeals[m]?['eaten_calories'] ?? 0).toDouble())
    .toList();
dailyMealsTarget = orderedNames
    .map<double>((m) => (dailyMeals[m]?['target_calories'] ?? 0).toDouble())
    .toList();
dailyMealsStatus = orderedNames
    .map<String>((m) => dailyMeals[m]?['status']?.toString() ?? 'on track')
    .toList();
          dailyTotalEaten  = (data['totalEaten']  ?? 0).toDouble();
          dailyTotalTarget = (data['dailyTarget'] ?? 0).toDouble();
        }

        // ── WEEKLY ─────────────────────────────────────────
        if (selectedPeriod == "weekly") {
          const weekdaysOrder = [
            "Monday","Tuesday","Wednesday",
            "Thursday","Friday","Saturday","Sunday"
          ];
          final wd =
              (data['weeklyData'] as Map<String, dynamic>?) ?? {};

          weeklyCalories = weekdaysOrder
              .map<double>((d) => (wd[d]?['calories'] ?? 0).toDouble())
              .toList();
          weeklyAllEaten = weekdaysOrder
              .map<double>((d) => (wd[d]?['allEaten'] ?? 0).toDouble())
              .toList();
          weeklyTarget   = weekdaysOrder
              .map<double>((d) => (wd[d]?['target'] ?? 0).toDouble())
              .toList();
          weeklyTrend    = weekdaysOrder
              .map<double>((d) => (wd[d]?['trend'] ?? 0).toDouble())
              .toList();
          progressStatus = weekdaysOrder
              .map<String>((d) => wd[d]?['status']?.toString() ?? 'on track')
              .toList();
        }

        // ── MONTHLY ────────────────────────────────────────
        if (selectedPeriod == "monthly") {
          final md =
              (data['monthlyData'] as Map<String, dynamic>?) ?? {};
          monthlyCalories  = md.values.map<double>((w) => (w['calories'] ?? 0).toDouble()).toList();
          monthlyTarget    = md.values.map<double>((w) => (w['target']   ?? 0).toDouble()).toList();
          monthlyAllEaten  = md.values.map<double>((w) => (w['allEaten'] ?? 0).toDouble()).toList();
          monthlyTrend     = md.values.map<double>((w) => (w['trend']    ?? 0).toDouble()).toList();
        }

        loading = false;
      });
    }  catch (e) {
      debugPrint("Backend error: $e");
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    List<double> weeklyMonthlyCalories = [];
    List<double> weeklyMonthlyTarget = [];

    // ── pick the right data arrays per period ──────────────
    List<double> caloriesData;
    List<double> targetData;
    List<double> trendData;
    List<double> caloriesChartData;
    int daysCount;

    if (selectedPeriod == "daily") {
      daysCount          = dailyMealsNames.length;
      caloriesData       = dailyMealsEaten;
      targetData         = dailyMealsTarget;
      trendData          = dailyMealsEaten;
      caloriesChartData  = dailyMealsEaten;
    } else if (selectedPeriod == "monthly") {
      daysCount          = monthlyCalories.length;
      caloriesData       = monthlyCalories;
      targetData         = monthlyTarget;
      trendData          = monthlyTrend;
      caloriesChartData  = monthlyAllEaten;
    } else {
      // weekly
      daysCount          = 7;
      caloriesData       = weeklyCalories;
      targetData         = weeklyTarget;
      trendData          = weeklyTrend;
      caloriesChartData  = weeklyAllEaten;
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: loading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text(
  selectedPeriod == "daily"
      ? "Fetching your daily progress..."
      : selectedPeriod == "monthly"
          ? "Fetching your monthly progress..."
          : "Fetching your weekly progress...",
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
                    // ── Header Row ─────────────────────────────────────────
                    Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Progress",
                          style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold),
                        ),
                        // ── Period Dropdown ─────────────────────────
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12),
                          decoration: BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(20),
                            color: Colors.grey.shade100,
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selectedPeriod,
                              icon: const Icon(
                                  Icons.keyboard_arrow_down),
                              items: const [
                                DropdownMenuItem(
                                    value: "daily",
                                    child: Text("Daily")),
                                DropdownMenuItem(
                                    value: "weekly",
                                    child: Text("Weekly")),
                                DropdownMenuItem(
                                    value: "monthly",
                                    child: Text("Monthly")),
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
                    const SizedBox(height: 6),
                    Text(
                      selectedPeriod == "daily"
                          ? "Today's overview"
                          : selectedPeriod == "weekly"
                          ? "Weekly overview"
                          : "Monthly overview",
                      style:
                          const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    // ── Download Button ─────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: loading
                            ? null
                            : () =>
                                _showDownloadModal(context),
                        icon: const Icon(
                            Icons.download_rounded,
                            size: 16),
                        label: const Text(
                          "Download Report",
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              const Color(0xFF2E7D32),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(12)),
                          elevation: 2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
SizedBox(
  width: double.infinity,
  child: OutlinedButton.icon(
    onPressed: () => _showExerciseLogsModal(context),
    icon: const Icon(Icons.play_circle_outline_rounded, size: 16),
    label: const Text(
      "View Exercise Logs",
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
    style: OutlinedButton.styleFrom(
      foregroundColor: const Color(0xFF1565C0),
      side: const BorderSide(color: Color(0xFF1565C0)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
),
const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            icon: Icons.local_fire_department,
                            value:
                                "${caloriesBurned.toStringAsFixed(2)} kcal",
                            label: "Burned",
                            gradient: const [
                              Colors.orange,
                              Colors.deepOrange
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatCard(
                            icon: Icons.fastfood,
                            value:
                               "${totalAllEaten.toInt()} kcal",
                            label: "Eaten",
                            gradient: const [
                              Colors.pink,
                              Colors.redAccent
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatCard(
                            icon: Icons.timer,
                            value:
                                "${workoutHours.toStringAsFixed(2)} hrs",
                            label: "Workout",
                            gradient: const [
                              Colors.blue,
                              Colors.lightBlueAccent
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.grey.shade200, blurRadius: 8, offset: const Offset(0, 3))],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── LEFT: Exercise Progress circular bar ──
                          Expanded(
                            flex: 1,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const Text("Exercise\nProgress",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: 72, height: 72,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      CircularProgressIndicator(
                                        value: exerciseProgressPercentage / 100,
                                        strokeWidth: 7,
                                        backgroundColor: Colors.grey.shade200,
                                        valueColor: AlwaysStoppedAnimation(
                                          exerciseProgressPercentage >= 80 ? Colors.green
                                          : exerciseProgressPercentage >= 40 ? Colors.orange
                                          : Colors.redAccent,
                                        ),
                                      ),
                                      Text(
                                        "${exerciseProgressPercentage.toStringAsFixed(0)}%",
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                
                                const SizedBox(height: 4),
                                Text(
                                  exerciseProgressPercentage >= 100 ? "💪 All done!"
                                  : exerciseProgressPercentage > 0 ? "Keep going!"
                                  : "Not started",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: exerciseProgressPercentage >= 100 ? Colors.green : Colors.blue,
                                    fontSize: 11, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // ── RIGHT: Today's Exercise Plan ─────────
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Today's Exercises",
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                const SizedBox(height: 8),
                                if (todayExercises.isEmpty)
                                  Text("No exercises loaded",
                                      style: TextStyle(color: Colors.grey.shade400, fontSize: 12))
                                else
                                  ...todayExercises.asMap().entries.map((entry) {
                                    final i = entry.key;
                                    final ex = entry.value;
                                    final repsPct = i < todayExerciseRepsProgress.length
    ? todayExerciseRepsProgress[i]
    : 0.0;
final exItemColor = repsPct >= 1.0 ? Colors.green
    : repsPct > 0 ? Colors.orange
    : Colors.blue;

                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 40, height: 40,
                                            child: Stack(
                                              alignment: Alignment.center,
                                              children: [
                                                CircularProgressIndicator(
  value: repsPct,
  strokeWidth: 4,
  backgroundColor: Colors.grey.shade200,
  valueColor: AlwaysStoppedAnimation(exItemColor),
),
Text(
  "${(repsPct * 100).toInt()}%",
  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: exItemColor),
),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  ex['exercise_name'] ?? '',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                    color: repsPct >= 1.0 ? Colors.grey : Colors.black87,
decoration: repsPct >= 1.0 ? TextDecoration.lineThrough : null,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                Text(
                                                  "${ex['sets'] ?? '-'}s × ${ex['repetitions'] ?? '-'}r • ${ex['duration'] ?? '-'}min",
                                                  style: const TextStyle(fontSize: 11, color: Colors.black45),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // ── Macros ─────────────────────────────────────────────
                    SizedBox(
                      height: 180,
                      child: Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            flex: 2,
                            child: Center(
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  SizedBox(
                                    width: 140,
                                    height: 140,
                                    child:
                                        CircularProgressIndicator(
                                      value: (progressPercentage
                                              .clamp(0, 100)) /
                                          100,
                                      strokeWidth: 12,
                                      color: Colors.green,
                                      backgroundColor:
                                          Colors.grey.shade300,
                                    ),
                                  ),
                                  Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                          Icons
                                              .local_fire_department,
                                          color: Colors.green,
                                          size: 26),
                                      const SizedBox(height: 6),
                                      Text(
                                        "${progressPercentage.toStringAsFixed(2)}%",
                                        style: const TextStyle(
                                            fontSize: 22,
                                            fontWeight:
                                                FontWeight.bold),
                                      ),
                                      const Text("Calories",
                                          style: TextStyle(
                                              fontSize: 12,
                                              color:
                                                  Colors.grey)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            flex: 1,
                            child: Column(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceEvenly,
                              children: [
                                _smallMacroCircle(
                                    title: "Protein",
                                    value: proteinPercentage,
                                    color: Colors.blue,
                                    icon: Icons.set_meal),
                                _smallMacroCircle(
                                    title: "Fats",
                                    value: fatsPercentage,
                                    color: Colors.orange,
                                    icon: Icons.opacity),
                                _smallMacroCircle(
                                    title: "Carbs",
                                    value: carbsPercentage,
                                    color: Colors.green,
                                    icon: Icons.grain),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ── Daily Meals Breakdown ──────────────────────────────
if (selectedPeriod == "daily") ...[
  const Text(
    "Today's Meals",
    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
  ),
  const SizedBox(height: 12),
  ...List.generate(dailyMealsNames.length, (i) {
    final mealKey = dailyMealsNames[i];
    final eaten   = i < dailyMealsEaten.length  ? dailyMealsEaten[i]  : 0.0;
    final target  = i < dailyMealsTarget.length ? dailyMealsTarget[i] : 0.0;
    final status  = i < dailyMealsStatus.length ? dailyMealsStatus[i] : 'on track';
    final pct     = target > 0 ? (eaten / target).clamp(0.0, 1.0) : 0.0;
    final color   = status == 'over'  ? Colors.red
                  : status == 'under' ? Colors.orange
                  : Colors.green;
    final icon    = mealKey == 'breakfast' ? Icons.free_breakfast
                  : mealKey == 'lunch'     ? Icons.lunch_dining
                  : mealKey == 'dinner'    ? Icons.dinner_dining
                  : Icons.fastfood;

    // Time-based visibility: sirf current time window wali meal dikhao
    final now          = DateTime.now().hour;
    final window       = _mealHours[mealKey];
    final isCurrentMeal = window != null && now >= window[0] && now < window[1];

    // Foods for this meal from meal plan
    final foods = dailyMealFoods[mealKey] ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header Row ──────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: color.withOpacity(0.15),
                    child: Icon(icon, color: color, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    mealKey[0].toUpperCase() + mealKey.substring(1),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  if (isCurrentMeal) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        "Now",
                        style: TextStyle(
                            color: Colors.blue,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ]),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(status,
                      style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),

            // ── Linear progress bar ──────────────────────
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 10,
                backgroundColor: color.withOpacity(0.15),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("${eaten.toInt()} kcal eaten",
                    style: const TextStyle(
                        color: Colors.grey, fontSize: 12)),
                Text("Target: ${target.toInt()} kcal",
                    style: const TextStyle(
                        color: Colors.grey, fontSize: 12)),
              ],
            ),

            // ── Food items — sirf current meal waqt pe show hoga ──
            if (isCurrentMeal && foods.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Divider(height: 1, color: Color(0xFFEEEEEE)),
              const SizedBox(height: 10),
              const Text(
                "What to eat now",
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54),
              ),
              const SizedBox(height: 8),
              ...foods.map((food) {
                final foodName = food['food_name'] ?? '';
                final targetQty   = (food['quantity'] ?? food['grams'] ?? 0).toDouble();
final calories    = (food['calories'] ?? 0).toDouble();
final foodNameKey = foodName.toLowerCase().trim();
final eatenQty    = dailyFoodEatenGrams[mealKey]?[foodNameKey] ?? 0.0;
final circlePct   = targetQty > 0
    ? (eatenQty / targetQty).clamp(0.0, 1.0)
    : 0.0;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      // Round circular progress bar per food
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircularProgressIndicator(
                              value: circlePct,
                              strokeWidth: 5,
                              backgroundColor:
                                  color.withOpacity(0.15),
                              valueColor:
                                  AlwaysStoppedAnimation(color),
                            ),
                            Text(
                              "${(circlePct * 100).toInt()}%",
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: color),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              foodName,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                         Text(
  "${eatenQty.toStringAsFixed(1)} / ${targetQty.toStringAsFixed(1)} ${food['unit'] ?? 'g'}  •  ${calories.toInt()} kcal",
  style: const TextStyle(fontSize: 12, color: Colors.black45),
),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }),

  // ── Total Today card ──────────────────────────────
  Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.green,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text("Total Today",
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16)),
        Text(
          "${dailyTotalEaten.toInt()} / ${dailyTotalTarget.toInt()} kcal",
          style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16),
        ),
      ],
    ),
  ),
 /* if (selectedPeriod == "daily" && todayExercises.isNotEmpty) ...[
  const Text(
    "Today's Exercises",
    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
  ),
  const SizedBox(height: 12),
  ...List.generate(todayExercises.length, (i) {
    final ex = todayExercises[i];
    final isDone = i < exerciseCompleted.length
        ? exerciseCompleted[i]
        : false;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 10),
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: isDone
              ? Colors.green.withOpacity(0.15)
              : Colors.blue.withOpacity(0.12),
          child: Icon(
            isDone
                ? Icons.check_circle_rounded
                : Icons.fitness_center_rounded,
            color: isDone ? Colors.green : Colors.blue,
            size: 20,
          ),
        ),
        title: Text(
          ex['exercise_name'] ?? '',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            decoration: isDone
                ? TextDecoration.lineThrough
                : TextDecoration.none,
            color: isDone ? Colors.grey : Colors.black87,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            "Sets: ${ex['sets'] ?? '-'}  •  Reps: ${ex['repetitions'] ?? '-'}  •  ${ex['duration'] ?? '-'} min",
            style: const TextStyle(
                fontSize: 12, color: Colors.black54),
          ),
        ),
        trailing: GestureDetector(
          onTap: () => _toggleExerciseComplete(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDone ? Colors.green : Colors.transparent,
              border: Border.all(
                color: isDone ? Colors.green : Colors.grey.shade400,
                width: 2,
              ),
            ),
            child: isDone
                ? const Icon(Icons.check,
                    color: Colors.white, size: 18)
                : null,
          ),
        ),
      ),
    );
  }),
  const SizedBox(height: 20),
],*/
  const SizedBox(height: 32),
],
                    // ── Calories Bar Chart ─────────────────────────────────
                    Text(
                      selectedPeriod == "daily"
                          ? "Today's Meal Calories"
                          : selectedPeriod == "weekly"
                              ? "This Week's Daily Calories"
                              : "This Month's Weekly Calories",
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 200,
                      child: BarChart(
                        BarChartData(
                          maxY: 100,
                          gridData: FlGridData(show: false),
                          borderData:
                              FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, _) {
                                  final idx = value.toInt();
                                  if (selectedPeriod == "weekly") {
                                    const days = ['M','T','W','T','F','S','S'];
                                    if (idx < 0 || idx >= days.length) return const SizedBox.shrink();
                                    return Text(days[idx]);
                                  }
                                  if (selectedPeriod == "daily") {
                                    if (idx < 0 || idx >= dailyMealsNames.length) return const SizedBox.shrink();
                                    final n = dailyMealsNames[idx];
                                    return Text(n[0].toUpperCase() + n.substring(1, n.length > 2 ? 3 : 1));
                                  }
                                  // monthly
                                  const weeks = ['W1','W2','W3','W4'];
                                  if (idx < 0 || idx >= weeks.length) return const SizedBox.shrink();
                                  return Text(weeks[idx]);
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
                                      return const SizedBox
                                          .shrink();
                                  }
                                },
                              ),
                            ),
                            topTitles: AxisTitles(
                                sideTitles: SideTitles(
                                    showTitles: false)),
                            rightTitles: AxisTitles(
                                sideTitles: SideTitles(
                                    showTitles: false)),
                          ),
                          barGroups:
                              List.generate(daysCount, (i) {
                            final eaten =
                                i < caloriesData.length
                                    ? caloriesData[i]
                                    : 0;
                            final target =
                                i < targetData.length
                                    ? targetData[i]
                                    : 0;
                            final eatenPercent = target > 0
                                ? (eaten / target) * 100.0
                                : 0.0;
                            final displayPercent =
                                eatenPercent > 100.0
                                    ? 100.0
                                    : eatenPercent;
                            return BarChartGroupData(
                              x: i,
                              barRods: [
                                BarChartRodData(
                                  toY: displayPercent,
                                  width: 14,
                                  color: Colors.green,
                                  borderRadius:
                                      BorderRadius.circular(4),
                                  backDrawRodData:
                                      BackgroundBarChartRodData(
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
                            touchTooltipData:
                                BarTouchTooltipData(
                              getTooltipItem: (group,
                                  groupIndex, rod, rodIndex) {
                                final eaten =
                                    groupIndex <
                                            caloriesData.length
                                        ? caloriesData[
                                            groupIndex]
                                        : 0;
                                final target =
                                    groupIndex <
                                            targetData.length
                                        ? targetData[groupIndex]
                                        : 0;
                                double percent = target > 0
                                    ? (eaten / target) * 100
                                    : 0;
                                if (percent > 100.0)
                                  percent = 100.0;
                                return BarTooltipItem(
                                  "${percent.toStringAsFixed(2)}%",
                                  const TextStyle(
                                      color: Colors.white,
                                      fontWeight:
                                          FontWeight.bold),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ── Performance Trend Line Chart ───────────────────────
                    const Text(
                      "Performance Trend",
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600),
                    ),
                    
                    const SizedBox(height: 16),
SizedBox(
  height: 260,
  child: LineChart(
                        LineChartData(
                          minY: 0.0,
                          gridData: FlGridData(show: false),
                          borderData:
                              FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            leftTitles: AxisTitles(
                              axisNameWidget: const Text(
                                  "Calories",
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey)),
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 50,
                                interval: () {
  final maxVal = caloriesChartData.isEmpty
      ? 500.0
      : caloriesChartData.reduce((a, b) => a > b ? a : b);
  final step = (maxVal / 5).ceilToDouble();
  return step <= 0 ? 500.0 : step;  // zero guard
}(),
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              axisNameWidget: const Text(
                                  "Days",
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey)),
                              sideTitles: SideTitles(
                                showTitles: true,
                                interval: 1,
                                getTitlesWidget: (value, meta) {
                                  final idx = value.toInt();
                                  if (selectedPeriod == "weekly") {
                                    const days = ['M','T','W','T','F','S','S'];
                                    if (idx < 0 || idx >= days.length) return const SizedBox.shrink();
                                    return SideTitleWidget(meta: meta, child: Text(days[idx]));
                                  }
                                  if (selectedPeriod == "daily") {
                                    if (idx < 0 || idx >= dailyMealsNames.length) return const SizedBox.shrink();
                                    final n = dailyMealsNames[idx];
                                    return SideTitleWidget(meta: meta, child: Text(n[0].toUpperCase() + n.substring(1, n.length > 3 ? 3 : 1)));
                                  }
                                  // monthly
                                  const weeks = ['W1','W2','W3','W4'];
                                  if (idx < 0 || idx >= weeks.length) return const SizedBox.shrink();
                                  return SideTitleWidget(meta: meta, child: Text(weeks[idx]));
                                },
                              ),
                            ),
                            topTitles: AxisTitles(
                                sideTitles: SideTitles(
                                    showTitles: false)),
                            rightTitles: AxisTitles(
                                sideTitles: SideTitles(
                                    showTitles: false)),
                          ),
                          lineBarsData: [
  LineChartBarData(
    isCurved: true,
    color: Colors.redAccent,
    barWidth: 3,
    dotData: FlDotData(show: true),
    belowBarData: BarAreaData(
        show: true,
        color: Colors.redAccent
            .withOpacity(0.2)),
    spots: List.generate(
      caloriesChartData.length,
      (i) => FlSpot(i.toDouble(),
          caloriesChartData[i]),
    ),
  ),
],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ── Weight Trend ───────────────────────────────────────
                    const Text(
                      "Weight Trend",
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 16),
                    Builder(
                      builder: (context) {
                        final weightData =
                            selectedPeriod == "monthly"
                                ? monthlyWeightTrend
                                : weeklyWeightTrend;
                        final nonZero = weightData
                            .where((v) => v > 0)
                            .toList();
                        final double minWeight = nonZero.isEmpty
                            ? 0
                            : (nonZero.reduce((a, b) =>
                                        a < b ? a : b) -
                                    2)
                                .clamp(0, double.infinity);
                        final double maxWeight = nonZero.isEmpty
                            ? 10
                            : nonZero.reduce(
                                    (a, b) => a > b ? a : b) +
                                2;

                        return SizedBox(
                          height: 260,
                          child: weightData.every((v) => v == 0)
                              ? const Center(
                                  child: Text(
                                      "No weight data available",
                                      style: TextStyle(
                                          color: Colors.grey)),
                                )
                              : LineChart(
                                  LineChartData(
                                    minX: 0,
                                    maxX:
                                        selectedPeriod == "monthly"
                                            ? 11
                                            : 3,
                                    minY: minWeight,
                                    maxY: maxWeight,
                                    gridData: FlGridData(
                                        show: true,
                                        drawVerticalLine:
                                            false),
                                    borderData:
                                        FlBorderData(
                                            show: false),
                                    titlesData: FlTitlesData(
                                      bottomTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          interval: 1,
                                          getTitlesWidget:
                                              (value, meta) {
                                            final idx =
                                                value.toInt();
                                            if (selectedPeriod ==
                                                "weekly") {
                                              if (idx < 0 ||
                                                  idx > 3)
                                                return const SizedBox
                                                    .shrink();
                                              return SideTitleWidget(
                                                meta: meta,
                                                child: Text(
                                                    "W${idx + 1}",
                                                    style: const TextStyle(
                                                        fontSize:
                                                            11)),
                                              );
                                            } else {
                                              if (idx < 0 ||
                                                  idx > 11)
                                                return const SizedBox
                                                    .shrink();
                                              const monthNames = [
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
                                                'Dec'
                                              ];
                                              return SideTitleWidget(
                                                meta: meta,
                                                child: Text(
                                                    monthNames[
                                                        idx],
                                                    style: const TextStyle(
                                                        fontSize:
                                                            10)),
                                              );
                                            }
                                          },
                                        ),
                                      ),
                                      leftTitles: AxisTitles(
                                        axisNameWidget:
                                            const Text("kg",
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors
                                                        .grey)),
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          reservedSize: 42,
                                          interval: ((maxWeight -
                                                      minWeight) /
                                                  4)
                                              .clamp(0.5, 10),
                                          getTitlesWidget:
                                              (value, meta) =>
                                                  Text(
                                                      value
                                                          .toStringAsFixed(
                                                              1),
                                                      style: const TextStyle(
                                                          fontSize:
                                                              10)),
                                        ),
                                      ),
                                      topTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                              showTitles: false)),
                                      rightTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                              showTitles: false)),
                                    ),
                                    lineBarsData: [
                                      LineChartBarData(
                                        isCurved: false,
                                        isStrokeCapRound: true,
                                        color: Colors.blue,
                                        barWidth: 3,
                                        belowBarData:
                                            BarAreaData(
                                                show: true,
                                                color: Colors
                                                    .blue
                                                    .withOpacity(
                                                        0.2)),
                                        spots: weightData
                                            .asMap()
                                            .entries
                                            .where((e) =>
                                                e.value > 0)
                                            .map((e) => FlSpot(
                                                e.key.toDouble(),
                                                e.value))
                                            .toList(),
                                      ),
                                    ],
                                    lineTouchData: LineTouchData(
                                      touchTooltipData:
                                          LineTouchTooltipData(
                                        getTooltipItems:
                                            (spots) =>
                                                spots.map((s) {
                                          return LineTooltipItem(
                                            "${s.y.toStringAsFixed(1)} kg",
                                            const TextStyle(
                                                color:
                                                    Colors.white,
                                                fontWeight:
                                                    FontWeight
                                                        .bold),
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
              ),
      ),
    );
  }
}

// ─── STAT CARD WIDGET ─────────────────────────────────────────────────────────
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
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.white,
            child:
                Icon(icon, size: 18, color: gradient.last),
          ),
          const SizedBox(height: 12),
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.white)),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: Colors.white70)),
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
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(fontSize: 11),
                overflow: TextOverflow.ellipsis),
            Text("${value.toStringAsFixed(2)}%",
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
          ],
        ),
      ),
    ],
  );
}

// ─── DOWNLOAD MODAL OPTION WIDGET ────────────────────────────────────────────
class _DownloadModalOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;

  const _DownloadModalOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child:
                    Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: color.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 14, color: color.withOpacity(0.5)),
            ],
          ),
        ),
      ),
    );
  }
}