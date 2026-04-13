from typing import Dict, Any, Optional
from datetime import datetime
import ollama

DEFAULT_TIMEZONE = "Asia/Karachi"
DEFAULT_MODEL = "tomng/lfm2.5-instruct:1.2b"

WEEKDAYS = [
    "Monday", "Tuesday", "Wednesday",
    "Thursday", "Friday", "Saturday", "Sunday"
]

WEEKDAY_TO_DAY_KEY = {
    "Monday": "Day 1",
    "Tuesday": "Day 2",
    "Wednesday": "Day 3",
    "Thursday": "Day 4",
    "Friday": "Day 5",
    "Saturday": "Day 6",
    "Sunday": "Day 7",
}


class Chatbot:
    def get_current_day(self,user_data: dict, timezone: str = DEFAULT_TIMEZONE) -> str:
        user_profile = user_data.get("user_profile", {})
        if "current_day" in user_profile:
            return user_profile["current_day"]

        tz = datetime.now().astimezone().tzinfo
        try:
            from zoneinfo import ZoneInfo
            tz = ZoneInfo(timezone)
        except Exception:
            pass

        today_index = datetime.now(tz).weekday()
        return WEEKDAYS[today_index]


    def split_health_and_allergies(self, profile: dict):
        raw_conditions = profile.get("healthConditions", [])
        allergies = profile.get("allergies", [])

        clean_health = []
        clean_allergies = list(allergies)

        for item in raw_conditions:
            if isinstance(item, str) and "allergy:" in item.lower():
                allergy_name = item.split(":")[1].strip()
                clean_allergies.append(allergy_name)
            else:
                clean_health.append(item)

        return clean_health, clean_allergies


    def flatten_today_plan(self,plan: dict, plan_type: str, today: str, day_key: Optional[str] = None) -> str:
        result = f"{plan_type} for {today}:\n"

        if not plan or "plan" not in plan:
            return result + "No plan available.\n"

        lookup_key = day_key if day_key else today
        day_details = plan.get("plan", {}).get(lookup_key)

        if not day_details:
            return result + f"No {plan_type.lower().split()[0]} assigned.\n"

        if plan_type == "Meal Plan":
            meals = day_details.get("meals", {})
            if not meals:
                return result + "No meals assigned.\n"

            for meal_name, meal_info in meals.items():
                items = meal_info.get("items", [])
                food_names = [
                    item.get("food_name")
                    for item in items
                    if item.get("food_name")
                ]
                if food_names:
                    result += f"  • {meal_name.capitalize()}: {', '.join(food_names)}\n"

            return result

        exercises = (
            day_details.get("exercises", [])
            if isinstance(day_details, dict)
            else day_details
        )

        for ex in exercises:
            name = ex.get("exercise_name", "Exercise")
            sets = ex.get("sets", 0)
            reps = ex.get("repetitions", 0)
            duration = ex.get("duration", 0)
            result += f"  • {name}: {sets} sets x {reps} reps, {duration} min\n"

        return result


    def build_system_prompt(self,profile: Dict[str, Any], today: str) -> str:
        clean_health, clean_allergies = self.split_health_and_allergies(profile)
        day_key = WEEKDAY_TO_DAY_KEY.get(today, today)
        user_name = profile.get("name", "there")
        user_goal = profile.get("goal", "fitness")

        meal_plan_str = self.flatten_today_plan(
            profile.get("meal_plan", {}),
            "Meal Plan",
            today,
            today
        )

        exercise_plan_str = self.flatten_today_plan(
            profile.get("exercise_plan", {}),
            "Exercise Plan",
            today,
            today
        )
        weekly_progress = profile.get("progress", {}).get("weekly", {})
        monthly_progress = profile.get("progress", {}).get("monthly", {})
        weekly_summary = f"Weekly Progress: {weekly_progress}" if weekly_progress else "No weekly progress data."
        monthly_summary = f"Monthly Progress: {monthly_progress}" if monthly_progress else "No monthly progress data."

        disclaimer = "Disclaimer: This is for informational purposes only. Consult a healthcare professional before making changes to your diet or exercise routine."
        if not clean_health:
            disclaimer = ""

        return f"""
                    You are NutriFit AI Coach — a friendly, professional, and supportive AI nutrition and fitness assistant inside a fitness app.
    
                    ========================
                    BEHAVIOR RULES
                    ========================
                    - Use ONLY the data provided below.
                    - Do NOT calculate anything.
                    - Do NOT modify numbers.
                    - Do NOT invent missing data.
                    - Do NOT assume values.
                    - Keep responses short, structured, and app-friendly.
                    - Use clear headings and bullet points.
                    - Be supportive, motivating, and personalized using the user's name when available.
                    - Never provide medical diagnosis.
                    - If information is missing, say: "I don't have that information in your profile."
                    - Think less, answer directly and concisely.
    
                    ========================
                    GREETING BEHAVIOR
                    ========================
                    If the user says:
                    "hi", "hello", "hey", "good morning", "good evening", or similar greeting
    
                    Respond in a warm, friendly, personalized way:
                    - Greet them by name (if available)
                    - Offer help with meals, workouts, or goals
                    - Keep it short and positive
                    Example tone:
                    "Hey {user_name}! Ready to crush your {user_goal} today? I can guide you with meals or workouts."
    
                    ========================
                    USER PROFILE
                    ========================
                    - Name: {profile.get("name")}
                    - Age: {profile.get("age")}
                    - Weight: {profile.get("weight")} kg
                    - Height: {profile.get("height")} ft
                    - Gender: {profile.get("gender")}
                    - Activity Level: {profile.get("activitylevel")}
                    - Target Goal: {profile.get("goal")}
                    - Health Conditions: {clean_health}
                    - Allergies: {clean_allergies}
                    - BMI: {profile.get("bmi")}
                    - BMR: {profile.get("bmr")}
                    - TDEE: {profile.get("tdee")}
    
                    ========================
                    MEAL PLAN
                    ========================
                    {meal_plan_str}
    
                    ========================
                    EXERCISE PLAN
                    ========================
                    {exercise_plan_str}
                    
                    ========================
                    PROGRESS
                    ========================
                    {weekly_summary}
                    {monthly_summary}
                    
                    ========================
                    RESPONSE FORMAT RULES
                    ========================
                    When giving plans:
                    - Use sections:
                    🔹 Nutrition
                    🔹 Workout
                    🔹 Tips
                    - Keep it structured and easy to scan.
                    - No long paragraphs.
                    - No emojis except light motivational ones (💪🔥🥗).
    
                    ========================
                    SAFETY
                    ========================
                    If user asks for medical advice:
                    Respond with:
                    "Please consult a qualified healthcare professional for medical advice."
    
                    ========================
                    DISCLAIMER
                    ========================
                    {disclaimer}
            """


    def call_ai(self,system_prompt: str, user_message: str, model: str = DEFAULT_MODEL) -> str:
        try:
            response = ollama.chat(
                model=model,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_message}
                ],
                options={
                    "temperature": 0.2,
                    "top_p": 0.8
                }
            )

            return response["message"]["content"]

        except Exception as e:
            print("Ollama Error:", str(e))
            return "AI is temporarily unavailable. Please try again."


    def generate_chat_response(self,user_data: dict):
        user_profile = user_data.get("user_profile")
        user_message = user_data.get("message", "").strip().lower()

        if not user_profile or not user_message:
            return {
                "status": "error",
                "message": "Missing user profile or message"
            }

        timezone = user_data.get("timezone", DEFAULT_TIMEZONE)
        today = self.get_current_day(user_data, timezone)

        clean_health, clean_allergies = self.split_health_and_allergies(user_profile)
        profile_intent = "profile" in user_message

        replies = []

        if profile_intent:
            profile_text = f"""
                User Profile:
                • Name: {user_profile.get("name")}
                • Age: {user_profile.get("age")}
                • Weight: {user_profile.get("weight")} kg
                • Height: {user_profile.get("height")} ft
                • Gender: {user_profile.get("gender")}
                • Activity Level: {user_profile.get("activitylevel")}
                • Target Goal: {user_profile.get("goal")}
                • Health Conditions: {clean_health}
                • Allergies: {clean_allergies}
                • BMI: {user_profile.get("bmi")}
                • BMR: {user_profile.get("bmr")}
                • TDEE: {user_profile.get("tdee")}
            """
            replies.append(profile_text.strip())

        if replies:
            return {
                "status": "success",
                "reply": "\n\n".join(replies)
            }

        system_prompt = self.build_system_prompt(user_profile, today)
        ai_reply = self.call_ai(system_prompt, user_message)

        return {
            "status": "success",
            "reply": ai_reply
        }
chatbot = Chatbot()