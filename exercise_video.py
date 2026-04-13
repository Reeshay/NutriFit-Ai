'''''# ============================================================
# NUTRIFT AI POSE ESTIMATION MODULE USING MEDIAPIPE
# ============================================================
# This module provides all functionality for the NutriftAI
# exercise analysis system:
#   - CSV dataset creation and landmark export
#   - Video labeling for training data collection
#   - Model training and evaluation
#   - Real-time webcam predictions with form feedback
#   - Video file processing for rep counting (used by Flask API)
# ============================================================

import os
import csv
import time
import pickle
import cv2
import mediapipe as mp
import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import LogisticRegression, RidgeClassifier
from sklearn.ensemble import RandomForestClassifier, GradientBoostingClassifier
from sklearn.metrics import accuracy_score, precision_score, recall_score


# ============================================================
# LANDMARK COLUMN HEADERS
# ============================================================
# MediaPipe detects 33 body landmarks. Each landmark has 4
# values: x, y, z (position) and visibility (confidence).
# The 'class' column stores the pose label (e.g. "up", "down").
#
# NOTE: Bench Press is a special case — it uses only the first
# 22 landmarks to avoid hip influence on the model, since the
# lower body is irrelevant during a bench press movement.
# ============================================================

# Full 33-landmark header — used for Deadlift and Squat
landmarks = ['class']
for val in range(1, 33 + 1):
    landmarks += [f'x{val}', f'y{val}', f'z{val}', f'v{val}']

# Reduced 22-landmark header — used for Bench Press only
landmarks_bench = ['class']
for val in range(1, 22 + 1):
    landmarks_bench += [f'x{val}', f'y{val}', f'z{val}', f'v{val}']


# ============================================================
# CREATE CSV FILES
# ============================================================
# These functions initialise and populate the CSV dataset files
# used to train the pose classification models.
# ============================================================

def first_line_CSV_file(path, bench=False):
    """
    Creates a new CSV file and writes the header row.
    Call this once before starting a labeling session.

    Args:
        path  (str):  File path for the CSV.
        bench (bool): If True, uses the 22-landmark header
                      for Bench Press; otherwise uses 33.
    """
    header = landmarks_bench if bench else landmarks
    with open(path, mode='w', newline='') as f:
        csv_writer = csv.writer(f, delimiter=',', quotechar='"', quoting=csv.QUOTE_MINIMAL)
        csv_writer.writerow(header)


def export_landmark(results, action, path, bench=False):
    """
    Appends one row of pose landmark data to the CSV file.
    Called each time a labeling key is pressed during a video.

    Args:
        results: MediaPipe pose detection result object.
        action  (str):  The class label to assign this frame.
        path    (str):  Path to the CSV file.
        bench   (bool): If True, only the first 22 landmarks
                        are exported (Bench Press mode).
    """
    try:
        all_landmarks = results.pose_landmarks.landmark
        # Use only the first 22 landmarks for Bench Press
        selected = list(all_landmarks)[:22] if bench else list(all_landmarks)

        keypoints = np.array([
            [res.x, res.y, res.z, res.visibility]
            for res in selected
        ]).flatten().tolist()

        keypoints.insert(0, action)

        with open(path, mode='a', newline='') as f:
            csv_writer = csv.writer(f, delimiter=',', quotechar='"', quoting=csv.QUOTE_MINIMAL)
            csv_writer.writerow(keypoints)
    except Exception:
        pass


# ============================================================
# VIDEO LABELING FOR TRAINING DATA COLLECTION
# ============================================================
# The following function is used to manually label videos.
#
# While the video plays, press the keyboard keys mapped in
# the 'labels' dictionary to assign pose classes to each frame.
# These labeled frames are saved to the CSV for model training.
#
# Key mappings used per exercise:
#
#   Deadlift:   u=up, d=down, l=down_low, r=down_roll,
#               b=up_back, g=up_roll
#
#   Squat:      u=up, d=down, l=down_deep, f=down_forward
#
#   Bench Press: u=up, d=down, l=down_close, c=up_close,
#                r=up_roll
#
# Press 'q' to quit the labeling session.
# ============================================================

def labeling_video(path_video, labels, path_CSV, bench=False):
    """
    Plays a video and allows manual frame-by-frame pose labeling.
    Draws MediaPipe skeleton overlay on screen for visual reference.

    Args:
        path_video (str):  Path to the input video file.
        labels     (dict): Mapping of class name → ASCII key code.
        path_CSV   (str):  CSV file to append labeled data to.
        bench      (bool): If True, uses 22-landmark mode for Bench Press.
    """
    mp_drawing = mp.solutions.drawing_utils
    mp_pose = mp.solutions.pose

    cap = cv2.VideoCapture(path_video)
    with mp_pose.Pose(min_detection_confidence=0.5, min_tracking_confidence=0.5) as pose:
        while cap.isOpened():
            ret, image = cap.read()
            if not ret:
                break

            # Recolor feed from BGR to RGB for MediaPipe processing
            image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
            image.flags.writeable = False

            # Run pose detection
            results = pose.process(image)

            # Recolor back to BGR for OpenCV rendering
            image.flags.writeable = True
            image = cv2.cvtColor(image, cv2.COLOR_RGB2BGR)

            if results.pose_landmarks:
                # Draw skeleton landmarks on the frame
                mp_drawing.draw_landmarks(
                    image,
                    results.pose_landmarks,
                    mp_pose.POSE_CONNECTIONS,
                    mp_drawing.DrawingSpec(color=(245, 117, 66), thickness=2, circle_radius=4),
                    mp_drawing.DrawingSpec(color=(245, 66, 230), thickness=2, circle_radius=2)
                )

            # Check for labeling key press and export landmark row
            k = cv2.waitKey(1)
            for label, asci in labels.items():
                if k == asci:
                    export_landmark(results, label, path_CSV, bench=bench)

            cv2.imshow('Raw Webcam Feed', image)

            # Press 'q' to quit the labeling session
            key = cv2.waitKey(1)
            if key == ord('q'):
                break

    cap.release()
    cv2.waitKey(1)
    cv2.destroyAllWindows()
    cv2.waitKey(1)


# ============================================================
# DEADLIFT — LABELING SESSION
# ============================================================
# Classes: up, down, down_low, down_roll, up_back, up_roll
# Videos: correct form, rolling back, overarching back
# ============================================================
# Uncomment to run:
path_CSV = 'CSV_files/coords_DL_C_new.csv'
path_videos = [
     'Videos/CorrectDeadlift_45f.mp4',
     'Videos/RollingDeadlift_45f.mp4',
     'Videos/BackDeadlift_45f.mp4'
 ]
labels = {"up": 117, "down": 100, "down_low": 108,
            "down_roll": 114, "up_back": 98, "up_roll": 103}
first_line_CSV_file(path_CSV)
for path_video in path_videos:
    labeling_video(path_video, labels, path_CSV)
    time.sleep(6)


# ============================================================
# SQUAT — LABELING SESSION
# ============================================================
# Classes: up, down, down_deep, down_forward
# Videos: correct form, forward lean, too deep
# ============================================================
# Uncomment to run:
path_CSV = 'CSV_files/coords_SQ_C_new.csv'
path_videos = [
     'Videos/CorrectSquat_45f.mp4',
     'Videos/ForwardSquat_45f.mp4',
     'Videos/DeepSquat.mp4'
 ]
labels = {"up": 117, "down": 100, "down_deep": 108, "down_forward": 102}
first_line_CSV_file(path_CSV)
for path_video in path_videos:
   labeling_video(path_video, labels, path_CSV)
   time.sleep(6)


# ============================================================
# BENCH PRESS — LABELING SESSION
# ============================================================
# Classes: up, down, down_close, up_close, up_roll
# deos: correct form, tight grip, shoulder roll
# Uses only 22 landmarks — hips are irrelevant for bench press.
# ============================================================
# Uncomment to run:
path_CSV = 'CSV_files/coords_BP_C_new.csv'
path_videos = [
     'Videos/CorrectBench_45f.mp4',
     'Videos/TietBench_45f.mp4',
     'Videos/RollBench_45f.mp4'
 ]
labels = {"up": 117, "down": 100, "down_close": 108,
            "up_close": 99, "up_roll": 114}
first_line_CSV_file(path_CSV, bench=True)
for path_video in path_videos:
    labeling_video(path_video, labels, path_CSV, bench=True)
    time.sleep(6)


# ============================================================
# MODEL TRAINING
# ============================================================
# Four classifier pipelines are defined. Each applies standard
# scaling before classification to normalise landmark values.
#
# Algorithms:
#   lr  — Logistic Regression
#   rc  — Ridge Classifier
#   rf  — Random Forest (chosen as the final saved model)
#   gb  — Gradient Boosting
#
# The Random Forest model is selected for deployment because it
# achieves the best balance of accuracy and inference speed.
# ============================================================

pipelines = {
    'lr': make_pipeline(StandardScaler(), LogisticRegression(max_iter=1000)),
    'rc': make_pipeline(StandardScaler(), RidgeClassifier()),
    'rf': make_pipeline(StandardScaler(), RandomForestClassifier()),
    'gb': make_pipeline(StandardScaler(), GradientBoostingClassifier()),
}


def Create_sample_label_dataset(path_CSV):
    """
    Loads a CSV dataset and splits it into train/test sets.
    The 'class' column is used as the target label.
    70% of data is used for training, 30% for testing.

    Args:
        path_CSV (str): Path to the labeled landmark CSV file.

    Returns:
        Tuple: (X_train, X_test, y_train, y_test)
    """
    df = pd.read_csv(path_CSV)
    X = df.drop('class', axis=1)   # Feature columns (landmark coordinates)
    y = df['class']                 # Target labels (pose class names)

    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.3, random_state=42)
    return X_train, X_test, y_train, y_test


def Train_Model(X_train, y_train):
    """
    Trains all four classifier pipelines on the training data.

    Args:
        X_train: Feature matrix for training.
        y_train: Label vector for training.

    Returns:
        dict: Fitted models keyed by algorithm abbreviation.
    """
    fitted_models = {}
    for algo, pipeline in pipelines.items():
        model = pipeline.fit(X_train, y_train)
        fitted_models[algo] = model
    return fitted_models


def Test_Accuracy(fitted_models, X_test, y_test):
    """
    Evaluates all fitted models and prints accuracy, precision,
    and recall scores on the test set.

    Precision and recall are computed with macro averaging:
    scores are calculated per class then averaged equally,
    regardless of class frequency.

    Args:
        fitted_models (dict): Models returned by Train_Model().
        X_test:  Feature matrix for evaluation.
        y_test:  True labels for evaluation.
    """
    for algo, model in fitted_models.items():
        yhat = model.predict(X_test)
        print(
            algo,
            accuracy_score(y_test.values, yhat),
            precision_score(y_test.values, yhat, average='macro', zero_division=0),
            recall_score(y_test.values, yhat, average='macro', zero_division=0)
        )


def save_model(model, save_path):
    """
    Saves a trained model to disk as a pickle file.
    Creates the output directory if it doesn't exist.

    Args:
        model:      The fitted sklearn pipeline to save.
        save_path (str): Destination file path (e.g. 'Models/Bench_rf.pkl').
    """
    os.makedirs(os.path.dirname(save_path), exist_ok=True)
    with open(save_path, 'wb') as f:
        pickle.dump(model, f)


# ============================================================
# TRAIN DEADLIFT MODEL
# ============================================================
# Merges the original and updated Deadlift datasets, trains
# all pipelines, evaluates accuracy, and saves the RF model.
# ============================================================
# Uncomment to run:
path_CSV_DL = 'CSV_files/coords_DL_C.csv'
path_CSV_DL_new = 'CSV_files/coords_DL_C_new.csv'
df_dl = pd.concat([pd.read_csv(path_CSV_DL), pd.read_csv(path_CSV_DL_new)], ignore_index=True)
df_dl.to_csv('CSV_files/coords_DL_merged.csv', index=False)
X_train, X_test, y_train, y_test = Create_sample_label_dataset('CSV_files/coords_DL_merged.csv')
fitted_models = Train_Model(X_train, y_train)
Test_Accuracy(fitted_models, X_test, y_test)
save_model(fitted_models['rf'], 'Models/Deadlift_rf.pkl')
# ============================================================
# TRAIN SQUAT MODEL
# ============================================================
# Uncomment to run:
X_train, X_test, y_train, y_test = Create_sample_label_dataset('CSV_files/coords_SQ_C.csv')
fitted_models = Train_Model(X_train, y_train)
Test_Accuracy(fitted_models, X_test, y_test)
save_model(fitted_models['rf'], 'Models/Squat_rf.pkl')


# ============================================================
# TRAIN BENCH PRESS MODEL
# ============================================================
# Uses only the first 22 landmark columns (hips excluded).
# Uncomment to run:
X_train, X_test, y_train, y_test = Create_sample_label_dataset('CSV_files/coords_BP_C.csv')
fitted_models = Train_Model(X_train, y_train)
Test_Accuracy(fitted_models, X_test, y_test)
save_model(fitted_models['rf'], 'Models/Bench_rf.pkl')


# ============================================================
# REAL-TIME FORM FEEDBACK (SUGGESTIONS)
# ============================================================
# Compares the current prediction and stage to known bad-form
# classes and overlays a corrective message on the video frame.
#
# Bad-form classes per exercise:
#
#   Deadlift:
#     up_back   — overarching lower back at the top
#     up_roll   — rounding the back at the top
#     down_roll — rounding the back on the way down
#     down_low  — hips too low (squatting instead of hinging)
#
#   Squat:
#     down_deep   — going too far below parallel
#     down_forward — excessive forward torso lean
#
#   Bench Press:
#     up_close  — arms not parallel (grip too narrow)
#     up_roll   — shoulder extension instead of lockout
#     down_close — chest not open enough at the bottom
# ============================================================

def Give_suggestions(path_model, prediction, image, currentStage):
    """
    Renders a corrective form suggestion on the video frame
    when a bad-form pose class is detected and sustained.

    Args:
        path_model   (str): Path to the active model file.
        prediction   (str): Current predicted pose class.
        image:              OpenCV image frame to draw on.
        currentStage (str): The last confirmed pose stage.
    """
    message = ''

    if path_model == "Models/Deadlift_rf.pkl":
        if prediction == currentStage == "up_back":
            message = "Avoid leaning backward or overarching your lower back."
        elif prediction == currentStage == "up_roll":
            message = "Never round your back while deadlifting."
        elif prediction == currentStage == "down_roll":
            message = "Try not to arch your back. Keep your chest elevated instead."
        elif prediction == currentStage == "down_low":
            message = "This is not a squat! Try to have your hips above parallel."

    if path_model == "Models/Squat_rf.pkl":
        if prediction == currentStage == "down_deep":
            message = "Try not to go down this much."
        elif prediction == currentStage == "down_forward":
            message = "Avoid leaning forward. Keep your back straight."

    if path_model == "Models/Bench_rf.pkl":
        if prediction == currentStage == "up_close":
            message = "Make sure to keep your arms parallel to each other."
        elif prediction == currentStage == "up_roll":
            message = "Try to lock your shoulders instead of extending them."
        elif prediction == currentStage == "down_close":
            message = "Try to keep your chest more open."

    # Draw white background bar and overlay message text
    cv2.rectangle(image, (7, 437), (610, 472), (255, 255, 255), -1)
    cv2.putText(image, message, (15, 460), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 0), 1, cv2.LINE_AA)


# ============================================================
# REAL-TIME WEBCAM PREDICTION
# ============================================================
# Loads a trained model and runs live pose classification on
# the webcam feed. Counts reps and displays form feedback.
#
# Rep counting logic:
#   A rep is counted when the pose transitions from a "down"
#   class to an "up" class with confidence >= 0.3.
#
# Press 'q' to quit the webcam session.
# ============================================================

def Make_Predictions(path_model, ups, downs, webcam):
    """
    Runs live pose classification and rep counting on a webcam.

    Args:
        path_model (str):  Path to the trained .pkl model file.
        ups        (list): Class names considered the "up" position.
        downs      (list): Class names considered the "down" position.
        webcam     (int):  Camera index (0 = default webcam).
    """
    with open(path_model, 'rb') as f:
        model = pickle.load(f)

    mp_drawing = mp.solutions.drawing_utils
    mp_pose = mp.solutions.pose

    # Determine landmark set based on model (Bench uses 22, others 33)
    is_bench = "Bench" in path_model
    feature_cols = landmarks_bench[1:] if is_bench else landmarks[1:]

    cap = cv2.VideoCapture(webcam)
    counter = 0
    current_stage = ''

    with mp_pose.Pose(min_detection_confidence=0.5, min_tracking_confidence=0.5) as pose:
        while cap.isOpened():
            ret, image = cap.read()
            if not ret:
                break

            # Mirror the image for a natural mirror-like view
            image = cv2.flip(image, 1)

            # Recolor to RGB for MediaPipe
            image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
            image.flags.writeable = False

            results = pose.process(image)

            # Recolor back to BGR for OpenCV display
            image.flags.writeable = True
            image = cv2.cvtColor(image, cv2.COLOR_RGB2BGR)

            if results.pose_landmarks:
                mp_drawing.draw_landmarks(
                    image,
                    results.pose_landmarks,
                    mp_pose.POSE_CONNECTIONS,
                    mp_drawing.DrawingSpec(color=(245, 117, 66), thickness=2, circle_radius=4),
                    mp_drawing.DrawingSpec(color=(245, 66, 230), thickness=2, circle_radius=2)
                )

            try:
                if not results.pose_landmarks:
                    continue

                # Extract only the landmarks needed for this model
                all_lm = results.pose_landmarks.landmark
                selected = list(all_lm)[:22] if is_bench else list(all_lm)

                row = np.array([
                    [res.x, res.y, res.z, res.visibility]
                    for res in selected
                ]).flatten().tolist()

                X = pd.DataFrame([row], columns=feature_cols)
                body_language_class = model.predict(X)[0]
                body_language_prob = model.predict_proba(X)[0]

                # Overlay form correction suggestion if bad form detected
                Give_suggestions(path_model, body_language_class, image, current_stage)

                # Rep counting: down → up transition counts as one rep
                if body_language_class in downs and body_language_prob.max() >= 0.3:
                    current_stage = body_language_class
                elif current_stage in downs and body_language_class in ups and body_language_prob.max() >= 0.3:
                    current_stage = body_language_class
                    counter += 1

                # Display HUD: class name and rep count
                cv2.rectangle(image, (0, 0), (500, 120), (201, 148, 56), -1)

                cv2.putText(image, 'CLASS', (60, 30), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (0, 0, 0), 2, cv2.LINE_AA)
                cv2.putText(image, body_language_class.split(' ')[0], (14, 90), cv2.FONT_HERSHEY_SIMPLEX, 2, (255, 255, 255), 4, cv2.LINE_AA)

                cv2.putText(image, 'COUNT', (380, 30), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (0, 0, 0), 2, cv2.LINE_AA)
                cv2.putText(image, str(counter), (400, 90), cv2.FONT_HERSHEY_SIMPLEX, 2, (255, 255, 255), 4, cv2.LINE_AA)

            except Exception:
                pass

            cv2.imshow('Mediapipe Feed', image)

            if cv2.waitKey(10) & 0xFF == ord('q'):
                break

    cap.release()
    cv2.waitKey(1)
    cv2.destroyAllWindows()
    cv2.waitKey(1)


# ============================================================
# EXERCISE CONFIGURATION MAP
# ============================================================
# Defines the up/down pose classes and landmark mode for each
# supported exercise. Used by process_video() to select the
# correct feature set and rep-counting logic automatically.
#
#   Bench Press:  22 landmarks (hips excluded)
#   Deadlift:     33 landmarks
#   Squat:        33 landmarks
# ============================================================

EXERCISE_CONFIG = {
    "Models/Bench_rf.pkl": {
        "ups":   ["up", "up_close", "up_roll"],
        "downs": ["down", "down_close"],
        "bench": True,   # Use 22-landmark feature set
    },
    "Models/Deadlift_rf.pkl": {
        "ups":   ["up", "up_back", "up_roll"],
        "downs": ["down", "down_low", "down_roll"],
        "bench": False,
    },
    "Models/Squat_rf.pkl": {
        "ups":   ["up"],
        "downs": ["down", "down_deep", "down_forward"],
        "bench": False,
    },
}


# ============================================================
# REAL-TIME FORM FEEDBACK — TEXT ONLY (API VERSION)
# ============================================================
# Returns a corrective suggestion string based on the current
# prediction and stage. Used by process_video() to include the
# suggestion in the JSON response to the Flutter app.
# Returns empty string if form is correct.
# ============================================================

def get_suggestion(model_path, prediction, current_stage):
    """
    Returns a corrective form suggestion string when a bad-form
    pose is detected and sustained. Returns "" if form is correct.

    Args:
        model_path    (str): Path to the active model file.
        prediction    (str): Current predicted pose class.
        current_stage (str): The last confirmed pose stage.

    Returns:
        str: A corrective message, or "" if form is correct.
    """
    message = ""

    if model_path == "Models/Deadlift_rf.pkl":
        if prediction == current_stage == "up_back":
            message = "Avoid leaning backward or overarching your lower back."
        elif prediction == current_stage == "up_roll":
            message = "Never round your back while deadlifting."
        elif prediction == current_stage == "down_roll":
            message = "Try not to arch your back. Keep your chest elevated instead."
        elif prediction == current_stage == "down_low":
            message = "This is not a squat! Try to have your hips above parallel."

    elif model_path == "Models/Squat_rf.pkl":
        if prediction == current_stage == "down_deep":
            message = "Try not to go down this much."
        elif prediction == current_stage == "down_forward":
            message = "Avoid leaning forward. Keep your back straight."

    elif model_path == "Models/Bench_rf.pkl":
        if prediction == current_stage == "up_close":
            message = "Make sure to keep your arms parallel to each other."
        elif prediction == current_stage == "up_roll":
            message = "Try to lock your shoulders instead of extending them."
        elif prediction == current_stage == "down_close":
            message = "Try to keep your chest more open."

    return message


# ============================================================
# VIDEO FILE PROCESSING (FLASK API ENDPOINT)
# ============================================================
# This function is called by the Flask backend when the mobile
# app uploads a recorded exercise video. It runs pose
# classification and rep counting on every frame — headless,
# no cv2.imshow() is called anywhere.
#
# The exercise type is inferred from model_path.
# Every frame is wrapped in try/except so a single bad frame
# (corrupt codec, empty read, etc.) does not crash the whole
# request and cause a 500 error.
#
# Returns a JSON-serialisable dict with:
#   reps        — total reps counted in the video
#   confidence  — max prediction confidence of the last frame
#   pose        — last detected pose class name
#   suggestion  — corrective form tip, or "" if form was good
#   status      — "done" on success, "error" with message on fail
#   frames_processed — number of frames successfully analysed
# ============================================================

def process_video(video_path, model_path="Models/Bench_rf.pkl"):
    """
    Processes a recorded exercise video to count reps, detect
    the last pose class, and generate a form suggestion.
    Used by the Flask API — fully headless, no display windows.

    Each frame is processed inside a try/except so corrupt or
    unreadable frames are skipped without crashing the request.

    Args:
        video_path (str): Path to the uploaded video file.
        model_path (str): Path to the trained .pkl model.
                          Defaults to Bench Press model.

    Returns:
        dict: {
            "reps":             int,
            "confidence":       float,
            "pose":             str,
            "suggestion":       str,
            "status":           "done" or "error",
            "frames_processed": int
        }
    """
    import traceback

    try:
        # Load exercise-specific configuration
        config   = EXERCISE_CONFIG.get(model_path, EXERCISE_CONFIG["Models/Bench_rf.pkl"])
        ups      = config["ups"]
        downs    = config["downs"]
        is_bench = config["bench"]

        # Select the correct feature column list for this exercise
        feature_cols = landmarks_bench[1:] if is_bench else landmarks[1:]

        # Load the trained Random Forest model
        with open(model_path, "rb") as f:
            model = pickle.load(f)

        mp_pose = mp.solutions.pose

        # Open the uploaded video file
        cap = cv2.VideoCapture(video_path)
        if not cap.isOpened():
            return {
                "reps": 0, "confidence": 0.0, "pose": "",
                "suggestion": "", "frames_processed": 0,
                "status": "error: could not open video file"
            }

        counter          = 0
        current_stage    = ""
        prob             = 0.0
        last_pred        = ""
        last_suggestion  = ""
        frames_processed = 0

        with mp_pose.Pose(
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5
        ) as pose:

            while cap.isOpened():
                ret, image = cap.read()

                # End of video
                if not ret:
                    break

                # Skip empty/corrupt frames silently instead of crashing
                if image is None or image.size == 0:
                    continue

                try:
                    # Mirror the frame for consistent orientation with training data
                    image     = cv2.flip(image, 1)
                    image_rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
                    results   = pose.process(image_rgb)

                    # Skip frames where no person is detected
                    if not results.pose_landmarks:
                        continue

                    # Extract landmarks — 22 for Bench Press, 33 for others
                    all_lm   = results.pose_landmarks.landmark
                    selected = list(all_lm)[:22] if is_bench else list(all_lm)

                    row = np.array([
                        [lm.x, lm.y, lm.z, lm.visibility]
                        for lm in selected
                    ]).flatten().tolist()

                    X    = pd.DataFrame([row], columns=feature_cols)
                    pred = model.predict(X)[0]
                    prob = float(model.predict_proba(X)[0].max())

                    last_pred        = pred
                    frames_processed += 1

                    # Capture most recent bad-form suggestion
                    suggestion = get_suggestion(model_path, pred, current_stage)
                    if suggestion:
                        last_suggestion = suggestion

                    # Rep counting: down-to-up transition = 1 rep
                    if pred in downs and prob > 0.3:
                        current_stage = pred
                    elif current_stage in downs and pred in ups and prob > 0.3:
                        current_stage = pred
                        counter += 1

                except Exception:
                    # Single bad frame — log and continue instead of crashing
                    print(f"[process_video] Skipped frame: {traceback.format_exc()}")
                    continue

        cap.release()

        return {
            "reps":             counter,
            "confidence":       round(prob, 2),
            "pose":             last_pred,
            "suggestion":       last_suggestion,
            "frames_processed": frames_processed,
            "status":           "done"
        }

    except Exception:
        # Top-level error — return details instead of letting Flask 500
        error_detail = traceback.format_exc()
        print(f"[process_video] FATAL: {error_detail}")
        return {
            "reps": 0, "confidence": 0.0, "pose": "",
            "suggestion": "", "frames_processed": 0,
            "status": f"error: {error_detail}"
        }


# ============================================================
# WEBCAM & TRAINING SESSIONS
# ============================================================
# Everything below only runs when this file is executed directly:
#   python exercise_video.py
#
# It does NOT run when Flask imports this module — so no windows
# pop up on the server and no training starts unexpectedly.
# ============================================================

if __name__ == "__main__":

    # ============================================================
    # DEADLIFT MODEL — WEBCAM SESSION
    # ============================================================
    # Up classes:   up, up_back, up_roll
    # Down classes: down, down_low, down_roll
    # ============================================================
    ups   = ["up", "up_back", "up_roll"]
    downs = ["down", "down_low", "down_roll"]
    Make_Predictions("Models/Deadlift_rf.pkl", ups, downs, webcam=0)

    # ============================================================
    # SQUAT MODEL — WEBCAM SESSION
    # ============================================================
    # Up classes:   up
    # Down classes: down, down_deep, down_forward
    # ============================================================
    ups   = ["up"]
    downs = ["down", "down_deep", "down_forward"]
    Make_Predictions("Models/Squat_rf.pkl", ups, downs, webcam=0)

    # ============================================================
    # BENCH PRESS MODEL — WEBCAM SESSION
    # ============================================================
    # Up classes:   up, up_close, up_roll
    # Down classes: down, down_close
    # ============================================================
    ups   = ["up", "up_close", "up_roll"]
    downs = ["down", "down_close"]
    Make_Predictions("Models/Bench_rf.pkl", ups, downs, webcam=0)'''''