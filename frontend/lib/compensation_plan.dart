import 'package:flutter/material.dart';

class CompensationPlan extends StatelessWidget {
  
  final List<dynamic> plan;

  const CompensationPlan({
    super.key,
    required this.plan,
  });


  String _getDayName(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      const days = [
        "Monday", "Tuesday", "Wednesday", "Thursday",
        "Friday", "Saturday", "Sunday",
      ];
      return days[date.weekday - 1];
    } catch (_) {
     
      return dateString; 
    }
  }
  List _filterMeals(List meals, String type) {
    return meals
        .where((m) =>
            m['meal_type']?.toString().toLowerCase() == type.toLowerCase())
        .toList();
  }

  
  Widget _buildMealSection(String title, List meals) {
    if (meals.isEmpty) return const SizedBox();

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
          Text(
            title,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.blue),
          ),
          const SizedBox(height: 8),
          ...meals.map((meal) => _mealCard(meal)),
        ],
      ),
    );
  }

  Widget _mealCard(dynamic meal) {
    final num calories =
        (meal['adjusted_calories'] ?? meal['calories'] ?? 0) as num;

    
    final bool isFasting = calories == 0;
String fmt(dynamic v) =>
        v == null ? '0' : (v as num).toStringAsFixed(1);

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
      child: isFasting
          ? Row(
              children: const [
                Icon(Icons.no_meals, color: Colors.grey),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Fasting — skip this meal (16:8 protocol)",
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meal['meal_type'].toString().toUpperCase(),
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black),
                ),
                
                if ((meal['note']?.toString() ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 4),
                    child: Text(
                      meal['note'].toString(),
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black54),
                    ),
                  ),
                const SizedBox(height: 8),
                _foodDetail(Icons.local_fire_department,
                    "${calories.toStringAsFixed(1)} kcal", "Calories"),
                _foodDetail(Icons.egg_alt,
                    "${fmt(meal['protein_g'])} g", "Protein"),
                _foodDetail(Icons.rice_bowl,
                    "${fmt(meal['carbs_g'])} g", "Carbs"),
                _foodDetail(Icons.opacity,
                    "${fmt(meal['fat_g'])} g", "Fats"),
              ],
            ),
    );
  }

  Widget _foodDetail(IconData icon, String value, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.blue),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 12, color: Colors.black54)),
              Text(value,
                  style: const TextStyle(
                      fontSize: 14, color: Colors.black87)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDayCard(Map<String, dynamic> day) {
    final List meals     = (day['meals']    as List?) ?? [];
    final int workout    = (day['extra_workout_min'] as num?)?.toInt() ?? 0;

    final String dayNote = day['day_note']?.toString() ??
                           day['note']?.toString() ?? '';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
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
                _getDayName(day['date']?.toString() ?? ''),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            day['date']?.toString() ?? '',
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(height: 12),

          _buildMealSection("Breakfast", _filterMeals(meals, "breakfast")),
          _buildMealSection("Lunch",     _filterMeals(meals, "lunch")),
          _buildMealSection("Dinner",    _filterMeals(meals, "dinner")),

          const SizedBox(height: 12),

          if (workout > 0)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.fitness_center, color: Colors.orange),
                  const SizedBox(width: 10),
                  Text(
                    "$workout min cardio",
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),

          if (dayNote.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                dayNote,
                style: const TextStyle(
                    fontSize: 12, color: Colors.black54),
              ),
            ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {


    if (plan.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          title: const Text(
            "Compensation Plan",
            style: TextStyle(
                color: Colors.black, fontWeight: FontWeight.bold),
          ),
          iconTheme: const IconThemeData(color: Colors.black),
        ),
        body: const Center(child: Text("No compensation plan available")),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text(
          "Compensation Plan",
          style: TextStyle(
              color: Colors.black, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: plan.length,
        separatorBuilder: (_, __) => const Divider(
            thickness: 3, color: Colors.blue, height: 32),
        itemBuilder: (context, index) {
          final day = plan[index];
          if (day is Map<String, dynamic>) {
            return _buildDayCard(day);
          }
         
          return _buildDayCard(
              Map<String, dynamic>.from(day as Map));
        },
      ),
    );
  }
}