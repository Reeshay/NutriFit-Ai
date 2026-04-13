import os
import re
import io
import torch
import torch.nn as nn
import pandas as pd
from torchvision import models, transforms
from PIL import Image, UnidentifiedImageError
from typing import List, Optional


BASE_CSV_DIR = r"D:\Nutrifit Backend"
FOOD_CSV_PATH = os.path.join(BASE_CSV_DIR, "foods.csv")
IMAGES_DIR = r"D:\Nutrifit Backend\Food Images"


class meal_snap:
    def __init__(self):
        self.device = torch.device(
            "cuda" if torch.cuda.is_available() else "cpu"
        )
        print("Using device:", self.device)

        self.df_food: Optional[pd.DataFrame] = None
        self.prototypes: Optional[torch.Tensor] = None
        self.proto_labels: List[str] = []

        self._init_model()
        self._load_food_csv()
        self._build_prototypes()

    # -------------------------
    # Model & transforms
    # -------------------------
    def _init_model(self):
        backbone = models.mobilenet_v3_large(weights="IMAGENET1K_V1").to(self.device)
        backbone.eval()

        self.feature_extractor = nn.Sequential(
            backbone.features,
            backbone.avgpool,
            nn.Flatten()
        ).to(self.device)

        for p in self.feature_extractor.parameters():
            p.requires_grad = False

        self.img_transform = transforms.Compose([
            transforms.Resize((224, 224)),
            transforms.ToTensor(),
            transforms.Normalize(
                mean=[0.485, 0.456, 0.406],
                std=[0.229, 0.224, 0.225],
            ),
        ])

    # -------------------------
    # Image → feature
    # -------------------------
    def _img_to_feature(self, img: Image.Image) -> torch.Tensor:
        x = self.img_transform(img).unsqueeze(0).to(self.device)
        with torch.no_grad():
            feat = self.feature_extractor(x)
        return torch.nn.functional.normalize(feat, dim=1).squeeze(0)

    def _img_to_feature_bytes(self, image_bytes: bytes) -> torch.Tensor:
        try:
            img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
        except UnidentifiedImageError:
            raise ValueError("Uploaded file is not a valid image")
        return self._img_to_feature(img)

    def _img_to_feature_path(self, img_path: str) -> torch.Tensor:
        if not os.path.exists(img_path):
            raise FileNotFoundError(f"Image not found: {img_path}")
        img = Image.open(img_path).convert("RGB")
        return self._img_to_feature(img)

    # -------------------------
    # Prototypes
    # -------------------------
    def _build_prototypes(self):
        if not os.path.exists(IMAGES_DIR):
            raise FileNotFoundError(f"Images directory not found: {IMAGES_DIR}")

        feats, labels = [], []

        for fname in sorted(os.listdir(IMAGES_DIR)):
            if not fname.lower().endswith((".jpg", ".jpeg", ".png")):
                continue

            label = os.path.splitext(fname)[0]
            path = os.path.join(IMAGES_DIR, fname)

            try:
                feat = self._img_to_feature_path(path)
                feats.append(feat)
                labels.append(label)
            except Exception as e:
                print(f"Skipping {fname}: {e}")

        self.prototypes = torch.stack(feats, dim=0)
        self.proto_labels = labels

        print(f"Built {len(labels)} prototypes")

    # -------------------------
    # CSV handling
    # -------------------------
    def _load_food_csv(self):
        df = pd.read_csv(FOOD_CSV_PATH)
        df.columns = df.columns.str.strip()

        required = ["food_name", "calories", "fat_g", "protein_g", "carbs_g"]
        missing = [c for c in required if c not in df.columns]
        if missing:
            raise KeyError(f"Missing columns in CSV: {missing}")

        df["meal_id"] = range(1, len(df) + 1)
        self.df_food = df

    @staticmethod
    def _normalize_name(s: str) -> str:
        s = s.lower().strip()
        s = re.sub(r"[_\-]", " ", s)
        return re.sub(r"\s+", " ", s)

    def _find_food_row(self, name: str):
        target = self._normalize_name(name)
        df_norm = self.df_food["food_name"].astype(str).apply(self._normalize_name)

        exact = df_norm == target
        if exact.any():
            return self.df_food[exact].iloc[0]

        contains = df_norm.str.contains(target)
        if contains.any():
            return self.df_food[contains].iloc[0]

        return None

    # -------------------------
    # Public prediction
    # -------------------------
    def estimate(self, image_bytes: bytes, quantity_g: float):
        feat = self._img_to_feature_bytes(image_bytes)
        sims = torch.matmul(self.prototypes, feat)

        idx = int(torch.argmax(sims))
        label = self.proto_labels[idx]
        similarity = float(sims[idx])

        row = self._find_food_row(label)
        if row is None:
            return {
                "predicted_label": label,
                "similarity": similarity,
                "nutrition_found": False,
            }

        factor = quantity_g / 100.0
        return {
            "predicted_label": label,
            "similarity": similarity,
            "nutrition_found": True,
            "meal_id": int(row["meal_id"]),
            "quantity_g": quantity_g,
            "calories": round(row["calories"] * factor, 2),
            "protein_g": round(row["protein_g"] * factor, 2),
            "carbs_g": round(row["carbs_g"] * factor, 2),
            "fat_g": round(row["fat_g"] * factor, 2),
        }


# =================================================
# GLOBAL INSTANCE (loaded once)
# =================================================
_model = meal_snap()


# =================================================
# BACKWARD-COMPATIBLE FUNCTION
# =================================================
def estimate_from_image_bytes(image_bytes: bytes, quantity_g: float):
    return _model.estimate(image_bytes, quantity_g)
