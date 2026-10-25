# Vader5 Pro Mapper

[繁體中文](README.zh-TW.md)

A Windows utility for the **Flydigi Vader 5 Pro / 黑武士 5 Pro**. Remap buttons directly on the controller, configure native turbo, and compare physical input with the XInput output that games receive.

The physical **R3 click is always disabled on save**. Map a working button, such as M1, to R3 instead. The right stick's directional axes remain available. The editor uses mouse-operated lists, so a stuck R3 cannot hijack mapping selection.

This is a PowerShell + C# **Windows Forms** application. It edits on-board configuration; it does **not** patch or flash firmware.

## Compatibility

| Item | Status |
| --- | --- |
| Platform | 64-bit Windows, PowerShell 7 |
| Controller | Standard Vader 5 Pro, USB `37D7:2401`, model 130 |
| Firmware | **7.1.5.4 only**; other versions are rejected |
| Mapping layout | **3.2**, 840 bytes |
| Connection | USB cable tested; receiver support is unverified |
| Bluetooth / Switch mode | Not supported by this utility |
| Profiles | Edits the currently active PC profile, 1–4 |
| Interface language | Traditional Chinese; English command-line examples below |

## Features

- Remap standard buttons, C/Z, M1–M4 and LM/RM to gamepad outputs.
- Keep the physical R3 output disabled while assigning R3 to another button.
- Configure native turbo: off, hold-to-fire, or press-to-toggle, at 1–20 presses/second.
- Explicit controller-wide Turbo master switch. Changing it affects all profiles.
- Test raw physical buttons, mapped XInput buttons, stick axes and triggers side by side in separate panels.
- Back up mappings before each write, verify the complete read-back, and attempt rollback on failure.
- Preserve unrelated mapping fields and existing bindings when they are left unchanged.

**Measured example:** M1 → R3, hold-to-fire at 15 Hz produced 236 presses and releases during a continuous hold, approximately 14.95 presses/second. This verifies that combination on the listed firmware, not every button/mode combination.

## Setup

1. Install **64-bit PowerShell 7** and make `pwsh.exe` available on `PATH`.
2. Keep Flydigi Space Station installed. Its existing `hidapi.dll` is used; no vendor DLL is included in this repository.
3. Connect the controller with a USB data cable.
4. Fully exit Space Station, including its tray application.
5. Stop its background service from an **administrator PowerShell** before direct editing or testing:

   ```powershell
   Stop-Service -Name 'Flydigi Space Station Service'
   ```

   Concurrent access can change profiles or interfere with configuration transfers. The utility refuses to open the controller while this service is running. It does not change the service's startup type; stop it again after a reboot if necessary.

6. Double-click **`Launch.cmd`**, or run:

   ```powershell
   pwsh -NoProfile -STA -File .\VaderMappings.ps1
   ```

The native library is resolved from the standard Space Station installation directory. For a different installation location, set `VADER_HIDAPI_PATH` to the **existing local DLL** before launching.

For a nonstandard PowerShell location, create an untracked `runtime.local.cmd` alongside `Launch.cmd`:

```bat
set "VADER_PWSH=the-full-path-to-pwsh.exe"
```

Never commit that local override or device backups.

## Use the editor

| UI label | Meaning |
| --- | --- |
| 按鍵映射 | Button mapping |
| 重新讀取 | Reload the active profile |
| 輸出映射 | Output button |
| 連發模式 | Turbo mode |
| 關閉 / 按住連發 / 按一下切換 | Off / Hold / Toggle |
| 次／秒 | Presses per second |
| Turbo 總開關（所有配置） | Controller-wide Turbo master switch |
| 儲存到手把 | Save to controller |
| 按鍵測試 | Input test |

Choose an output and optional turbo mode, then save. The physical R3 row is locked. To use M1 as a normal R3, choose **M1 → R3**, turbo **Off**. To repeat R3 while holding M1, choose **Hold**, set a rate, and enable the Turbo master switch.

Use **Keep current setting** (`保留目前設定`) to preserve a macro or Space Station keyboard/mouse binding. This utility does not create or edit macros or keyboard/mouse actions. Extended-button turbo through the physical Turbo shortcut is separate from the direct on-board turbo settings used here.

Each save applies only to the active profile. Switching to another profile does not automatically apply the R3 workaround there. Backups are stored under `backups/` beside the script.

## Input testing

The test page displays two different signals:

- **Raw physical input:** includes extended buttons such as C, Z and M1. A faulty physical R3 may remain pressed here.
- **Game output:** the first connected XInput slot. R3 should be released at rest, and should follow whichever working button is mapped to R3.

If multiple XInput controllers are connected, disconnect the others to make the output comparison unambiguous. Leaving the test page or closing the application restores the previous raw-stream flags. After a crash or forced termination during testing, reconnect the controller to reset the temporary test mode.

## Command line

```powershell
# Read the active profile without changing mappings.
pwsh -NoProfile -File .\VaderMappings.ps1 -Mode Read

# Map M1 to a normal R3. Physical R3 remains disabled.
pwsh -NoProfile -File .\VaderMappings.ps1 -Mode Apply -Source M1 -Target R3 -TurboMode Off

# Native M1 -> R3 turbo, while held, at 15 presses/second.
pwsh -NoProfile -File .\VaderMappings.ps1 -Mode Apply -Source M1 -Target R3 -TurboMode Hold -TurboRate 15 -TurboMaster On

# Restore Z to its firmware default.
pwsh -NoProfile -File .\VaderMappings.ps1 -Mode Apply -Source Z -Target Default

# Compare raw input and game output for three seconds.
pwsh -NoProfile -File .\VaderMappings.ps1 -Mode Test -Seconds 3
```

`-TurboMode` accepts `Keep`, `Off`, `Hold` or `Toggle`. `-TurboMaster` accepts `Keep`, `On` or `Off`. Output aliases include `Default`, `Disabled` and `Keep`.

## Persistence and limitations

Saved mappings work without this utility running. A USB reconnect and M1/R3 input check have been verified. Open the utility only to edit mappings or view tests.

This is a workaround for game output, **not a repair of the physical switch**. Other software reading raw HID input can still see the faulty R3. The application intentionally blocks physical R3 from being re-enabled through its editor. Firmware bootloader, factory reset and device-identity write commands are not exposed.

Avoid concurrent editors. Do not unplug the controller while saving. A failed rollback is reported with the local backup location; do not assume a failed write was reverted successfully.

## Repository privacy

Only source, launchers, documentation and the license are tracked. `.gitignore` excludes device backups/dumps, logs, binaries, environment files and local runtime overrides. No device-specific snapshot or machine-specific runtime path belongs in the repository.

## Credits and license

The USB framing and mapping layout were referenced from the community [OpenVader protocol documentation](https://github.com/FilipVajgand/openvader/blob/9957cd10c779f361ef52a0058527424ebecf1699/docs/PROTOCOL.md). HIDAPI and Flydigi software retain their own licenses and are not redistributed here.

This project is unofficial and is not affiliated with Flydigi. Source code is available under the [MIT License](LICENSE).
