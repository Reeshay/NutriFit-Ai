import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:nutrifit/notification.dart';

class GamificationPage extends StatefulWidget {
  const GamificationPage({super.key});

  @override
  State<GamificationPage> createState() => _GamificationPageState();
}

class _GamificationPageState extends State<GamificationPage> {
  final currentUser = FirebaseAuth.instance.currentUser;
final NotificationService notificationService = NotificationService();
  bool _isSyncing = false;

  int? _lastXp;
  int? _lastStreak;
  int? _lastFoodCount;
bool _isLoading = true;
  // Backend synced values
  int _serverLevel = 0;
  double _serverProgress = 0.0;
  int _serverXP = 0;
void _sendMotivationalNotification({
  List<String> newAchievements = const [],
  int? level,
  String? badge,
}) {
  String title;
  String message;

  if (newAchievements.isNotEmpty) {
    // Priority: naya achievement unlock hua
    final badgeName = newAchievements.first;
    title = "Achievement Unlocked! 🏆";
    message = _achievementMessage(badgeName);
  } else {
    // Fallback: streak-based motivation
    final streak = _lastStreak ?? 0;
    title = "Keep Going! 🔥";
    if (streak <= 0) {
      message = "Start your streak today — log a meal and take the first step!";
    } else if (streak < 7) {
      message = "You're on a $streak-day streak — don't break it now!";
    } else if (streak < 30) {
      message = "$streak days strong! Your consistency is paying off.";
    } else {
      message = "$streak-day streak! You're a NutriFit champion 🏆";
    }
  }

  notificationService.showNotification(title, message, const Duration(seconds: 1));
}

String _achievementMessage(String badgeId) {
  if (badgeId == "gold" || badgeId == "silver" || badgeId == "bronze") {
    return "You've reached ${badgeId[0].toUpperCase()}${badgeId.substring(1)} tier! Your hard work is showing.";
  }
  if (badgeId.startsWith("streak_")) {
    final days = badgeId.split("_")[1];
    return "$days-day streak milestone reached! Amazing consistency.";
  }
  if (badgeId.startsWith("food_")) {
    final count = badgeId.split("_")[1];
    return "You've logged $count meals! Tracking is the key to results.";
  }
  return "You've unlocked a new achievement!";
}
  Future<void> _syncGamificationToBackend(
    Map<String, dynamic> userData, int eatenFoodCount) async {
  final xp = userData["xp"] ?? 0;
  final streak = userData["streak"] ?? 0;
  final achievements =
      List<String>.from(userData["achievements_unlocked"] ?? []);

  final matchedFoodCount = userData["matchedFoodCount"] ?? 0;
  final unmatchedFoodCount = userData["unmatchedFoodCount"] ?? 0;
  final lastSyncedExerciseMinutes =
      (userData["last_synced_exercise_minutes"] ?? 0).toDouble();

  // Total exercise minutes from exercise_videos collection
  double exerciseMinutes = 0.0;
  try {
    final videosSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser!.uid)
        .collection('exercise_videos')
        .get();

    double totalHours = 0.0;
    for (var doc in videosSnap.docs) {
      totalHours += (doc.data()['duration'] ?? 0).toDouble();
    }
    exerciseMinutes = totalHours * 60;
  } catch (e) {
    debugPrint("Failed to fetch exercise videos: $e");
  }

  if (_lastXp == xp && _lastStreak == streak && _lastFoodCount == eatenFoodCount) return;
  if (_isSyncing) return;

  _lastXp = xp;
  _lastStreak = streak;
  _lastFoodCount = eatenFoodCount;
  _isSyncing = true;

  try {
    final response = await http.post(
      Uri.parse("https://nutrifit-backend-production-1761.up.railway.app/gamification"),
      //Uri.parse("http://192.168.18.197:8000/gamification"),
      headers: {"Content-Type": "application/json"},
     body: jsonEncode({
  "uid": currentUser?.uid,
  "xp": xp,
  "streak": streak,
  "achievements": achievements,
  "matched_foods": matchedFoodCount,
  "unmatched_foods": unmatchedFoodCount,
  "last_synced_matched": userData["last_synced_matched"] ?? 0,
  "last_synced_unmatched": userData["last_synced_unmatched"] ?? 0,
  "exercise_minutes": exerciseMinutes,
  "last_synced_exercise_minutes": lastSyncedExerciseMinutes,
  "last_active_date": userData["last_active_date"]
}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      if (data["status"] == "success") {
        setState(() {
          _serverLevel = data["server_level"];
          _serverProgress = (data["level_progress"] as double).clamp(0.0, 1.0);
          _serverXP = data["server_xp"] ?? xp; 
          _isLoading = false;
        });
        _sendMotivationalNotification(
  newAchievements: List<String>.from(data["new_achievements"] ?? []),
  level: data["server_level"],
  badge: data["current_badge"],
);
        await FirebaseFirestore.instance
    .collection("users")
    .doc(currentUser!.uid)
    .update({
  "streak": data["streak"],
  "last_active_date": data["last_active_date"],
  "current_badge": data["current_badge"],
  "xp": data["server_xp"],  
  "achievements_unlocked": data["all_achievements"],
  "last_synced_matched": data["last_synced_matched"],
  "last_synced_unmatched": data["last_synced_unmatched"],
  "last_synced_exercise_minutes": data["last_synced_exercise_minutes"],
});
      }

    }
  } catch (e) {
    debugPrint("Gamification sync failed: $e");
  }

  _isSyncing = false;
}
  @override
  Widget build(BuildContext context) {
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "Gamification",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection("users")
            .doc(currentUser!.uid)
            .snapshots(),
        builder: (context, userSnapshot) {
          if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
            return const Center(child: CircularProgressIndicator());
          }

          final userInfo =
              userSnapshot.data!.data() as Map<String, dynamic>;
              final badge = userInfo["current_badge"] ?? "";

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection("users")
                .doc(currentUser!.uid)
                .collection("eaten_foods")
                .snapshots(),
            builder: (context, foodSnapshot) {
              if (!foodSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final eatenFoodCount = foodSnapshot.data!.docs.length;

              // Schedule backend sync after build
              Future.microtask(() => _syncGamificationToBackend(userInfo, eatenFoodCount));

              final streakDays = userInfo["streak"] ?? 0;
              final unlockedBadges = userInfo["achievements_unlocked"] ?? [];

              return ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  _buildHeroProgressPanel(badge),
                  const SizedBox(height: 25),
                  _buildConsistencyTracker(streakDays),
                  const SizedBox(height: 25),
                  _buildAchievementVault(unlockedBadges),
                  const SizedBox(height: 25),
                  _buildLeaderboard(),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // ================= HERO XP PANEL =================
  Widget _buildHeroProgressPanel(String badge) {
  return Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: const Color(0xFF2D3142),
      borderRadius: BorderRadius.circular(28),
    ),
    child: _isLoading
        ? const Center(
            child: CircularProgressIndicator(color: Colors.white),
          )
        : Column(
            children: [
              
              // ✅ BADGE (FIXED)
              if (badge.isNotEmpty &&
                  ["bronze", "silver", "gold"].contains(badge))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Image.asset(
                    "images/$badge.png",
                    width: 50,
                    height: 50,
                  ),
                ),

              const Text(
                "Performance Level",
                style: TextStyle(color: Colors.white70),
              ),

              const SizedBox(height: 18),

              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    height: 130,
                    width: 130,
                    child: CircularProgressIndicator(
                      value: _serverProgress,
                      strokeWidth: 12,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF00C2FF),
                      ),
                    ),
                  ),
                  Column(
                    children: [
                      Text(
                        "$_serverLevel",
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const Text(
                        "LEVEL",
                        style: TextStyle(
                          color: Colors.white70,
                          letterSpacing: 1.2,
                        ),
                      )
                    ],
                  )
                ],
              ),

              const SizedBox(height: 16),

              Text(
                "$_serverXP Experience Points",
                style: const TextStyle(color: Colors.white),
              )
            ],
          ),
  );
}
  // ================= STREAK =================
  Widget _buildConsistencyTracker(int streak) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 15,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: Color(0xFFFFE8D6),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.whatshot_rounded,
              color: Color(0xFFFF6B00),
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Consistency Streak",
                style: TextStyle(fontSize: 14, color: Colors.black54),
              ),
              Text(
                "$streak Active Days",
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w600),
              )
            ],
          )
        ],
      ),
    );
  }

  // ================= ACHIEVEMENTS =================
  Widget _buildAchievementVault(List unlocked) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection("achievements").snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final allAchievements = snapshot.data!.docs;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: allAchievements.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 1,
          ),
          itemBuilder: (context, index) {
            final achievementData =
                allAchievements[index].data() as Map<String, dynamic>;

            final badgeId = allAchievements[index].id;
            final unlockedStatus = unlocked.contains(badgeId);

            return _achievementTile(achievementData["title"] ?? "", unlockedStatus);
          },
        );
      },
    );
  }
Widget _buildLeaderboard() {
  return StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance
        .collection("users")
        .orderBy("xp", descending: true)
        
        .snapshots(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }

      final users = snapshot.data!.docs;

      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 15,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
  children: const [
    Icon(Icons.emoji_events, color: Colors.amber),
    SizedBox(width: 8),
    Text(
      "Leaderboard",
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    ),
  ],
),
            const SizedBox(height: 16),

            ListView.builder(
              
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: users.length,
              itemBuilder: (context, index) {
                final user = users[index].data() as Map<String, dynamic>;

                final name = user["name"] ?? "User";
                final xp = user["xp"] ?? 0;
                final isMe = users[index].id == currentUser?.uid;
final badge = user["current_badge"] ?? "";
                return Container(
  decoration: BoxDecoration(
    
    border: isMe
        ? Border.all(color: Colors.green, width: 2)
        : null,
    borderRadius: BorderRadius.circular(14),
  ),
  child: _leaderboardTile(index + 1, name, xp, badge),
);
              },
            )
          ],
        ),
      );
    },
  );
}
Widget _leaderboardTile(int rank, String name, int xp, String badge) {

  Color rankColor;
  IconData? medalIcon;

  if (rank == 1) {
    rankColor = Colors.amber;
    medalIcon = Icons.emoji_events;
  } else if (rank == 2) {
    rankColor = Colors.grey;
    medalIcon = Icons.emoji_events;
  } else if (rank == 3) {
    rankColor = Colors.brown;
    medalIcon = Icons.emoji_events;
  } else {
    rankColor = Colors.black;
  }
Color badgeColor;
IconData badgeIcon = Icons.workspace_premium;

switch (badge) {
  case "gold":
    badgeColor = Colors.amber;
    badgeIcon = Icons.emoji_events;
    break;
  case "silver":
    badgeColor = Colors.grey;
    badgeIcon = Icons.emoji_events;
    break;
  case "bronze":
    badgeColor = const Color(0xFFCD7F32);
    badgeIcon = Icons.emoji_events;
    break;
  default:
    badgeColor = Colors.grey;
}
  return Container(
    margin: const EdgeInsets.symmetric(vertical: 6),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: rank <= 3
          ? rankColor.withOpacity(0.1)
          : Colors.grey.withOpacity(0.05),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Row(
  children: [
    // Rank medal
    medalIcon != null
        ? Icon(medalIcon, color: rankColor)
        : Text(
            "#$rank",
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),

    const SizedBox(width: 8),

    if (badge.isNotEmpty &&
    ["bronze", "silver", "gold"].contains(badge))
  Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: badgeColor, width: 1.5),
    ),
    child: Image.asset(
      "images/$badge.png",
      width: 22,
      height: 22,
      fit: BoxFit.contain,
    ),
  ),
  ],
),
            
        const SizedBox(width: 12),

        // Avatar
        CircleAvatar(
          backgroundColor: const Color(0xFF2D3142),
          child: Text(
            name[0].toUpperCase(),
            style: const TextStyle(color: Colors.white),
          ),
        ),

        const SizedBox(width: 12),

        // Name
        Expanded(
          child: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),

        // XP
        Text(
          "$xp XP",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: rank <= 3 ? rankColor : const Color(0xFF00A86B),
          ),
        )
      ],
    ),
  );
}
  
  Widget _achievementTile(String title, bool unlocked) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: unlocked ? const Color(0xFFE6F9F0) : const Color(0xFFF0F0F0),
      ),
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.workspace_premium,
                  size: 34,
                  color: unlocked ? const Color(0xFF00A86B) : Colors.grey,
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: unlocked ? Colors.black87 : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          if (!unlocked)
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.45),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Center(
                child: Icon(
                  Icons.lock_outline,
                  color: Colors.white,
                ),
              ),
            )
        ],
      ),
    );
  }
}