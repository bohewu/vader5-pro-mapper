# Vader5 Pro Mapper

[繁體中文](README.zh-TW.md)

A Windows utility for the **Flydigi Vader 5 Pro / 黑武士 5 Pro**. Remap buttons on the controller, configure native turbo, and compare physical input with the XInput output that games receive.

Built with PowerShell, C# and **Windows Forms**. Settings are saved on the controller; the application only needs to run when editing or testing. It edits configuration without patching or flashing firmware.

## Compatibility

| Item | Status |
| --- | --- |
| Platform | 64-bit Windows, 64-bit PowerShell 7.2 or later |
| Controller | Standard Vader 5 Pro, USB `37D7:2401`, model 130 |
| Firmware | **7.1.5.4 only**; other versions are rejected |
| Mapping layout | **3.2**, 840 bytes |
| Connection | USB cable and USB 2.4 GHz receiver tested |
| Bluetooth / Switch mode | Not supported |
| Profiles | Edits the currently active PC profile, 1–4 |
| Interface language | Traditional Chinese; English CLI examples below |

Testing has used **one controller on one PC**. Receiver reading, a mapping write, complete read-back, exact restoration, and raw/XInput monitoring have been checked. Cable persistence after reconnect and native turbo have also been checked. This is not a compatibility guarantee for every PC, firmware or receiver revision.

**Macro testing:** USB cable, M3 triggering an A/B sequence, with once, hold and toggle playback. Complete macro/mapping read-backs and exact restoration passed after each test. Macro writes through the 2.4 GHz receiver have not yet been tested.

Saved mappings are expected to follow the controller to another PC. Running this editor there still requires the runtime, native library and compatible device mode below. Drivers, competing software and multiple connected controllers can affect detection and test results. A second PC has not been tested.

## Features

- Remap standard buttons, C/Z, M1–M4 and LM/RM to gamepad outputs.
- Restore a button to its firmware default or disable its gamepad output, including L3/R3 clicks.
- Native turbo: off, hold-to-fire, or press-to-toggle, at 1–20 presses/second.
- On-board macros: gamepad press/release sequences with delays, trigger selection, and once/hold/toggle playback.
- Explicit controller-wide Turbo master switch, which affects all profiles.
- Separate raw physical and mapped XInput panels, including stick axes and triggers.
- Backup before writing, complete read-back comparison, and rollback attempt on failure.
- Preserve unedited entries and fields. Startup and reload apply no preset.
- Unsaved-change status and confirmation before discarding edits on reload or close.

Native turbo on an extended button has been measured at approximately 14.95 presses/second with a 15 Hz setting. This checks one combination on the listed firmware; not every button and playback mode has been tested.

## Setup

1. Install **64-bit PowerShell 7.2 or later** and make `pwsh.exe` available on `PATH`.
2. Keep Flydigi Space Station installed. Its existing `hidapi.dll` is used; no vendor DLL is included here.
3. Connect one controller with a USB data cable or its USB 2.4 GHz receiver. Keep it powered on.
4. Fully exit Space Station, including its tray application.
5. Stop its background service from an **administrator PowerShell**:

   ```powershell
   Stop-Service -Name 'Flydigi Space Station Service'
   ```

   Concurrent access can change profiles or interfere with transfers. The utility refuses to open the controller while this service is running. It does not change the service's startup type; stopping it again may be necessary after reboot. To return to Space Station, close this utility and start that service again.

6. Double-click **`Launch.cmd`**, or run:

   ```powershell
   pwsh -NoProfile -STA -File .\VaderMappings.ps1
   ```

The native library is resolved from the standard Space Station installation directory. For a different location, set `VADER_HIDAPI_PATH` to the **existing local DLL** before launching. Match the DLL architecture to the PowerShell process.

For a nonstandard PowerShell location, create an untracked `runtime.local.cmd` alongside `Launch.cmd`:

```bat
set "VADER_PWSH=the-full-path-to-pwsh.exe"
```

Never commit that override or device backups.

## Use the editor

| UI label | Meaning |
| --- | --- |
| 按鍵映射 / 輸出映射 | Button mapping / Output button |
| 重新讀取 | Reload the active profile |
| 保留目前設定 / 預設 | Keep current setting / Firmware default |
| 停用遊戲輸出 | Disable gamepad output |
| 連發模式 | Turbo mode |
| 關閉 / 按住連發 / 按一下切換 | Off / Hold / Toggle |
| 次／秒 | Presses per second |
| Turbo 總開關（所有配置） | Controller-wide Turbo master switch |
| 儲存到手把 / 按鍵測試 | Save to controller / Input test |

Choose an output and optional turbo mode, then save. For example, choose **C → A** for ordinary remapping, or **M1 → RB**, **Hold**, 15 presses/second and enable the Turbo master switch for native turbo. No button has a mandatory mapping or a locked disable rule.

**Disable gamepad output** uses the firmware's non-gamepad target. It does not erase an existing Space Station keyboard/mouse binding: that binding can still produce keyboard/mouse events. **Keep current setting** preserves an existing macro or other unsupported target. Use the **巨集 (Macros)** tab to edit macros. Keyboard/mouse binding editing is not implemented.

Extended-button turbo through the physical Turbo shortcut is separate from these direct on-board settings. For turbo on an extended button, first choose a regular gamepad output.

Only **Save to controller** applies edits. Each save affects the active profile; the Turbo master switch affects all profiles. Unedited bindings and other fields are retained. Backups are stored under `backups/` beside the script; hover over the save status to see the backup location.

## On-board macros

1. Open **巨集 (Macros)**. The active profile's macros are loaded without writing.
2. Click **新增巨集 (New macro)**, or select an existing macro.
3. Choose a physical trigger, name, playback mode and repeat interval. Saving assigns that trigger to macro playback, replacing its current gamepad mapping.
4. Edit the step table: **距前一步等待 ms** is the delay **before** that step; **遊戲按鍵** is the gamepad output; **動作** is press or release. The first step may have a zero delay. Overlapping held buttons are supported.
5. **加入 A 按放** adds an editable A press/release pair. Change the output cells to other buttons; use delete/up/down to edit the order.
6. Click **儲存巨集到手把 (Save macros to controller)**. The tool backs up both stores, writes the macros and trigger mapping, reloads the profile, and verifies both complete read-backs. On failure it attempts to restore both stores and reports the result.

Example: `0 ms A press`, `100 ms A release`, `200 ms B press`, `100 ms B release` produces an A tap, then a B tap, ending 400 ms after the sequence starts.

Playback modes are **單次** (once per press), **按住重複** (repeat while held) and **切換重複** (press again to stop). **重複間隔 ms** is the pause between repeats, independent of the step delays and Turbo master switch.

Each profile holds at most **10 macros**, sharing **1632 record bytes**; a record uses 32 bytes plus 4 per step. Each macro allows up to 256 steps, with a maximum timeline of 65535 ms. Names allow **20 UTF-8 bytes**, so Chinese characters usually consume three bytes each. The editor rejects duplicate triggers, unsupported output keys, excess capacity, reversed/overflowing time, and sequences that leave a key pressed.

Deleting a macro restores its trigger to the firmware default **only if that trigger still maps to the deleted macro**. A later ordinary remap is retained. Unedited macro records and unrelated mapping fields are preserved. Save or reload drafts before switching between the two editing pages; the input-test page shows the configuration currently stored on the controller.

Macros run on the controller without this app open. This editor supports standard gamepad button outputs only, without keyboard/mouse events, analog stick movement, recording, or import/export. Macros are separate from native turbo.

## Input testing

- **Raw physical input:** physical buttons, including C, Z and M1–M4, before gamepad remapping.
- **Game output:** the first connected XInput slot, after the controller's mapping and turbo.

Different readings can be expected when a button is remapped, disabled or using turbo. Compare them with the intended configuration. Disconnect other XInput controllers to make the comparison unambiguous.

Leaving the test page or closing the application restores the previous raw-stream flags. After a crash or forced termination during testing, reconnect the controller to reset the temporary test mode.

## Command line

```powershell
# Read the active profile without changing mappings.
pwsh -NoProfile -File .\VaderMappings.ps1 -Mode Read

# Map C to A without turbo.
pwsh -NoProfile -File .\VaderMappings.ps1 -Mode Apply -Source C -Target A -TurboMode Off

# Native M1 -> RB turbo, while held, at 15 presses/second.
pwsh -NoProfile -File .\VaderMappings.ps1 -Mode Apply -Source M1 -Target RB -TurboMode Hold -TurboRate 15 -TurboMaster On

# Disable Z's gamepad output, or restore its firmware default.
pwsh -NoProfile -File .\VaderMappings.ps1 -Mode Apply -Source Z -Target Disabled -TurboMode Off
pwsh -NoProfile -File .\VaderMappings.ps1 -Mode Apply -Source Z -Target Default

# Compare raw input and game output for three seconds.
pwsh -NoProfile -File .\VaderMappings.ps1 -Mode Test -Seconds 3
```

`-TurboMode` accepts `Keep`, `Off`, `Hold` or `Toggle`. `-TurboMaster` accepts `Keep`, `On` or `Off`. Output aliases include `Default`, `Disabled` and `Keep`.

## Limitations

Keyboard/mouse binding editing is not implemented. Firmware bootloader, factory reset and device-identity write commands are not exposed. Macro playback modes use the reverse-engineered protocol; see the tested scope above rather than assuming every button and timing combination is verified.

Avoid concurrent editors. Keep the wireless controller in range and do not disconnect it while saving. A failed rollback is reported with the local backup location; do not assume a failed write was reverted successfully.

The tested receiver forwards a firmware-info reply whose checksum does not match. A narrowly scoped compatibility exception accepts that known read-only reply for the listed model and firmware. Configuration packets and write acknowledgements still require valid checksums. Receiver read timeouts have bounded retries; write commands are not automatically retried.

## Repository privacy

Only source, launchers, documentation and the license are tracked. `.gitignore` excludes device backups/dumps, logs, binaries, environment files and local runtime overrides. Device-specific snapshots and machine-specific runtime paths do not belong in the repository.

## Credits and license

The USB framing and mapping layout were referenced from the community [OpenVader protocol documentation](https://github.com/FilipVajgand/openvader/blob/9957cd10c779f361ef52a0058527424ebecf1699/docs/PROTOCOL.md). HIDAPI and Flydigi software retain their own licenses and are not redistributed here.

Run the hardware-independent macro codec checks with `pwsh -NoProfile -File .\tests\Test-Macros.ps1`.

This project is unofficial and is not affiliated with Flydigi. Source code is available under the [MIT License](LICENSE).
