# Smart-Blind-Guiding-System

2025（114-1） 大學專題-智慧導盲系統 Edited by 甘 2025.12.7
***

## 前置作業（串接模型的 api）
1. 將 backend 資料夾獨立出來到 VS code 準備執行。
2. 在 beckend 目錄下的terminal 輸入 **pip install flask ultralytics Pillow requests**
3. 到此連結下載 best.pt，並放到backend資料夾中：<https://drive.google.com/file/d/1m0BP54Ljw-dRG2dEdLSf-rxfSSB27mKM/view?usp=drive_link>
4. 執行 **python app.py** 開啟本地端後端。
❗ 手機和電腦的網路務必相同，否則無法連上後端。

## Flutter 部分
1. 手機設定為開發者模式。
2. 防火牆設定： 務必在電腦的 Windows 防火牆中為 TCP Port 5000 新增傳入規則。
3. 網路設定檔： 確保電腦連線的網路設定檔是 「私人 (Private)」 而非「公用 (Public)」。
4. 在專案的 terminal 執行 **flutter pub get**
5. 開啟 lib/main.dart。
6. 將 _apiEndpoint 變數中的 IP 地址替換為您的電腦 IP (可以在 CMD 打指令 ipconfig 找到 IPv4 )：例如 192.168.55.1
7. 用 USB 線連接電腦和手機，即可在裝置設定連接並執行。

## 🤓正常情況下會有的輸出
1. VS code 會有正確連線 200 的輸出，並且顯示 偵測完成，回傳 n 個物體。
2. Flutter 會顯示 API 連線成功的訊息。
3. 只回傳一次是正常的，因為我不知道為什麼會這樣🤡
   



