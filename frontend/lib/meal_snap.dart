import 'dart:convert';
import 'cheatmeal.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

class UploadMealScreen extends StatefulWidget {
  const UploadMealScreen({super.key});

  @override
  State<UploadMealScreen> createState() => _UploadMealScreenState();
}

class _UploadMealScreenState extends State<UploadMealScreen> {
  Uint8List? _webImage;
  File? _image;
  Timer? _debounce;
  String? _imagePath;

  bool uploading = false;
  bool hadError = false;

  // Meal macros
  double? protein;
  double? carbs;
  double? fats;
  double? calories;
  final TextEditingController quantity = TextEditingController();
  // Predicted label and similarity
List<Map<String, dynamic>> detectedItems = [];

List<TextEditingController> itemQuantities = [];

  final ImagePicker picker = ImagePicker();

  // ============================
  // Select Image Source
  // ============================
  Future<void> _selectImageSource() async {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text("Camera"),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text("Gallery"),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ============================
  // Pick Image
  // ============================
  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await picker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );

    if (pickedFile == null) return;

    if (kIsWeb) {
      _webImage = await pickedFile.readAsBytes();
      _imagePath =
          "web_${DateTime.now().millisecondsSinceEpoch}_${pickedFile.name}";
    } else {
      _image = File(pickedFile.path);
      _imagePath = pickedFile.path;
    }

    setState(() {
  protein = carbs = fats = calories = null;
  detectedItems = [];
itemQuantities = [];
hadError = false;
});
  }

  // ============================
  // Upload Image to Backend
  // ============================
  Future<void> _uploadImage() async {
    if (uploading) return;
    if (_image == null && _webImage == null) return;

    setState(() => uploading = true);

    try {
      final uri = Uri.parse("https://nutrifit-backend-production-1761.up.railway.app/meal_snap");
      //final uri = Uri.parse("http://192.168.18.197:8000/meal_snap");
      final request = http.MultipartRequest('POST', uri);

      // Attach image
      if (kIsWeb && _webImage != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'meal_image',
            _webImage!,
            filename: "upload_${DateTime.now().millisecondsSinceEpoch}.jpg",
          ),
        );
      } else if (_image != null) {
        request.files.add(
          await http.MultipartFile.fromPath('meal_image', _image!.path),
        );
      }

      request.fields['image_path'] = _imagePath ?? '';
      if (quantity.text.trim().isNotEmpty) {
  request.fields['quantity_g'] = quantity.text;
}

      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = jsonDecode(body);

     final todayFoods = await _getTodayMeals(); 
      if (!mounted) return;
setState(() {
  hadError = false;
  detectedItems = List<Map<String, dynamic>>.from(data['items'] ?? []);
  if (itemQuantities.isEmpty) {
    itemQuantities = List.generate(
    detectedItems.length,
    (i) {
      final detectedName = (detectedItems[i]['predicted_label'] ?? '').toLowerCase().trim();

      // Meal plan mein same food dhundo
      final matchedFood = todayFoods.firstWhere(
        (f) => (f['food_name'] ?? '').toString().toLowerCase().trim() == detectedName,
        orElse: () => null,
      );

      // Agar meal plan mein mila toh uski quantity use karo, warna CSV wali
      final defaultQty = matchedFood != null
          ? (matchedFood['quantity'] ?? detectedItems[i]['quantity'] ?? '1').toString()
          : (detectedItems[i]['quantity'] ?? '1').toString();

      final controller = TextEditingController(text: defaultQty);
      controller.addListener(() {
        double totalCal = 0, totalProtein = 0, totalCarbs = 0, totalFat = 0;
        for (int j = 0; j < detectedItems.length; j++) {
          final item = detectedItems[j];
          final csvQty = (item['quantity'] as num?)?.toDouble() ?? 100.0;
          final enteredQty = double.tryParse(itemQuantities[j].text) ?? csvQty;
          final factor = enteredQty / csvQty;
          totalCal     += ((item['calories']  as num?)?.toDouble() ?? 0) * factor;
          totalProtein += ((item['protein_g'] as num?)?.toDouble() ?? 0) * factor;
          totalCarbs   += ((item['carbs_g']   as num?)?.toDouble() ?? 0) * factor;
          totalFat     += ((item['fat_g']     as num?)?.toDouble() ?? 0) * factor;
        }
        if (!mounted) return;
        setState(() {
          calories = totalCal;
          protein  = totalProtein;
          carbs    = totalCarbs;
          fats     = totalFat;
        });
      });
      return controller;
    },
  );
}
// Initial macros — CSV values as-is
protein   = detectedItems.fold<double>(0.0, (s, i) => s + ((i['protein_g'] as num?)?.toDouble() ?? 0.0));
carbs     = detectedItems.fold<double>(0.0, (s, i) => s + ((i['carbs_g']   as num?)?.toDouble() ?? 0.0));
fats      = detectedItems.fold<double>(0.0, (s, i) => s + ((i['fat_g']     as num?)?.toDouble() ?? 0.0));
calories  = detectedItems.fold<double>(0.0, (s, i) => s + ((i['calories']  as num?)?.toDouble() ?? 0.0));
});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Meal analyzed successfully!")),
        );
    } else if (response.statusCode == 499) {
        if (mounted) {
          setState(() => hadError = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Connection timed out. Try again.")),
          );
        }
      } else {
        if (mounted) setState(() => hadError = true);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Upload failed: $body")));
      }
    } catch (e) {
      if (mounted) {
        setState(() => hadError = true);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Something went wrong. Try again.")));
      }
    } finally {
      if (mounted) setState(() => uploading = false); // ✅
    }
  }

  Future<List<dynamic>> _getTodayMeals() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    final doc = await FirebaseFirestore.instance
    .collection('users')
    .doc(user.uid)
    .collection('meal_plan')
    .doc('current_plan')
    .get(GetOptions(source: Source.cache))
    .catchError((_) => FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('meal_plan')
        .doc('current_plan')
        .get(GetOptions(source: Source.server)));

    if (!doc.exists) return [];

    final plan = doc.data()?['plan'] ?? {};

    final daysOrder = [
      "Monday",
      "Tuesday",
      "Wednesday",
      "Thursday",
      "Friday",
      "Saturday",
      "Sunday",
    ];

    final today = daysOrder[DateTime.now().weekday - 1];

    final todayMeals = plan[today]?['meals'] ?? {};

    List<dynamic> allFoods = [];

    for (var meal in todayMeals.values) {
      allFoods.addAll(meal['items'] ?? []);
    }

    return allFoods;
  }

  
  Future<double> _getDailyCaloriesTarget(String uid) async {
    try {
      final mealPlanDoc = await FirebaseFirestore.instance
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

      if (!mealPlanDoc.exists) return 2000;
      final plan = mealPlanDoc.data()?['plan'] as Map<String, dynamic>? ?? {};
      final firstDay = plan.values.isNotEmpty ? plan.values.first : null;
      if (firstDay != null && firstDay is Map) {
        return (firstDay['predicted_daily_calories'] ?? 2000).toDouble();
      }
    } catch (_) {}
    return 2000;
  }

  Future<double> _getTodayEatenCalories(String uid) async {
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('eaten_foods')
          .where('consumed', isEqualTo: true)
          .get();

      double total = 0;
      for (var doc in snapshot.docs) {
        final ts = doc['created_at'];
        if (ts != null && ts is Timestamp) {
          if (ts.toDate().isAfter(startOfDay)) {
            total += (doc['calories'] ?? 0).toDouble();
          }
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _markMealAsEaten(bool eaten) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || detectedItems.isEmpty) return;

   for (int idx = 0; idx < detectedItems.length; idx++) {
  final item = detectedItems[idx];
  final csvQty = (item['quantity'] as num?)?.toDouble() ?? 100.0;
  final enteredQty = double.tryParse(itemQuantities[idx].text) ?? csvQty;
  final factor = csvQty > 0 ? enteredQty / csvQty : 1.0;

  await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('eaten_foods')
      .doc()
      .set({
        "quantity_g": enteredQty,
        "unit": item['unit'] ?? 'g',
        "food_name": item['predicted_label'] ?? '',
        "calories": ((item['calories']  as num?)?.toDouble() ?? 0) * factor,
        "protein_g": ((item['protein_g'] as num?)?.toDouble() ?? 0) * factor,
        "carbs_g":   ((item['carbs_g']   as num?)?.toDouble() ?? 0) * factor,
        "fat_g":     ((item['fat_g']     as num?)?.toDouble() ?? 0) * factor,
        "consumed": eaten,
        "created_at": FieldValue.serverTimestamp(),
      });
}
    if (!eaten || !mounted) return;

    // Cheat detection: check if today's total calories exceed daily target
    final dailyTarget = await _getDailyCaloriesTarget(user.uid);
    final todayEaten = await _getTodayEatenCalories(user.uid);
    final newTotal = todayEaten + (calories ?? 0);
    final threshold = dailyTarget * 1.15; // 15% over target = cheat

    if (newTotal >= threshold && mounted) {
      // It's a cheat! Navigate to CheatMealScreen automatically
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⚠️ Cheat meal detected! Generating compensation plan..."),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CheatMealScreen(
              foodName: detectedItems.map((i) => i['predicted_label']).join(', '),
              calories: calories ?? 0,
              protein: protein ?? 0,
              carbs: carbs ?? 0,
              fats: fats ?? 0,
              autoSave: true,
            ),
          ),
        );
      }
      return;
    }

    // Normal eaten — just show snackbar
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            eaten ? "Meal marked as eaten 🍽️" : "Meal marked as not eaten ❌",
          ),
        ),
      );
    }
  }

  // ============================
  // Macros Card Widget
  // ============================
  Widget _buildMacrosCard(
    String label,
    double? value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              value != null ? value.toStringAsFixed(1) : "-",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================
  // Progress Card Widget
  // ============================
  Widget _buildProgressCard(String title, double progress, Color color) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              backgroundColor: color.withOpacity(0.3),
              valueColor: AlwaysStoppedAnimation(color),
            ),
            const SizedBox(height: 8),
            Text("${(progress * 100).toStringAsFixed(0)}% completed"),
          ],
        ),
      ),
    );
  }

  @override
 
void dispose() {
  for (final c in itemQuantities) c.dispose();
  quantity.dispose();
  _debounce?.cancel();
  super.dispose();
}
 @override
  void initState() {
    quantity.addListener(() {
      if (quantity.text.trim().isEmpty) return;
      if (_debounce?.isActive ?? false) _debounce!.cancel();
      _debounce = Timer(const Duration(milliseconds: 500), () {
        if (detectedItems.isNotEmpty) _uploadImage();
      });
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.grey,
        title: const Text("Upload Meal", style: TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // IMAGE PREVIEW
            Container(
              height: 300,
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black26),
                borderRadius: BorderRadius.circular(16),
              ),
              child: _image == null && _webImage == null
                  ? const Center(
                      child: Text(
                        "No Image Selected",
                        style: TextStyle(color: Colors.black54),
                      ),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: kIsWeb
                          ? Image.memory(_webImage!, fit: BoxFit.cover)
                          : Image.file(_image!, fit: BoxFit.cover),
                    ),
            ),

            const SizedBox(height: 20),

            // SELECT (Camera / Gallery)
            ElevatedButton.icon(
              onPressed: _selectImageSource,
              icon: const Icon(Icons.add_a_photo),
              label: const Text("Select / Capture Meal Image"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                minimumSize: const Size(double.infinity, 50),
              ),
            ),

            const SizedBox(height: 16),

            ElevatedButton.icon(
              onPressed: (uploading || (_image == null && _webImage == null))
                  ? null
                  : _uploadImage,
              icon: uploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.cloud_upload),
              label: Text(uploading ? "Analyzing..." : "Analyze Meal"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                minimumSize: const Size(double.infinity, 50),
              ),
            ),

            const SizedBox(height: 20),

  
if (detectedItems.isEmpty && (_image != null || _webImage != null) && !uploading && !hadError)
  const Text(
    "Food not found",
    style: TextStyle(color: Colors.red, fontSize: 16, fontWeight: FontWeight.bold),
  ),

if (hadError && (_image != null || _webImage != null) && !uploading)
  const Text(
    "Something went wrong. Try again.",
    style: TextStyle(color: Colors.red, fontSize: 16, fontWeight: FontWeight.bold),
  ),

if (detectedItems.isNotEmpty)
  Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        "${detectedItems.length} food item(s) detected",
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      ...detectedItems.asMap().entries.map((entry) {
  final idx = entry.key;
  final item = entry.value;
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: Colors.black12,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item['predicted_label'] ?? '',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          "Cal: ${item['calories']}  •  P: ${item['protein_g']}g  •  C: ${item['carbs_g']}g  •  F: ${item['fat_g']}g",
          style: const TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: itemQuantities[idx],
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
          labelText: "Quantity (${item['unit'] ?? 'g'})",
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    ),
  );
}),
      const SizedBox(height: 12),
      const SizedBox(height: 8),
SizedBox(
  width: double.infinity,
  child: ElevatedButton(
    onPressed: () => _markMealAsEaten(true),
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.green,
      padding: const EdgeInsets.symmetric(vertical: 16),
    ),
    child: const Text("Eaten"),
  ),
),
      const SizedBox(height: 16),
    ],
  ),
            const SizedBox(height: 8),


            // MACROS CARDS
            Column(
              children: [
                Row(
                  children: [
                    _buildMacrosCard(
                      "Calories",
                      calories,
                      Icons.fastfood,
                      Colors.blue,
                    ),
                    const SizedBox(width: 8),
                    _buildMacrosCard(
                      "Protein",
                      protein,
                      Icons.accessibility,
                      Colors.green,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildMacrosCard(
                      "Carbs",
                      carbs,
                      Icons.restaurant,
                      Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    _buildMacrosCard(
                      "Fats",
                      fats,
                      Icons.monitor_weight,
                      Colors.red,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}