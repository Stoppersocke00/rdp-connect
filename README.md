# RDP Connect

**RDP Connect** is a lightweight, customizable RDP session launcher built entirely in PowerShell.  
It provides a simple GUI for launching remote desktop sessions, managing multiple display options, and even supports a full **kiosk mode** to lock down a Windows session to only the RDP client GUI.

---

## 🚀 Features

- Start RDP sessions via GUI with:
  - Custom hostname or IP
  - Optional `.rdp` configuration file
  - Fullscreen or windowed mode
  - Multi-monitor support
- System tray integration with context menu
- Persistent configuration stored as JSON
- Built-in kiosk mode (launches instead of `explorer.exe`)
- Optional startup shortcut creation
- Configurable via `Ctrl + Alt + C` hotkey

---

## 🖥️ Kiosk Mode

When kiosk mode is enabled:

- Windows shell is changed to `rdp-connect.exe`
- Only the RDP launcher GUI is shown at logon
- Desktop and taskbar are hidden
- Admin privileges are required to apply the shell change
- Applied via Registry:  
  `HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\Shell`

When disabled, the system is restored to the default `explorer.exe` shell.

---

## 🛠 Requirements

- PowerShell 5.1+
- Windows with RDP support (`mstsc.exe`)
- Admin rights required to apply kiosk mode

---

## ⚙️ Installation

### 1. One-time Setup

Install the PS2EXE module with the following command (used to compile the script):
```powershell
Install-Module -Name ps2exe -Scope CurrentUser
```

### 2. Build the EXE

Create a standalone executable version by running this PS-script:
```powershell
.build.ps1
```

### 3. Run

Start the application:
- Run `rdp-connect.exe` after building or use the given `rdp-connect.exe`
- Or use `rdp-connect.ps1` directly from PowerShell (not recommended)

---

## 🧪 First Run Behavior

- On first launch (no config file present):
  - A default config is created at:  
    `%APPDATA%\RDP-Connect\Config`
  - A desktop shortcut to the current executable is created
- When enabling kiosk mode:
  - If not already in `C:\Windows\System32`, the current executable is copied there
  - The existing desktop shortcut is replaced with one pointing to the System32 version

---

## 🧰 Development Notes

- Configuration is stored as a JSON file in:  
  `%APPDATA%\RDP-Connect\Config`
- Kiosk mode changes are handled in a single admin-elevated PowerShell process that:
  - Updates the shell registry key
  - Copies the EXE to `System32` (if needed)
  - Replaces the desktop shortcut

---
