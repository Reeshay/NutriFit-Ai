import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nutrifit/chatbot.dart';
import 'package:nutrifit/gamification.dart';
import 'package:nutrifit/track_progress.dart';
import 'meal_plan.dart';
import 'profile_setup.dart';
import 'exercise_plan.dart';
import 'login_page.dart';
import 'notification.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  User? user;
  bool hasShownProfileReminder = false;
  bool isLoadingPersonal = true;
  bool isLoadingMetrics = true;
  String? previousBadge;
  final Map<String, int> badgeRank = {
  "bronze": 1,
  "silver": 2,
  "gold": 3,
};
final NotificationService notificationService = NotificationService();
  String? name;
  String gender = "Male";
  String activitylevel = "";
  String fitnessGoal = "";

  String? targetTimeline;
  int? age;
  double height = 0.0;
  double weight = 0.0;
  double targetWeight = 0.0;

  double bmi = 0.0;
  double bmr = 0.0;
  double tdee = 0.0;
  int? timelineWeeks;
  String? badge; // state variable


  List<String> allergies = [];
List<String> healthConditions = [];

  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    user = FirebaseAuth.instance.currentUser;
    notificationService.init();

    if (user != null) {
      _loadUserInfo();
    } else {
      isLoadingPersonal = false;
      isLoadingMetrics = false;
    }
  }

  Future<void> _loadUserInfo() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection("users")
          .doc(user!.uid)
          .get();

      if (!doc.exists) return;

      final data = doc.data()!;
bool isProfileCompleted = data["isProfileCompleted"] ?? false;

if (!isProfileCompleted && !hasShownProfileReminder) {
  notificationService.showNotification(
    "Complete Your Profile",
    "Please complete your profile to unlock your full Nutrifit experience.",
    Duration()
  );

  hasShownProfileReminder = true;
}      if (!mounted) return;

      setState(() {
        name = data["name"]?.toString();
        age = int.tryParse(data["age"]?.toString() ?? "0") ?? 0;
        height = double.tryParse(data["height"]?.toString() ?? "0") ?? 0.0;
        weight = double.tryParse(data["weight"]?.toString() ?? "0") ?? 0.0;
        targetWeight =
            double.tryParse(data["targetWeight"]?.toString() ?? "0") ?? 0.0;

        gender = data["gender"]?.toString() ?? "Male";
        activitylevel = data["activitylevel"]?.toString() ?? "";
        fitnessGoal = data["goal"]?.toString() ?? "";

        targetTimeline = data["targetTimeLine"]?.toString() ?? "";
        timelineWeeks = data["timelineWeeks"] ?? 0;
        bmi = data["bmi"] ?? 0.0;
        bmr = data["bmr"] ?? 0.0;
        tdee = data["tdee"] ?? 0.0;

       allergies = List<String>.from(data["allergies"] ?? []);

healthConditions = List<String>.from(
  data["healthConditions"] ?? data["healthCondition"] ?? []
);
String? newBadge = data["current_badge"];

if (newBadge != null) {
  int newRank = badgeRank[newBadge] ?? 0;
  int oldRank = badgeRank[badge ?? ""] ?? 0;

  if (newRank > oldRank) {
    notificationService.showNotification(
      "Badge Upgraded!",
      "Congrats! You reached ${newBadge.toUpperCase()} level! Keep following your exercise and meal plan.",
      Duration()
    );
  }
}
badge = newBadge;if (badge != null) {
  notificationService.showNotification(
    "Badge Earned!",
    "You earned a ${badge!.toUpperCase()} badge!. Start following your meal and exercise plan for the placement of new badges.",
    Duration()
  );
}

        isLoadingPersonal = false;
        isLoadingMetrics = false;
      });
    } catch (e) {
      debugPrint("Error loading user info: $e");
      setState(() {
        isLoadingPersonal = false;
        isLoadingMetrics = false;
      });
    }
  }

  Future<void> _saveUserInfo(Map<String, dynamic> info) async {
    if (user != null) {
      await FirebaseFirestore.instance
          .collection("users")
          .doc(user!.uid)
          .set(info, SetOptions(merge: true));
    }

    if (!mounted) return;

    setState(() {
      name = info["name"];
      age = int.tryParse(info["age"] ?? "0") ?? 0;
      height = double.tryParse(info["height"] ?? "0") ?? 0.0;
      weight = double.tryParse(info["weight"] ?? "0") ?? 0.0;
      targetWeight = double.tryParse(info["targetWeight"] ?? "0") ?? 0.0;
      timelineWeeks = info['timeline_weeks'] ?? 0;
      gender = info["gender"] ?? "Male";
      activitylevel = info["activitylevel"] ?? "";
      fitnessGoal = info["goal"] ?? "";

      targetTimeline = info["targetTimeLine"];

      bmi = info["bmi"] ?? 0.0;
      bmr = info["bmr"] ?? 0.0;
      tdee = info["tdee"] ?? 0.0;
allergies = List<String>.from(info["allergies"] ?? []);
healthConditions = List<String>.from(info["healthConditions"] ?? []);
    });
  }

  void _logout() async {
    await FirebaseAuth.instance.signOut();

    if (!mounted) return;

    setState(() {
      user = null;
      name = null;
      age = null;
      height = 0.0;
      weight = 0.0;
      activitylevel = "";
      targetWeight = 0.0;
      gender = "Male";
      fitnessGoal = "";
      targetTimeline = null;
      timelineWeeks = 0;
      bmi = 0.0;
      bmr = 0.0;
      tdee = 0.0;
      allergies = [];
healthConditions = [];
    });

    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const LoginPage()));
  }

  void _onBottomNavTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  Widget _getBody() {
    switch (_selectedIndex) {
      case 0:
        return _buildMainContent();
      case 1:
        return MealPlan(
            targetGoal: fitnessGoal,
            activityLevel: activitylevel,
            timelineWeeks: timelineWeeks,
            gender: gender,
            weight: weight,
            height: height,
            age: age ?? 0,
            allergies: allergies,
            healthConditions: healthConditions);
            
      case 2:
        return ExercisePlan();
        case 3:
        return TrackProgress();
        case 4:
        return ChatbotPage();
        case 5:
        return GamificationPage();
        
      default:
        return _buildMainContent();
    }
  }

  Widget _buildMainContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 100, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Welcome, ${name ?? 'Guest'}",
            style: const TextStyle(
                color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          _buildCard(
            title: "Personal Information",
            isLoading: isLoadingPersonal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Name: ${name ?? ''}", style: infoStyle()),
                Text("Age: ${age ?? 0}", style: infoStyle()),
                Text("Gender: $gender", style: infoStyle()),
                Text("Height: $height ft", style: infoStyle()),
                Text("Weight: $weight kg", style: infoStyle()),
                Text("Target Weight: $targetWeight kg", style: infoStyle()),
                Text("Activity Level: $activitylevel", style: infoStyle()),
                Text("Goal: $fitnessGoal", style: infoStyle()),
                Text("Target Timeline: ${targetTimeline ?? ''}", style: infoStyle()),
                const SizedBox(height: 10),
                if (allergies.isNotEmpty) ...[
  const Text(
    "Allergies:",
    style: TextStyle(
      color: Colors.white,
      fontSize: 16,
      fontWeight: FontWeight.bold,
    ),
  ),
  const SizedBox(height: 8),
  Wrap(
    spacing: 8,
    children: allergies.map(
      (a) => Chip(
        label: Text(
          a,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.black,
      ),
    ).toList(),
  ),
  const SizedBox(height: 12),
],

if (healthConditions.isNotEmpty) ...[
  const Text(
    "Health Conditions:",
    style: TextStyle(
      color: Colors.white,
      fontSize: 16,
      fontWeight: FontWeight.bold,
    ),
  ),
  const SizedBox(height: 8),
  Wrap(
    spacing: 8,
    children: healthConditions.map(
      (m) => Chip(
        label: Text(
          m,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.black,
      ),
    ).toList(),
  ),
],
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    final updated = await Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const PersonalInformation()),
                    );

                    if (updated != null) {
                      _saveUserInfo(updated);
                    }
                  },
                  icon: const Icon(Icons.edit, color: Colors.white),
                  label: const Text("Edit Information",
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
          _buildCard(
            title: "Health Metrics",
            isLoading: isLoadingMetrics,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("BMI: $bmi", style: infoStyle()),
                Text("BMR: $bmr kcal/day", style: infoStyle()),
                Text("TDEE: $tdee kcal/day", style: infoStyle()),
               
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        drawer: Drawer(
        backgroundColor: Colors.black,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [

            DrawerHeader(
  decoration: const BoxDecoration(color: Colors.blueAccent),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      if (badge != null) 
        Image.asset(
          "images/$badge.png",
          width: 40,
          height: 40,
        ),
      const SizedBox(width: 10),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            name ?? "Guest",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            user?.email ?? "",
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ],
      ),
    ],
  ),
),
            _drawerItem(Icons.home, "Home", 0),
            _drawerItem(Icons.restaurant_menu, "Meal Plan", 1),
            
            _drawerItem(Icons.fitness_center, "Workout", 2),
            _drawerItem(Icons.show_chart, "Progress", 3),
            _drawerItem(Icons.chat, "Chatbot", 4),
            _drawerItem(Icons.games, "Gamification", 5),
          

            const Divider(color: Colors.white24),

            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text(
                "Logout",
                style: TextStyle(color: Colors.red),
              ),
              onTap: _logout,
            ),
          ],
        ),
      ),
        appBar: AppBar(
          
          backgroundColor: Colors.grey,
          elevation: 0,
          title: const Text("Nutrifit",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                "images/background_image.jpeg",
                fit: BoxFit.cover,
              ),
            ),
            Container(
              color: Colors.black54,
              child: _getBody(),
            ),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          backgroundColor: Colors.black,
          selectedItemColor: Colors.blueAccent,
          unselectedItemColor: Colors.white,
          currentIndex: _selectedIndex,
          onTap: _onBottomNavTapped,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
            BottomNavigationBarItem(
                icon: Icon(Icons.restaurant_menu), label: "Meal"),
            BottomNavigationBarItem(
                icon: Icon(Icons.fitness_center), label: "Workout"),
                BottomNavigationBarItem(
  icon: Icon(Icons.show_chart),
  label: "Progress",
),
BottomNavigationBarItem(
  icon: Icon(Icons.chat),
  label: "Chatbot",
),
BottomNavigationBarItem(
  icon: Icon(Icons.games),
  label: "Gamification",
),


          ],
        ),
      ),
    );
  }

  TextStyle infoStyle() => const TextStyle(color: Colors.white, fontSize: 16);

  Widget _buildCard({
    required String title,
    required Widget child,
    bool isLoading = false,
  }) {
    return Stack(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
        if (isLoading)
          const Positioned(
            top: 8,
            right: 8,
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }
  
Widget _drawerItem(IconData icon, String title, int index) {
  return ListTile(
    leading: Icon(icon, color: Colors.white),
    title: Text(
      title,
      style: const TextStyle(color: Colors.white),
    ),
    onTap: () {
      Navigator.pop(context); // close drawer
      setState(() {
        _selectedIndex = index;
      });
    },
  );
}}