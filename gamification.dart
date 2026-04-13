import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class GamificationPage extends StatefulWidget {
  const GamificationPage({super.key});

  @override
  State<GamificationPage> createState() => _GamificationPageState();
}

class _GamificationPageState extends State<GamificationPage> {
  final currentUser = FirebaseAuth.instance.currentUser;

  bool _isSyncing = false;

  int? _lastXp;
  int? _lastStreak;
  int? _lastFoodCount;
bool _isLoading = true;
  // Backend synced values
  int _serverLevel = 0;
  double _serverProgress = 0.0;
  int _serverXP = 0;

  Future<void> _syncGamificationToBackend(
    Map<String, dynamic> userData, int eatenFoodCount) async {
  final xp = userData["xp"] ?? 0;
  final streak = userData["streak"] ?? 0;
  final achievements =
      List<String>.from(userData["achievements_unlocked"] ?? []);

  if (_lastXp == xp && _lastStreak == streak && _lastFoodCount == eatenFoodCount) return;
  if (_isSyncing) return;

  _lastXp = xp;
  _lastStreak = streak;
  _lastFoodCount = eatenFoodCount;
  _isSyncing = true;

  try {
    final response = await http.post(
      Uri.parse("http://192.168.18.197:8000/gamification"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "uid": currentUser?.uid,
        "xp": xp,
        "streak": streak,
        "achievements": achievements,
        "eaten_foods": eatenFoodCount,
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
        await FirebaseFirestore.instance
    .collection("users")
    .doc(currentUser!.uid)
    .update({
  "streak": data["streak"],
  "last_active_date": data["last_active_date"],
  "current_badge": data["current_badge"],
  "xp": data["server_xp"],  // <--- save total XP
  "achievements_unlocked": data["all_achievements"], 
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
                  _buildHeroProgressPanel(),
                  const SizedBox(height: 25),
                  _buildConsistencyTracker(streakDays),
                  const SizedBox(height: 25),
                  _buildAchievementVault(unlockedBadges),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // ================= HERO XP PANEL =================
  Widget _buildHeroProgressPanel() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF2D3142),
        borderRadius: BorderRadius.circular(28),
      ),
     child: _isLoading
    ? const Center(
        child: CircularProgressIndicator(
          color: Colors.white,
        ),
      )
    : Column(
        children: [
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
                      Color(0xFF00C2FF)),
                ),
              ),
              Column(
                children: [
                  Text(
                    "$_serverLevel",
                    style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  const Text(
                    "LEVEL",
                    style:
                        TextStyle(color: Colors.white70, letterSpacing: 1.2),
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