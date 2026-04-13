import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'package:path/path.dart' as path;
class ExerciseVideo extends StatefulWidget {
  const ExerciseVideo({super.key});

  @override
  State<ExerciseVideo> createState() => _ExerciseVideoState();
}

class _ExerciseVideoState extends State<ExerciseVideo> {
  User? user;

  CameraController? _cameraController;
  bool _isBusy = false;
  bool _isCameraInitialized = false;
  bool _isRecording = false;
  bool _isUploading = false;
  String? _recordedVideoPath;
  List<CameraDescription> _cameras = [];
  DateTime? _recordingStartTime;

  // ---- Exercise selection ----
  String _selectedExercise = "bench"; // bench | deadlift | squat
  final ImagePicker _picker = ImagePicker();

  // ---- Backend result state ----
  // These fields are updated after the backend processes the video.
  // They are displayed as an overlay on the camera preview.
  String _statusMessage = "Ready to record";
  String _poseLabel     = "";
  String _suggestion    = "";
  int    _reps          = 0;
  double _confidence    = 0.0;

  @override
  void initState() {
    super.initState();
    user = FirebaseAuth.instance.currentUser;
    _initCamera();
  }

  // ---------------------------------------------------------------
  // CAMERA INIT
  // ---------------------------------------------------------------
  // Fetches all available cameras and initialises the first one
  // (rear camera) at high resolution with audio enabled.
  // ---------------------------------------------------------------
  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;

      _cameraController = CameraController(
        _cameras[0],
        ResolutionPreset.high,
        enableAudio: true,
      );

      await _cameraController!.initialize();

      if (!mounted) return;
      setState(() {
        _isCameraInitialized = true;
      });
    } catch (e) {
      debugPrint("Camera error: $e");
    }
  }

  // ---------------------------------------------------------------
  // SWITCH CAMERA
  // ---------------------------------------------------------------
  // Toggles between front and rear cameras if more than one is
  // available. Disposes the current controller before switching.
  // ---------------------------------------------------------------
  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;

    final currentIndex = _cameras.indexOf(_cameraController!.description);
    final newIndex     = (currentIndex + 1) % _cameras.length;

    await _cameraController?.dispose();

    _cameraController = CameraController(
      _cameras[newIndex],
      ResolutionPreset.high,
      enableAudio: true,
    );

    await _cameraController!.initialize();

    if (!mounted) return;
    setState(() {});
  }

  // ---------------------------------------------------------------
  // START RECORDING
  // ---------------------------------------------------------------
  // Starts video recording and resets all backend result fields
  // so the UI is clean for the new recording session.
  // ---------------------------------------------------------------
  Future<void> _startRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      debugPrint("Camera not ready");
      return;
    }

    try {
      await _cameraController!.startVideoRecording();

      setState(() {
        _isRecording      = true;
        _recordedVideoPath = null;
        _statusMessage    = "Recording...";
        _poseLabel        = "";
        _suggestion       = "";
        _reps             = 0;
        _confidence       = 0.0;
      });

      debugPrint("Recording STARTED ✅");
      _recordingStartTime = DateTime.now();
    } catch (e) {
      debugPrint("Start error: $e");
    }
  }

  // ---------------------------------------------------------------
  // STOP RECORDING
  // ---------------------------------------------------------------
  // Stops recording, saves the file path, and immediately uploads
  // the video to the Flask backend for processing.
  // ---------------------------------------------------------------
  Future<void> _stopRecording() async {
    if (_cameraController == null) return;

    try {
      final file = await _cameraController!.stopVideoRecording();

      final durationInHours = _recordingStartTime != null
          ? DateTime.now().difference(_recordingStartTime!).inSeconds / 3600
          : 0.0;

      setState(() {
        _isRecording       = false;
        _recordedVideoPath = file.path;
        _statusMessage     = "Uploading video...";
        _isUploading       = true;
      });

      await _sendToBackend(file.path, durationInHours);
    } catch (e) {
      debugPrint("Stop error: $e");
    }
  }
  Future<void> _pickFromGallery() async {
  if (_isUploading || _isRecording) return;
  try {
    final XFile? picked = await _picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() {
      _recordedVideoPath = picked.path;
      _statusMessage     = "Uploading video...";
      _isUploading       = true;
      _poseLabel         = "";
      _suggestion        = "";
      _reps              = 0;
      _confidence        = 0.0;
    });
    await _sendToBackend(picked.path, 0.0);
  } catch (e) {
    setState(() {
      _isUploading   = false;
      _statusMessage = "Gallery error: $e";
    });
  }
}
  Future<void> _sendToBackend(String videoPath, double duration) async {
  try {
    final uri = Uri.parse("http://192.168.18.197:8000/exercise_video");

    var request = http.MultipartRequest("POST", uri);

    request.files.add(
      await http.MultipartFile.fromPath("video", videoPath),
    );

    request.fields["userId"]    = user?.uid ?? "";
    request.fields["createdAt"] = DateTime.now().toIso8601String();
    request.fields["duration"]  = duration.toStringAsFixed(2);
    request.fields["exercise"]  = _selectedExercise;

    final response     = await request.send();
    final responseBody = await response.stream.bytesToString();

    final data = jsonDecode(responseBody);

    // SAVE TO FIRESTORE HERE
    final uid = user?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('exercise_videos')
          .add({
        "duration": duration, // in hours
        "createdAt": FieldValue.serverTimestamp(),
        "reps": data["reps"] ?? 0,
        "pose": data["pose"] ?? "",
      });
    }

    setState(() {
      _isUploading   = false;
      _statusMessage = data["status"] ?? "Done";
      _reps          = data["reps"] ?? 0;
      _confidence    = (data["confidence"] ?? 0).toDouble();
      _poseLabel     = data["pose"] ?? "";
      _suggestion    = data["suggestion"] ?? "";
    });

  } catch (e) {
    setState(() {
      _isUploading   = false;
      _statusMessage = "Backend error: $e";
    });
  }
}
  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Record Exercise"),
        backgroundColor: Colors.grey,
        actions: [
          IconButton(
  icon: const Icon(Icons.video_library),
  tooltip: "Upload from gallery",
  onPressed: (_isRecording || _isUploading) ? null : _pickFromGallery,
),
          // Exercise type selector
          DropdownButton<String>(
            value: _selectedExercise,
            dropdownColor: Colors.grey[800],
            underline: const SizedBox(),
            style: const TextStyle(color: Colors.white, fontSize: 13),
            items: const [
              DropdownMenuItem(value: "bench",    child: Text("Bench Press")),
              DropdownMenuItem(value: "deadlift", child: Text("Deadlift")),
              DropdownMenuItem(value: "squat",    child: Text("Squat")),
            ],
            onChanged: _isRecording ? null : (val) {
              if (val != null) setState(() => _selectedExercise = val);
            },
          ),
          const SizedBox(width: 8),
          // Switch camera button — only shown if multiple cameras exist
          if (_isCameraInitialized && _cameras.length > 1)
            IconButton(
              icon: const Icon(Icons.flip_camera_android),
              onPressed: _switchCamera,
            ),
        ],
      ),
      body: Stack(
        children: [

          // ---- CAMERA PREVIEW ----
          // Full screen camera preview. Shows a loading spinner
          // until the camera is initialised.
          Positioned.fill(
            child: _isCameraInitialized
                ? CameraPreview(_cameraController!)
                : const Center(child: CircularProgressIndicator()),
          ),

          // ---- BACKEND RESULT OVERLAY ----
          // Displayed at the top of the screen. Shows the current
          // status, rep count, confidence, detected pose, and any
          // form correction suggestion from the backend.
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // Status / upload indicator
                  Row(
                    children: [
                      if (_isUploading)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          _statusMessage,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Rep count and confidence — shown after backend responds
                  if (_reps > 0 || _confidence > 0) ...[
                    const SizedBox(height: 8),
                    const Divider(color: Colors.white24, height: 1),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Reps counter
                        _statChip(
                          label: "Reps",
                          value: "$_reps",
                          color: Colors.greenAccent,
                        ),
                        // Confidence score
                        _statChip(
                          label: "Confidence",
                          value: "${(_confidence * 100).toStringAsFixed(0)}%",
                          color: Colors.orangeAccent,
                        ),
                      ],
                    ),
                  ],

                  // Last detected pose class — shown after backend responds
                  if (_poseLabel.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.accessibility_new,
                            color: Colors.lightBlueAccent, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          "Pose: $_poseLabel",
                          style: const TextStyle(
                            color: Colors.lightBlueAccent,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],

                  // Form correction suggestion — only shown if backend
                  // detected bad form during the exercise
                  if (_suggestion.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.redAccent, width: 1),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              color: Colors.redAccent, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _suggestion,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Good form message — shown when processing is done
                  // and no bad form was detected
                  if (_statusMessage == "done" && _suggestion.isEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: const [
                        Icon(Icons.check_circle,
                            color: Colors.greenAccent, size: 16),
                        SizedBox(width: 6),
                        Text(
                          "Great form! Keep it up.",
                          style: TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ---- SAVED FILE NAME ----
          // Shown just above the record button after recording stops
          if (_recordedVideoPath != null && !_isUploading)
            Positioned(
              bottom: 120,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  path.basename(_recordedVideoPath!),
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ),
            ),

          // ---- RECORD BUTTON ----
          // Tap to start or stop recording. Button turns red with
          // a stop icon while recording is in progress.
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: () async {
                  if (_isBusy || _isUploading) return;
                  _isBusy = true;
                  if (_isRecording) {
                    await _stopRecording();
                  } else {
                    await _startRecording();
                  }
                  _isBusy = false;
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isRecording ? Colors.red : Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: (_isRecording ? Colors.red : Colors.white)
                            .withOpacity(0.4),
                        blurRadius: 16,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Icon(
                    _isRecording ? Icons.stop : Icons.videocam,
                    size: 40,
                    color: _isRecording ? Colors.white : Colors.black,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // STAT CHIP WIDGET
  // ---------------------------------------------------------------
  // Small labelled value chip used in the result overlay to display
  // rep count and confidence side by side.
  // ---------------------------------------------------------------
  Widget _statChip({
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}