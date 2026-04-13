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

  // Meal macros
  double? protein;
  double? carbs;
  double? fats;
  double? calories;
  final TextEditingController quantity = TextEditingController();
  // Predicted label and similarity
  String? predictedLabel;
  double? similarity;

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
      predictedLabel = null;
      similarity = null;
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
      final uri = Uri.parse("http://192.168.18.197:8000/meal_snap");
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
      request.fields['quantity_g'] = quantity.text.trim().isEmpty
          ? "100"
          : quantity.text;

      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = jsonDecode(body);

        setState(() {
          predictedLabel = data['predicted_label'] ?? "Image Not Found";
          similarity = (data['similarity'] as num?)?.toDouble() ?? 0.0;
          protein = (data['protein_g'] as num?)?.toDouble() ?? 0.0;
          carbs = (data['carbs_g'] as num?)?.toDouble() ?? 0.0;
          fats = (data['fat_g'] as num?)?.toDouble() ?? 0.0;
          calories = (data['calories'] as num?)?.toDouble() ?? 0.0;
        });
        if (quantity.text.trim().isEmpty) {
          await _autoFillQuantity();
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Meal analyzed successfully!")),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Upload failed: $body")));
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Something went wrong!")));
    }

    setState(() => uploading = false);
  }

  Future<List<dynamic>> _getTodayMeals() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('meal_plan')
        .doc('current_plan')
        .get();

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

  Future<void> _autoFillQuantity() async {
    if (predictedLabel == null) return;

    // ✅ DO NOT override if user already changed value
    if (quantity.text.trim().isNotEmpty) {
      return;
    }

    final foods = await _getTodayMeals();

    for (var item in foods) {
      final name = item['food_name'].toString().toLowerCase();
      final predicted = predictedLabel!.toLowerCase();

      if (name.contains(predicted) || predicted.contains(name)) {
        quantity.text = item['grams'].toString();
        return;
      }
    }
  }

  Future<void> _markMealAsEaten(bool eaten) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || predictedLabel == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('eaten_foods')
        .doc()
        .set({
          "quantity_g": double.tryParse(quantity.text) ?? 100,
          "food_name": predictedLabel,

          "calories": calories ?? 0,
          "protein_g": protein ?? 0,
          "carbs_g": carbs ?? 0,
          "fat_g": fats ?? 0,
          "consumed": eaten,
          "created_at": FieldValue.serverTimestamp(),
        });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          eaten ? "Meal marked as eaten 🍽️" : "Meal marked as not eaten ❌",
        ),
      ),
    );
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
  void initState() {
    quantity.addListener(() {
      if (quantity.text.trim().isEmpty) return;
      if (_debounce?.isActive ?? false) _debounce!.cancel();
      _debounce = Timer(const Duration(milliseconds: 500), () {
        if (predictedLabel != null) _uploadImage();
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

            // PREDICTED MEAL
            if (predictedLabel != null)
              Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Predicted Meal:",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          predictedLabel!,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),

                  Row(
                    children: [
                      // LEFT: Quantity Input
                      Expanded(
                        child: TextField(
                          controller: quantity,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: "Quantity (g)",
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // RIGHT: Eaten Button
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _markMealAsEaten(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text("Eaten"),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            const SizedBox(height: 8),

            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CheatMealScreen(
                      foodName: predictedLabel ?? "",
                      calories: calories ?? 0,
                      protein: protein ?? 0,
                      carbs: carbs ?? 0,
                      fats: fats ?? 0,
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text("Mark as Cheat Meal 🔥"),
            ),
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
