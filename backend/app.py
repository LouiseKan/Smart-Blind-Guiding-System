from flask import Flask, request, jsonify
from ultralytics import YOLO
from PIL import Image
import io
import traceback
import os

# --- 設定 ---
# ⚠️ 請確保 'best.pt' 存在於與此 app.py 相同的目錄
MODEL_PATH = "best.pt"

# 推論參數 (與 Flutter App 前面討論的最佳參數一致)
# 信心度閾值：只保留分數高於 40% 的結果
CONF_THRESHOLD = 0.4
# NMS IoU 閾值：用於合併重疊的邊界框
IOU_THRESHOLD = 0.3
# 輸入圖片尺寸：提高邊界框準確度
IMG_SIZE = 800
# --- 設定結束 ---

app = Flask(__name__)

# 載入模型
try:
    print(f"--- 載入模型: {MODEL_PATH} ---")
    model = YOLO(MODEL_PATH)
    # 這裡假設模型只有一個類別 {0: 'crosswalk'}，如果不是，需要手動覆寫
    if "crosswalk" not in model.names.values():
        model.names = {0: "crosswalk"}
    print(f"✅ 模型載入成功。類別: {model.names}")
except Exception as e:
    print(f"❌ 模型載入失敗，請檢查 {MODEL_PATH} 檔案。錯誤: {e}")
    # 如果模型載入失敗，應用程式將無法啟動
    exit(1)


@app.route("/detect_crosswalk", methods=["POST"])
def detect_crosswalk():
    """
    處理 POST 請求，接收圖片，執行 YOLOv8 偵測並回傳 JSON 結果。
    """

    # 1. 檢查是否有檔案上傳
    if "image" not in request.files:
        return jsonify({"error": "No image file provided in the 'image' field."}), 400

    file = request.files["image"]

    # 2. 讀取圖片
    try:
        # 使用 PIL 從位元組流讀取圖片
        img_bytes = file.read()
        img = Image.open(io.BytesIO(img_bytes))
        print(f"📥 成功接收圖片，尺寸: {img.size}")
    except Exception as e:
        print(f"❌ 圖片讀取失敗: {e}")
        return jsonify({"error": f"Invalid image file format: {e}"}), 400

    # 3. 執行推論
    try:
        # 這裡的 source 可以是 PIL Image 物件
        results = model(img, conf=CONF_THRESHOLD, iou=IOU_THRESHOLD, imgsz=IMG_SIZE)
    except Exception as e:
        print(f"❌ YOLO 推論時發生錯誤: {e}")
        traceback.print_exc()
        return jsonify({"error": "Internal model inference error."}), 500

    output_json = []

    # 4. 解析推論結果
    if results and results[0].boxes:
        result = results[0]

        # 這是前面討論的合併邏輯的前置步驟，但這裡只進行單框解析
        for box in result.boxes:
            bbox = box.xyxy[0].tolist()  # 取得 [x_min, y_min, x_max, y_max]
            cls_id = int(box.cls[0].item())
            conf = float(box.conf[0].item())

            # 使用模型載入時確認的類別名稱
            cls_name = model.names.get(cls_id, "crosswalk")

            output_json.append(
                {
                    "label": cls_name,
                    "confidence": round(conf, 4),
                    "bbox": {
                        "x_min": round(bbox[0], 2),
                        "y_min": round(bbox[1], 2),
                        "x_max": round(bbox[2], 2),
                        "y_max": round(bbox[3], 2),
                    },
                }
            )

    # ⚠️ 注意：這裡省略了前面討論的「多框合併」邏輯。
    # 如果您需要單一合併的框，請在上方邏輯之後加入合併程式碼，然後回傳合併後的結果。

    print(f"📤 偵測完成，回傳 {len(output_json)} 個物體。")

    # 5. 返回 JSON 結果
    # Flutter App 將接收到這個 JSON 列表
    return jsonify(output_json)


if __name__ == "__main__":
    # 啟動伺服器：host='0.0.0.0' 允許區域網路中的其他設備（例如手機）連線
    print("\n--- 啟動服務 ---")
    print("請確保手機和電腦在同一 Wi-Fi，且防火牆未阻擋 5000 端口。")
    app.run(host="0.0.0.0", port=5000, debug=True)
