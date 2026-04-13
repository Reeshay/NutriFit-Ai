from flask import Flask, jsonify, request
from flask_cors import CORS

from chatbot import chatbot
from cheatmeal import cheatmeal_route
from exercise_plan import exercise_plan_route
#from exercise_video import process_video
from gamification import gamification_sync_route
from meal_snap import estimate_from_image_bytes

from profile_setup import profile_setup_route

from meal_plan import generate_meal_plan_route
from track_progress import TrackProgress
app = Flask(__name__)
CORS(app)



@app.route("/profile_setup", methods=["POST"])
def handle_profile_setup_endpoint():
    try:
        user_data = request.get_json()
        print(user_data)
        return profile_setup_route()

    except Exception as e:
        app.logger.error(f"Error in profile setup: {str(e)}")
        return jsonify({"status": "error", "message": str(e)}), 500


@app.route("/meal_snap", methods=["POST"])
def predict():
    file = request.files.get("meal_image")
    if file is None:
        return jsonify({"error": "No file provided"}), 400

    quantity_g = float(request.form.get("quantity_g", 0))
    image_bytes = file.read()

    try:
        result = estimate_from_image_bytes(image_bytes, quantity_g)
        print("Prediction result:", result)
        return jsonify(result)
    except Exception as e:
        return jsonify({"error": str(e)}), 400


@app.route("/meal_plan", methods=["POST"])
def meal_plan_endpoint():
    try:
        user_data = request.get_json()
        print(user_data)
        result = generate_meal_plan_route(user_data)
        print(result)
        return jsonify(result)
    except Exception as e:
        app.logger.error("Meal plan ERROR:", exc_info=True)
        return jsonify({"status": "error", "message": str(e)}), 500
@app.route("/cheatmeal", methods=["POST"])
def cheatmeal_endpoint():
    try:
        data = request.get_json()
        print("Cheat meal request:", data)

        result = cheatmeal_route(data)
        print("Cheat meal result:", result)

        status_code = 200 if result.get("status") != "error" else 500
        return jsonify(result), status_code

    except Exception as e:
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500
'''@app.route("/exercise_video", methods=["POST"])
def handle_exercise_video_endpoint():
    try:
        file = request.files.get("video")
        print(request.files)

        if file is None:
            return jsonify({"error": "No video"}), 400

        import os
        os.makedirs("videos", exist_ok=True)

        video_path = os.path.join("videos", file.filename)
        file.save(video_path)
        print(video_path)

        print("Saved:", video_path)

        # 🔥 CALL ML FUNCTION
        result = process_video(video_path)

        return jsonify(result), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500'''
@app.route("/gamification", methods=["POST"])
def gamification_endpoint():
    try:
        data = request.get_json()
        print("Gamification data:", data)

        result = gamification_sync_route(data)
        print(result)

        status_code = 200 if result.get("status") == "success" else 500
        return jsonify(result), status_code

    except Exception as e:
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500
@app.route("/exercise_plan", methods=["POST"])
def exercise_plan_endpoint():
    user_data = request.get_json()
    print(user_data)
    result = exercise_plan_route(user_data)
    status_code = 200 if result.get("status") == "success" else 500
    return jsonify(result), status_code
@app.route("/chatbot", methods=["POST"])
def chatbot_endpoint():
    data = request.get_json()
    print(data)
    result = chatbot.generate_chat_response(data)
    print(result)
    return jsonify(result)


@app.route("/track_progress", methods=["POST"])
def track_progress_endpoint():
    try:
        data = request.get_json()
        print(data)
        tracker = TrackProgress(data)
        result = tracker.track_progress()
        print(result)
        return jsonify({
            "status": "success",
            **result
        }), 200

    except Exception as e:
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000, debug=True)
