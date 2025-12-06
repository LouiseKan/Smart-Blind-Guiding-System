import requests
import json
import os

# --- 設定 ---
# ⚠️ 請確保這張測試圖片存在於與 app.py 相同的資料夾
TEST_IMAGE_NAME = "zebra_crossings.jpg"
# 假設您的 app.py 運行在本地 5000 端口
API_URL = "http://127.0.0.1:5000/detect_crosswalk"
# --- 設定結束 ---


def test_detection_api():
    if not os.path.exists(TEST_IMAGE_NAME):
        print(
            f"❌ 錯誤: 找不到測試圖片 {TEST_IMAGE_NAME}。請在相同目錄放置一張圖片並命名為此名稱。"
        )
        return

    print(f"--- 1. 準備發送圖片: {TEST_IMAGE_NAME} ---")

    try:
        # 開啟圖片檔案並準備 multipart/form-data
        with open(TEST_IMAGE_NAME, "rb") as f:
            files = {
                "image": (TEST_IMAGE_NAME, f, "image/jpeg")
            }  # 檔案欄位名稱 'image' 必須與 app.py 匹配

            # 發送 POST 請求
            response = requests.post(API_URL, files=files)

        print("\n--- 2. 接收到 API 回應 ---")
        print(f"HTTP Status Code: {response.status_code}")

        if response.status_code == 200:
            # 成功！解析並印出 JSON 結果
            try:
                data = response.json()
                print("✅ 偵測成功！回傳 JSON 數據如下:")
                print(json.dumps(data, indent=4, ensure_ascii=False))

                if not data:
                    print("⚠️ JSON 為空，表示模型沒有檢測到任何物體 (或信心度太低)。")
                else:
                    print(f"總共偵測到 {len(data)} 個物體。")

            except json.JSONDecodeError:
                print("❌ 錯誤: API 回傳的不是有效的 JSON 格式。")
                print(f"原始回應內容:\n{response.text}")
        else:
            # 伺服器內部錯誤 (500) 或客戶端錯誤 (400)
            print(f"❌ API 請求失敗。回應內容:\n{response.text}")

    except requests.exceptions.ConnectionError:
        print("❌ 連線錯誤: 請確保 app.py 服務正在運行 (Step 1)。")
    except Exception as e:
        print(f"發生未知錯誤: {e}")


if __name__ == "__main__":
    test_detection_api()
