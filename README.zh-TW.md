# Vader5 Pro Mapper

[English](README.md)

飛智 **黑武士 5 Pro / Vader 5 Pro** 的 Windows 改鍵與輸入測試工具，使用 PowerShell、C# 和 **Windows Forms**。

儲存時固定屏蔽**實體右搖桿下壓 R3 的遊戲輸出**，其方向軸仍保留。可用 M1 等正常按鍵代替 R3，並透過滑鼠下拉選單改鍵，避免故障 R3 搶走按鍵捕捉。

本工具修改的是板載配置，**沒有修改或刷寫韌體**。

## 相容範圍

| 項目 | 狀態 |
| --- | --- |
| 系統 | 64 位元 Windows、PowerShell 7 |
| 手把 | 標準版黑武士 5 Pro，USB `37D7:2401`、型號代碼 130 |
| 韌體 | 僅驗證 **7.1.5.4**，其他版本停止操作 |
| 配置格式 | **3.2**，840 位元組 |
| 連線 | 已測試 USB 有線；接收器尚未驗證 |
| 藍牙／Switch 模式 | 此工具不支援 |
| 配置 | 編輯目前啟用的 PC 配置 1～4 |

## 功能

- 一般按鍵、C/Z、M1～M4、LM/RM 的遊戲按鍵映射。
- 實體 R3 固定停用，其他按鍵仍可輸出 R3。
- 手把原生連發：關閉、按住連發、按一下切換；每秒 1～20 次。
- 明確的 Turbo 總開關，作用範圍為所有配置。
- 分別顯示原始實體按鍵和遊戲收到的 XInput 輸出，包含四軸與 LT/RT。
- 寫入前備份、完整讀回比較；失敗時嘗試還原並回報結果。

**實測範例：**M1 映射 R3、按住連發設定 15 Hz，持續按住時讀到 236 次按下／放開，約每秒 14.95 次。這證明該組合在上述韌體可用，不代表所有按鍵與模式組合都已實測。

## 啟動前準備

1. 安裝 64 位元 PowerShell 7，並讓 `pwsh.exe` 位於 `PATH`。
2. 保留飛智空間站的安裝；工具使用其現有的 `hidapi.dll`，儲存庫不附帶廠商 DLL。
3. 用 USB 資料線連接手把。
4. 完整退出飛智空間站，包含系統匣程式。
5. 用**系統管理員 PowerShell** 暫停背景服務，避免配置切換或傳輸干擾：

   ```powershell
   Stop-Service -Name 'Flydigi Space Station Service'
   ```

   服務執行時工具會拒絕直接操作。本工具不更改服務的啟動類型；電腦重新啟動後，使用工具前可能需要再停止服務。

6. 雙擊 `Launch.cmd`／`開啟改鍵工具.cmd`，或執行：

   ```powershell
   pwsh -NoProfile -STA -File .\VaderMappings.ps1
   ```

原生 DLL 預設從空間站的標準安裝目錄載入。若安裝於其他位置，可用環境變數 `VADER_HIDAPI_PATH` 指定現有的 `hidapi.dll`。

PowerShell 安裝位置若不在 PATH，可在工具旁建立不納入 Git 的 `runtime.local.cmd`：

```bat
set "VADER_PWSH=完整的-pwsh.exe-路徑"
```

## 改鍵與連發

1. 在「按鍵映射」選擇輸出。
2. 選擇「關閉」、「按住連發」或「按一下切換」，設定每秒次數。
3. 要使用連發時，確認 Turbo 總開關已勾選；此開關會影響所有配置。
4. 按「儲存到手把」。實體 R3 的整列固定停用，不能重新啟用。

例如 M1 → R3、連發關閉，就是一般 R3；改成按住連發與 15 次／秒，就會在持續按住 M1 時連發 R3。

未修改的設定會保留。「保留目前設定」可保留既有巨集或空間站鍵盤／滑鼠功能，本工具不建立或編輯這些功能。實體 Turbo 鍵的快捷操作與本工具直接寫入的連發設定是不同入口。

每次儲存只修改目前配置。切換其他配置時，不會自動把 R3 屏蔽套用過去。備份位於工具旁的 `backups/`。

## 按鍵測試

- **上方原始訊號：**可看到 C/Z/M1 等擴充鍵，故障的實體 R3 仍可能常亮。
- **下方遊戲輸出：**顯示第一個已連接的 XInput 槽位；放手時 R3 應放開，按下映射按鍵時才觸發。

有多支 XInput 手把時，先拔掉其他手把以避免看錯槽位。離開測試頁或正常關閉工具會恢復先前的串流狀態；若測試中程式崩潰或被強制關閉，重新插入手把可重置暫時測試模式。

## 命令列

```powershell
# 讀取目前配置。
pwsh -NoProfile -File .\VaderMappings.ps1 -Mode Read

# M1 代替一般 R3。
pwsh -NoProfile -File .\VaderMappings.ps1 -Mode Apply -Source M1 -Target R3 -TurboMode Off

# M1 按住時，每秒連發 R3 15 次。
pwsh -NoProfile -File .\VaderMappings.ps1 -Mode Apply -Source M1 -Target R3 -TurboMode Hold -TurboRate 15 -TurboMaster On

# Z 恢復預設。
pwsh -NoProfile -File .\VaderMappings.ps1 -Mode Apply -Source Z -Target Default

# 測試原始訊號與遊戲輸出。
pwsh -NoProfile -File .\VaderMappings.ps1 -Mode Test -Seconds 3
```

## 保存與限制

配置存入手把後，平常玩遊戲不用開工具。已驗證拔插後設定仍有效，以及 M1 按放能正常產生 R3 輸出。

這是屏蔽遊戲輸出的繞法，不是修復實體開關；讀取原始 HID 的其他程式仍會看到故障 R3。工具沒有提供韌體刷寫、恢復原廠或改寫裝置識別碼的功能。

避免同時使用其他改鍵程式，儲存時不要拔掉手把。若還原失敗，程式會顯示本機備份位置；不能把寫入失敗當成已還原成功。

## 隱私、來源與授權

儲存庫只追蹤原始碼、啟動檔、文件與授權。裝置備份、資料傾印、紀錄、二進位依賴、環境檔和本機執行路徑覆寫檔均由 `.gitignore` 排除。

USB 協議與配置格式參考社群 [OpenVader 協議文件](https://github.com/FilipVajgand/openvader/blob/9957cd10c779f361ef52a0058527424ebecf1699/docs/PROTOCOL.md)。HIDAPI 與廠商軟體保有各自授權，本專案不重新散布其二進位檔。

本專案非飛智官方作品，原始碼採用 [MIT License](LICENSE)。
