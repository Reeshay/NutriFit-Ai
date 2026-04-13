from datetime import datetime
import calendar
from logging import exception

def clean_numpy(data):
    if isinstance(data, dict):
        return {k: clean_numpy(v) for k, v in data.items()}
    elif isinstance(data, list):
        return [clean_numpy(i) for i in data]
    elif isinstance(data, bool):  # ✅ ADD THIS
        return data
    elif hasattr(data, "item"):
        return round(float(data.item()), 2)
    elif isinstance(data, (float, int)):
        return round(float(data), 2)
    return data


class TrackProgress:

    def __init__(self, data):

        self.data = data
        self.period = data.get("period", "weekly")
        self.meal_plan = data.get("meal_plan", {})
        self.eaten_foods = data.get("eaten_foods", [])
        profile_updated_at = data.get("profile_updated_at")

        try:
            if profile_updated_at and "seconds=" in profile_updated_at:
                seconds = int(profile_updated_at.split("seconds=")[1].split(",")[0])
                self.profile_start_date = datetime.fromtimestamp(seconds)
            else:
                self.profile_start_date = datetime.today()
        except Exception:
            self.profile_start_date = datetime.today()
        self.today = datetime.today()

        self.days_in_month = calendar.monthrange(
            self.today.year,
            self.today.month
        )[1]


    def weekly_progress(self):

        days_in_month = self.days_in_month
        meal_plan = self.meal_plan
        eaten_foods = self.eaten_foods

        monthly_calories = [0.0] * days_in_month
        monthly_all_eaten = [0.0] * days_in_month

        monthly_protein = [0.0] * days_in_month
        monthly_fats = [0.0] * days_in_month
        monthly_carbs = [0.0] * days_in_month

        monthly_protein_target = [0.0] * days_in_month
        monthly_fats_target = [0.0] * days_in_month
        monthly_carbs_target = [0.0] * days_in_month

        meal_plan_foods_by_day = {}

        weekly_target = [0.0] * 7
        weekly_protein_target = [0.0] * 7
        weekly_fats_target = [0.0] * 7
        weekly_carbs_target = [0.0] * 7
        weekly_all_eaten = [0.0] * 7

        for day_index in range(7):

            days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
            day_name = days[day_index]

            day_info = meal_plan.get(day_name)

            if not day_info:
                continue

            meals = day_info.get("meals", {})
            foods_set = set()

            for meal in meals.values():
                items = meal.get("items", [])

                for food in items:

                    name = food.get("food_name", "")

                    if name:
                        foods_set.add(
                            name.strip().lower()
                        )

            meal_plan_foods_by_day[day_index] = foods_set
            weekly_target[day_index] = float(day_info.get("predicted_daily_calories",0))

            macros_target = day_info.get("daily_macros_target",{})

            weekly_protein_target[day_index] = float(macros_target.get("protein_g",0))

            weekly_fats_target[day_index] = float(macros_target.get("fat_g",0))

            weekly_carbs_target[day_index] = float(macros_target.get("carbs_g",0))


        # -----------------------
        # Monthly macro targets
        # -----------------------

        for i in range(days_in_month):
            monthly_protein_target[i] = (weekly_protein_target[i % 7])

            monthly_fats_target[i] = (weekly_fats_target[i % 7])

            monthly_carbs_target[i] = (weekly_carbs_target[i % 7])


        weekly_calories = [0.0] * 7
        weekly_protein = [0.0] * 7
        weekly_fats = [0.0] * 7
        weekly_carbs = [0.0] * 7
        unmatched_foods = []
        unmatched_date = self.today.date()
        for food in eaten_foods:

            try:

                if not food.get("consumed", False):
                    continue

                name = food.get("food_name","").strip().lower()

                created_at = food.get("created_at")

                if not name or not created_at:
                    continue

                try:
                    food_date = datetime.fromisoformat(created_at)

                except exception:

                    food_date = datetime.fromisoformat(
                        created_at.split(".")[0]
                    )

                day_index = food_date.weekday()

                month_day = food_date.day - 1

                if month_day < days_in_month:
                    calories = float(food.get("calories", 0))

                    monthly_calories[month_day] += calories


                    monthly_all_eaten[month_day] += calories

                    monthly_protein[month_day] += float(food.get("protein_g", 0))

                    monthly_fats[month_day] += float(food.get("fat_g", 0))

                    monthly_carbs[month_day] += float(food.get("carbs_g", 0))


                matched = False

                if day_index in meal_plan_foods_by_day:
                    for food_name in meal_plan_foods_by_day[day_index]:
                        if name in food_name or food_name in name:
                            matched = True
                            break

                calories = float(food.get("calories", 0))

                # ✅ ALWAYS (for stats + trend)
                weekly_all_eaten[day_index] += calories

                # ✅ ONLY MATCHED → graph + macros
                if matched:
                    weekly_calories[day_index] += calories

                    weekly_protein[day_index] += float(food.get("protein_g", 0))
                    weekly_fats[day_index] += float(food.get("fat_g", 0))
                    weekly_carbs[day_index] += float(food.get("carbs_g", 0))
                else:
                    if food_date.date() == unmatched_date:
                        unmatched_foods.append(name)

            except exception:
                continue

        progress = [weekly_calories[i] - weekly_target[i]
            for i in range(7)
        ]

        progress_status = []

        for i in range(7):

            if weekly_target[i] == 0:

                progress_status.append(
                    "on track"
                )

            elif (
                    weekly_calories[i]
                    < weekly_target[i]
            ):

                progress_status.append(
                    "under"
                )

            elif (
                    weekly_calories[i]
                    > weekly_target[i]
            ):

                progress_status.append(
                    "over"
                )

            else:

                progress_status.append(
                    "on track"
                )

        total_eaten = sum(
            weekly_calories
        )

        total_target = sum(
            weekly_target
        )

        total_protein = sum(
            weekly_protein
        )

        total_fats = sum(
            weekly_fats
        )

        total_carbs = sum(
            weekly_carbs
        )

        total_protein_target = sum(
            weekly_protein_target
        )

        total_fats_target = sum(
            weekly_fats_target
        )

        total_carbs_target = sum(
            weekly_carbs_target
        )

        progress_percentage = min(
            (total_eaten/ total_target) * 100

            if total_target > 0
            else 0,100
        )

        protein_percentage = (
            (total_protein/total_protein_target) * 100

            if total_protein_target > 0
            else 0
        )

        fats_percentage = (
            (
                    total_fats
                    / total_fats_target
            )
            * 100
            if total_fats_target > 0
            else 0
        )

        carbs_percentage = (
            (
                    total_carbs
                    / total_carbs_target
            )
            * 100
            if total_carbs_target > 0
            else 0
        )

        weekly_trend = []

        running_sum = 0
        count = 0

        for i in range(7):

            if weekly_all_eaten[i] > 0:
                running_sum += weekly_all_eaten[i]

                count += 1

            weekly_trend.append(
                running_sum / count
                if count > 0
                else 0
            )

        days = [
            "Monday",
            "Tuesday",
            "Wednesday",
            "Thursday",
            "Friday",
            "Saturday",
            "Sunday"
        ]

        weekly_calories = {
            days[i]: weekly_calories[i]
            for i in range(7)
        }

        weekly_target = {
            days[i]: weekly_target[i]
            for i in range(7)
        }

        weekly_trend = {
            days[i]: weekly_trend[i]
            for i in range(7)
        }

        weekly_all_eaten = {
            days[i]: weekly_all_eaten[i]
            for i in range(7)
        }

        result = {
            "unmatchedFoods": list(set(unmatched_foods)),
            "hasUnmatchedFoods": len(unmatched_foods) > 0,
            "weeklyCalories":
                weekly_calories,

            "weeklyTarget":
                weekly_target,

            "weeklyTrend":
                weekly_trend,

            "weeklyAllEaten":
                weekly_all_eaten,

            "progress":
                progress,

            "progressStatus":
                progress_status,

            "progressPercentage":
                progress_percentage,

            "proteinPercentage":
                protein_percentage,

            "fatsPercentage":
                fats_percentage,

            "carbsPercentage":
                carbs_percentage,
        }

        return clean_numpy(result)

    # MONTHLY PROGRESS

    def monthly_progress(self):

        today = self.today
        days_in_month = self.days_in_month
        meal_plan = self.meal_plan
        eaten_foods = self.eaten_foods
        weeks_in_month = 4
        monthly_calories = [0.0] * weeks_in_month
        monthly_target = [0.0] * weeks_in_month
        monthly_all_eaten = [0.0] * weeks_in_month

        monthly_protein = [0.0] * weeks_in_month
        monthly_fats = [0.0] * weeks_in_month
        monthly_carbs = [0.0] * weeks_in_month

        monthly_protein_target = [0.0] * weeks_in_month

        monthly_fats_target = [0.0] * weeks_in_month
        monthly_carbs_target = [0.0] * weeks_in_month

        weekly_protein_target = [0.0] * 7
        weekly_fats_target = [0.0] * 7
        weekly_carbs_target = [0.0] * 7
        weekly_target = [0.0] * 7

        days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

        # -----------------------
        # Weekly targets
        # -----------------------
        for day_index in range(7):
            day_name = days[day_index]
            day_info = meal_plan.get(day_name)
            if not day_info:
                continue

            weekly_target[day_index] = float(
                day_info.get("predicted_daily_calories", 0)
            )

            macros_target = day_info.get("daily_macros_target", {})
            weekly_protein_target[day_index] = float(macros_target.get("protein_g", 0))
            weekly_fats_target[day_index] = float(macros_target.get("fat_g", 0))
            weekly_carbs_target[day_index] = float(macros_target.get("carbs_g", 0))

        # Build meal plan food map

        meal_plan_foods_by_day = {}

        for day_index in range(7):
            day_name = days[day_index]
            day_info = meal_plan.get(day_name)

            if not day_info:
                continue

            meals = day_info.get("meals", {})
            foods_set = set()

            for meal in meals.values():
                for food in meal.get("items", []):
                    name = food.get("food_name", "")
                    if name:
                        foods_set.add(name.strip().lower())

            meal_plan_foods_by_day[day_index] = foods_set

        # Monthly macro targets

        days_since_start = (today - self.profile_start_date).days
        current_week = days_since_start // 7

        if current_week > 3:
            current_week = 3

        weekly_total_target = sum(weekly_target)
        weekly_total_protein = sum(weekly_protein_target)
        weekly_total_fats = sum(weekly_fats_target)
        weekly_total_carbs = sum(weekly_carbs_target)

        for i in range(weeks_in_month):
            monthly_target[i] = weekly_total_target
            monthly_protein_target[i] = weekly_total_protein
            monthly_fats_target[i] = weekly_total_fats
            monthly_carbs_target[i] = weekly_total_carbs

        # -----------------------
        # Food tracking (UPDATED LOGIC ONLY)
        # -----------------------
        ongoing_week = 1  # default
        unmatched_foods = []
        unmatched_date = self.today.date()
        for food in eaten_foods:
            try:
                if not food.get("consumed", False):
                    continue

                created_at = food.get("created_at")
                if not created_at:
                    continue

                try:
                    food_date = datetime.fromisoformat(created_at)
                except Exception:
                    food_date = datetime.fromisoformat(created_at.split(".")[0])

                week_index = (food_date - self.profile_start_date).days // 7
                if week_index < 0:
                    week_index = 0
                if week_index > 3:
                    week_index = 3

                ongoing_week = week_index + 1

                name = food.get("food_name", "").strip().lower()
                day_index = food_date.weekday()

                calories = float(food.get("calories", 0))
                protein = float(food.get("protein_g", 0))
                fats = float(food.get("fat_g", 0))
                carbs = float(food.get("carbs_g", 0))

                matched = False

                if day_index in meal_plan_foods_by_day:
                    for food_name in meal_plan_foods_by_day[day_index]:
                        if name in food_name or food_name in name:
                            matched = True
                            break

                monthly_all_eaten[week_index] += calories

                if matched:
                    monthly_calories[week_index] += calories

                    monthly_protein[week_index] += protein
                    monthly_fats[week_index] += fats
                    monthly_carbs[week_index] += carbs
                else:
                    if food_date.date() == unmatched_date:
                        unmatched_foods.append(name)
            except Exception:
                continue

        # -----------------------
        print(f"Ongoing Week: Week {ongoing_week}")
        # -----------------------

        monthly_trend = []
        running_sum = 0
        count = 0
        for i in range(weeks_in_month):
            if monthly_calories[i] > 0:
                running_sum += monthly_calories[i]
                count += 1
            monthly_trend.append(running_sum / count if count > 0 else 0)

        total_monthly_calories = sum(monthly_calories)
        total_monthly_target = sum(monthly_target)

        total_monthly_protein = sum(monthly_protein)
        total_monthly_fats = sum(monthly_fats)
        total_monthly_carbs = sum(monthly_carbs)

        total_monthly_protein_target = sum(monthly_protein_target)
        total_monthly_fats_target = sum(monthly_fats_target)
        total_monthly_carbs_target = sum(monthly_carbs_target)

        monthly_progress_percentage = (
            (total_monthly_calories / total_monthly_target) * 100
            if total_monthly_target > 0 else 0
        )

        monthly_protein_percentage = (
            (total_monthly_protein / total_monthly_protein_target) * 100
            if total_monthly_protein_target > 0 else 0
        )

        monthly_fats_percentage = (
            (total_monthly_fats / total_monthly_fats_target) * 100
            if total_monthly_fats_target > 0 else 0
        )

        monthly_carbs_percentage = (
            (total_monthly_carbs / total_monthly_carbs_target) * 100
            if total_monthly_carbs_target > 0 else 0
        )

        monthly_days = {}
        for i in range(weeks_in_month):
            key = f"Week {i + 1}"
            week_percentage = (
                (monthly_calories[i] / monthly_target[i]) * 100
                if monthly_target[i] > 0 else 0
            )

            monthly_days[key] = {
                "calories": monthly_calories[i],
                "target": monthly_target[i],
                "trend": monthly_trend[i],
                "allEaten": monthly_all_eaten[i],
                "percentage": week_percentage,

            }

        result = {
            "unmatchedFoods": list(set(unmatched_foods)),
            "hasUnmatchedFoods": len(unmatched_foods) > 0,
            "monthlyData": monthly_days,
            "progressPercentage": monthly_progress_percentage,
            "proteinPercentage": monthly_protein_percentage,
            "fatsPercentage": monthly_fats_percentage,
            "carbsPercentage": monthly_carbs_percentage,
        }

        return clean_numpy(result)
    # -------------------------------------------------
    # MAIN FUNCTION
    # -------------------------------------------------

    def track_progress(self):

        if self.period == "monthly":

            result = self.monthly_progress()

        else:

            result = self.weekly_progress()
        result = {
            **result,
            "ongoingWeek": (self.today - self.profile_start_date).days // 7 + 1,
        }
        return clean_numpy(result)
