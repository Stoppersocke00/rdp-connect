Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Web.Extensions

$ConfigPath = "$env:AppData\RDP-Connect\Config.json"
$DesktopPath = [Environment]::GetFolderPath("Desktop")
$System32Path = "$env:windir\System32"
$ExeName = "rdp-connect.exe"
$SystemExePath = Join-Path $System32Path $ExeName
$ShortcutPath = Join-Path $DesktopPath "RDP Connect.lnk"

if ($MyInvocation.MyCommand.Path) {
    # Wenn als PS1 gestartet → Pfad zum Skript
    $LocalExePath = $MyInvocation.MyCommand.Path
} else {
    # Wenn als EXE gestartet → Pfad zur laufenden EXE
    $LocalExePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
}


# API Import für ExtractIconEx
Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @"
    [System.Runtime.InteropServices.DllImport("shell32.dll", CharSet = System.Runtime.InteropServices.CharSet.Auto)]
    public static extern int ExtractIconEx(string szFileName, int nIconIndex, out IntPtr phiconLarge, out IntPtr phiconSmall, int nIcons);
"@

function Get-IconFromDll {
    param ([string]$dllPath, [int]$iconIndex, [int]$size = 16)
    $ptrLarge = [IntPtr]::Zero; $ptrSmall = [IntPtr]::Zero
    [Win32.NativeMethods]::ExtractIconEx($dllPath, $iconIndex, [ref]$ptrLarge, [ref]$ptrSmall, 1) | Out-Null
    if ($ptrSmall -ne [IntPtr]::Zero) {
        $icon = [System.Drawing.Icon]::FromHandle($ptrSmall)
        return New-Object System.Drawing.Bitmap $icon.ToBitmap(), $size, $size
    }
    return $null
}

function Get-FormIcon {
    param ([string]$dllPath, [int]$iconIndex)
    $ptrLarge = [IntPtr]::Zero; $ptrSmall = [IntPtr]::Zero
    [Win32.NativeMethods]::ExtractIconEx($dllPath, $iconIndex, [ref]$ptrLarge, [ref]$ptrSmall, 1) | Out-Null
    if ($ptrLarge -ne [IntPtr]::Zero) {
        return [System.Drawing.Icon]::FromHandle($ptrLarge)
    }
    return $null
}

New-Item -ItemType Directory -Force -Path (Split-Path $ConfigPath) | Out-Null

function New-DesktopShortcut($targetPath) {
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath = $targetPath
    $Shortcut.WorkingDirectory = Split-Path $targetPath
    $Shortcut.IconLocation = "$targetPath,0"
    $Shortcut.Save()
}

function Load-Config {
    if (-not (Test-Path $ConfigPath)) {
        New-Item -ItemType Directory -Force -Path (Split-Path $ConfigPath) | Out-Null

        if (-not (Test-Path $ShortcutPath)) {
            New-DesktopShortcut -targetPath $LocalExePath
        }

        return [PSCustomObject]@{
            RdpServer         = "localhost"
            RdpFile           = ""
            Gateway           = ""
            Fullscreen        = $true
            Width             = ""
            Height            = ""
            Admin             = $false
            Public            = $true
            MultiMon          = $true
            RestrictedAdmin   = $false
            RemoteGuard       = $false
            Prompt            = $true
            ShadowID          = ""
            Control           = $false
            NoConsentPrompt   = $false
            KioskMode         = $false
        }
    } else {
        $json = Get-Content $ConfigPath -Raw | ConvertFrom-Json

        $defaultValues = @{
            RdpServer       = "localhost"
            RdpFile         = ""
            Gateway         = ""
            Fullscreen      = $true
            Width           = ""
            Height          = ""
            Admin           = $false
            Public          = $false
            MultiMon        = $true
            RestrictedAdmin = $false
            RemoteGuard     = $false
            Prompt          = $true
            ShadowID        = ""
            Control         = $false
            NoConsentPrompt = $false
            KioskMode       = $false
            DisablePasswordSaving = $false
        }

        foreach ($key in $defaultValues.Keys) {
            if (-not ($json.PSObject.Properties.Name -contains $key)) {
                $json | Add-Member -MemberType NoteProperty -Name $key -Value $defaultValues[$key]
            }
        }

        return $json
    }
}

function Save-Config($config) {
    $config | ConvertTo-Json -Depth 3 | Set-Content -Path $ConfigPath -Encoding UTF8
}

function Show-ConfigForm {
    $config = Load-Config

    $form = New-Object Windows.Forms.Form
    $form.Text = "RDP Konfiguration"
    $form.Size = New-Object Drawing.Size(600, 620)
    $form.StartPosition = "CenterScreen"
    $form.TopMost = $true
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    $dll = "C:\Windows\System32\imageres.dll"
    $form.Icon = Get-FormIcon -dllPath $dll -iconIndex 64


    [int]$y = 20

    function Add-Label($text, [ref]$yRef) {
        $label = New-Object Windows.Forms.Label
        $label.Text = $text
        $label.Location = "10,$($yRef.Value)"
        $label.AutoSize = $true
        $form.Controls.Add($label)
        $yRef.Value += 30
        return $label
    }

    function Add-Textbox($x, [ref]$yRef, $value, $optional = $true) {
        $tb = New-Object Windows.Forms.TextBox
        $tb.Size = '350,20'
        $tb.Location = "$x,$($yRef.Value - 30)"

        if ($optional -and [string]::IsNullOrWhiteSpace($value)) {
            $tb.ForeColor = [System.Drawing.Color]::Gray
            $tb.Text = "(optional)"
            $tb.Tag = "placeholder"

            $tb.Add_GotFocus({
                if ($tb.Tag -eq "placeholder") {
                    $tb.Text = ""
                    $tb.ForeColor = [System.Drawing.Color]::Black
                    $tb.Tag = ""
                }
            })

            $tb.Add_LostFocus({
                if ([string]::IsNullOrWhiteSpace($tb.Text)) {
                    $tb.Text = "(optional)"
                    $tb.ForeColor = [System.Drawing.Color]::Gray
                    $tb.Tag = "placeholder"
                }
            })
        } else {
            $tb.Text = $value
            $tb.Tag = ""
        }

        $form.Controls.Add($tb)
        return $tb
    }

    function Add-Checkbox($labelText, [ref]$yRef, $checked) {
        $label = New-Object Windows.Forms.Label
        $label.Text = $labelText
        $label.Location = New-Object System.Drawing.Point(10, $yRef.Value)
        $label.AutoSize = $true
        $form.Controls.Add($label)

        $cbY = $yRef.Value - 3
        $cb = New-Object Windows.Forms.CheckBox
        $cb.Location = New-Object System.Drawing.Point(250, $cbY)
        $cb.Checked = $checked
        $form.Controls.Add($cb)

        $yRef.Value += 30
        return $cb
    }

    # RDP Server
    Add-Label "RDP-Server:" ([ref]$y) | Out-Null
    $txtServer = Add-Textbox 180 ([ref]$y) $config.RdpServer $false

    # RDP-Datei
    Add-Label "RDP-Datei:" ([ref]$y) | Out-Null
    $txtFile = Add-Textbox 180 ([ref]$y) $config.RdpFile

    $picBrowse = New-Object Windows.Forms.PictureBox
    $picBrowse.Size = '20,20'
    $picBrowse.Location = '540,' + ($y - 30)
    $picBrowse.Image = Get-IconFromDll -dllPath $dll -iconIndex 203
    $picBrowse.SizeMode = 'StretchImage'
    $picBrowse.Cursor = [System.Windows.Forms.Cursors]::Hand
    $picBrowse.Add_Click({
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Filter = "RDP-Dateien (*.rdp)|*.rdp"
        if ($dialog.ShowDialog() -eq "OK") {
            $txtFile.Text = $dialog.FileName
            $txtFile.ForeColor = [System.Drawing.Color]::Black
            $txtFile.Tag = ""
        }
    })

    $form.Controls.Add($picBrowse)

    # Gateway
    Add-Label "Gateway:" ([ref]$y) | Out-Null
    $txtGateway = Add-Textbox 180 ([ref]$y) $config.Gateway

    # Breite
    Add-Label "Fensterbreite:" ([ref]$y) | Out-Null
    $txtWidth = Add-Textbox 180 ([ref]$y) $config.Width

    # Höhe
    Add-Label "Fensterhöhe:" ([ref]$y) | Out-Null
    $txtHeight = Add-Textbox 180 ([ref]$y) $config.Height

    # Shadow-ID
    Add-Label "Shadow-ID:" ([ref]$y) | Out-Null
    $txtShadow = Add-Textbox 180 ([ref]$y) $config.ShadowID

    # Checkbox-Parameter
    $chkFullscreen      = Add-Checkbox "Vollbildmodus:" ([ref]$y) $config.Fullscreen
    $chkMultiMon        = Add-Checkbox "Mehrere Monitore:" ([ref]$y) $config.MultiMon
    $chkPrompt          = Add-Checkbox "Anmeldeaufforderung:" ([ref]$y) $config.Prompt
    $chkPublic          = Add-Checkbox "Öffentlicher Modus:" ([ref]$y) $config.Public
    $chkAdmin           = Add-Checkbox "Administratorsitzung:" ([ref]$y) $config.Admin
    $chkRestricted      = Add-Checkbox "Eingeschränkter Admin:" ([ref]$y) $config.RestrictedAdmin
    $chkRemoteGuard     = Add-Checkbox "Remote Guard:" ([ref]$y) $config.RemoteGuard
    $chkControl         = Add-Checkbox "Steuerung erlauben:" ([ref]$y) $config.Control
    $chkNoConsentPrompt = Add-Checkbox "Ohne Zustimmung:" ([ref]$y) $config.NoConsentPrompt

    $chkKiosk = Add-Checkbox "Kiosk-Modus" ([ref]$y) $config.KioskMode
    $chkKiosk.Add_CheckedChanged({
        if ($chkKiosk.Checked -ne $config.KioskMode) {
            [System.Windows.Forms.MessageBox]::Show("Die Änderung wird nach einem Neustart aktiv und erfordert Administratorrechte beim Speichern.", "Hinweis", "OK", "Information")
        }
    })

    $chkDisablePwSave = Add-Checkbox "Passwortspeicherung deaktivieren" ([ref]$y) $config.DisablePasswordSaving
    $chkDisablePwSave.Add_CheckedChanged({
        if ($chkDisablePwSave.Checked -ne $config.DisablePasswordSaving) {
            [System.Windows.Forms.MessageBox]::Show("Passwortspeicherung wird deaktiviert. Diese Änderung erfordert Administratorrechte und wird beim Speichern wirksam.", "Hinweis", "OK", "Information")
        }
    })


    # Buttons
    $btnSave = New-Object Windows.Forms.Button
    $btnSave.Text = "Speichern"
    $btnSave.Location = '180,' + $y
    $btnSave.Size = '100,30'
    $btnSave.Add_Click({

    $originalConfig = Load-Config

    # Texte auslesen mit Platzhalterprüfung
    $config.RdpServer       = $txtServer.Text
    $config.RdpFile         = if ($txtFile.Tag -eq "placeholder") { "" } else { $txtFile.Text }
    $config.Gateway         = if ($txtGateway.Tag -eq "placeholder") { "" } else { $txtGateway.Text }
    $config.Width           = if ($txtWidth.Tag -eq "placeholder") { "" } else { $txtWidth.Text }
    $config.Height          = if ($txtHeight.Tag -eq "placeholder") { "" } else { $txtHeight.Text }
    $config.ShadowID        = if ($txtShadow.Tag -eq "placeholder") { "" } else { $txtShadow.Text }

    # Checkbox-Werte
    $config.Fullscreen      = $chkFullscreen.Checked
    $config.MultiMon        = $chkMultiMon.Checked
    $config.Prompt          = $chkPrompt.Checked
    $config.Public          = $chkPublic.Checked
    $config.Admin           = $chkAdmin.Checked
    $config.RestrictedAdmin = $chkRestricted.Checked
    $config.RemoteGuard     = $chkRemoteGuard.Checked
    $config.Control         = $chkControl.Checked
    $config.NoConsentPrompt = $chkNoConsentPrompt.Checked
    $config.KioskMode       = $chkKiosk.Checked
    $config.DisablePasswordSaving = $chkDisablePwSave.Checked

    $kioskChanged     = $originalConfig.KioskMode -ne $chkKiosk.Checked
    $pwSaveChanged    = $originalConfig.DisablePasswordSaving -ne $chkDisablePwSave.Checked

    if ($kioskChanged -or $pwSaveChanged) {
        $adminScript = ""

        if ($kioskChanged) {
            $desiredShell = if ($chkKiosk.Checked) { "rdp-connect.exe" } else { "explorer.exe" }

            if ($chkKiosk.Checked) {
                # Kiosk aktivieren
                $adminScript += @"
`$regPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Set-ItemProperty -Path `$regPath -Name 'Shell' -Value 'rdp-connect.exe'

`$systemExe = '$SystemExePath'
if (-not (Test-Path `$systemExe)) {
    `$source = '$LocalExePath'
    Copy-Item -Path `$source -Destination `$systemExe -Force
}

`$desktop = [Environment]::GetFolderPath('Desktop')
`$shortcutPath = Join-Path `$desktop 'RDP Connect.lnk'
if (Test-Path `$shortcutPath) { Remove-Item `$shortcutPath -Force }

`$WshShell = New-Object -ComObject WScript.Shell
`$Shortcut = `$WshShell.CreateShortcut(`$shortcutPath)
`$Shortcut.TargetPath = '$SystemExePath'
`$Shortcut.WorkingDirectory = Split-Path '$SystemExePath'
`$Shortcut.IconLocation = '$SystemExePath,0'
`$Shortcut.Save()
"@
            } else {
                # Kiosk deaktivieren
                $adminScript += @"
`$regPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Set-ItemProperty -Path `$regPath -Name 'Shell' -Value 'explorer.exe'
"@
            }
        }

        if ($pwSaveChanged) {
            $regPwPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
            $disablePw = if ($chkDisablePwSave.Checked) { 1 } else { 0 }

            $adminScript += @"
`$pwPath = '$regPwPath'
if (-not (Test-Path `$pwPath)) {
    New-Item -Path `$pwPath -Force | Out-Null
}
Set-ItemProperty -Path `$pwPath -Name 'DisablePasswordSaving' -Type DWord -Value $disablePw
"@
        }

        $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($adminScript))
        Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -NoProfile -EncodedCommand $encoded" -Verb RunAs

        if ($kioskChanged) {
            if ($chkKiosk.Checked) {
                [System.Windows.Forms.MessageBox]::Show("Kiosk-Modus wurde aktiviert. Änderungen werden nach dem nächsten Neustart aktiv. Mit Strg + Alt + C kann der Kiosk-Modus wieder deaktiviert werden.", "Kiosk-Modus", "OK", "Information")
            } else {
                [System.Windows.Forms.MessageBox]::Show("Kiosk-Modus wurde deaktiviert. Der normale Desktop wird beim nächsten Neustart geladen.", "Kiosk-Modus", "OK", "Information")
            }
        }

        if ($pwSaveChanged -and $chkDisablePwSave.Checked) {
            [System.Windows.Forms.MessageBox]::Show("Passwortspeicherung wurde deaktiviert. Benutzer müssen sich künftig bei jeder RDP-Sitzung erneut anmelden.", "Passwortspeicherung", "OK", "Information")
        }
    }

    Save-Config -config $config
    $form.Close()
})
    $form.Controls.Add($btnSave)

    $btnCancel = New-Object Windows.Forms.Button
    $btnCancel.Text = "Abbrechen"
    $btnCancel.Location = '300,' + $y
    $btnCancel.Size = '100,30'
    $btnCancel.Add_Click({ $form.Close() })
    $form.Controls.Add($btnCancel)

    $form.ShowDialog()
}

function Show-GUI {
    $config = Load-Config

    $form = New-Object Windows.Forms.Form
    $form.Text = "An Server anmelden"
    $form.Size = '300,200'
    $form.StartPosition = "CenterScreen"
    $form.TopMost = $true
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.KeyPreview = $true

    $form.add_FormClosing({
        $_.Cancel = $true
        $form.Hide()
    })

    $dll = "C:\Windows\System32\imageres.dll"
    $form.Icon = Get-FormIcon -dllPath $dll -iconIndex 170

    $form.Add_KeyDown({
        if ($_.Control -and $_.Alt -and $_.KeyCode -eq "C") {
            Show-ConfigForm
        }
    })

    $btnLogin = New-Object Windows.Forms.Button
    $btnLogin.Text = "Anmelden"
    $btnLogin.Size = '250,30'
    $btnLogin.Location = '20,20'
    $btnLogin.Image = Get-IconFromDll -dllPath $dll -iconIndex 208
    $btnLogin.ImageAlign = 'MiddleLeft'
    $btnLogin.Add_Click({
        $cfg = Load-Config
        $args = @()

        if (![string]::IsNullOrWhiteSpace($cfg.RdpFile) -and (Test-Path $cfg.RdpFile)) {
            $args += "`"$($cfg.RdpFile)`""
        }

        if ($cfg.RdpServer) { $args += "/v:$($cfg.RdpServer)" }
        if ($cfg.Gateway)   { $args += "/g:$($cfg.Gateway)" }
        if ($cfg.Fullscreen) { $args += "/f" }
        if ($cfg.Width)     { $args += "/w:$($cfg.Width)" }
        if ($cfg.Height)    { $args += "/h:$($cfg.Height)" }
        if ($cfg.Public)    { $args += "/public" }
        if ($cfg.MultiMon)  { $args += "/multimon" }
        if ($cfg.Admin)     { $args += "/admin" }
        if ($cfg.Prompt)    { $args += "/prompt" }
        if ($cfg.RestrictedAdmin) { $args += "/restrictedAdmin" }
        if ($cfg.RemoteGuard)     { $args += "/remoteGuard" }
        if ($cfg.ShadowID)  { $args += "/shadow:$($cfg.ShadowID)" }
        if ($cfg.Control)   { $args += "/control" }
        if ($cfg.NoConsentPrompt) { $args += "/noConsentPrompt" }

        Start-Process "mstsc.exe" -ArgumentList $args
        $form.Hide()
    })
    $form.Controls.Add($btnLogin)

    $btnShutdown = New-Object Windows.Forms.Button
    $btnShutdown.Text = "Herunterfahren"
    $btnShutdown.Size = '250,30'
    $btnShutdown.Location = '20,60'
    $btnShutdown.Image = Get-IconFromDll -dllPath $dll -iconIndex 227
    $btnShutdown.ImageAlign = 'MiddleLeft'
    $btnShutdown.Add_Click({ Stop-Computer -Force })
    $form.Controls.Add($btnShutdown)

    $btnReboot = New-Object Windows.Forms.Button
    $btnReboot.Text = "Neustarten"
    $btnReboot.Size = '250,30'
    $btnReboot.Location = '20,100'
    $btnReboot.Image = Get-IconFromDll -dllPath $dll -iconIndex 228
    $btnReboot.ImageAlign = 'MiddleLeft'
    $btnReboot.Add_Click({ Restart-Computer -Force })
    $form.Controls.Add($btnReboot)

    return $form
}

# Fenster verstecken (PowerShell-Fenster ausblenden)
Add-Type -Name Win -Namespace HideWindow -MemberDefinition '
  [DllImport("user32.dll")]
  public static extern int ShowWindow(int hwnd, int nCmdShow);
  [DllImport("kernel32.dll")]
  public static extern int GetConsoleWindow();
'
$consolePtr = [HideWindow.Win]::GetConsoleWindow()
[HideWindow.Win]::ShowWindow($consolePtr, 0)

# GUI erzeugen
$form = Show-GUI
$dll = "C:\Windows\System32\imageres.dll"

$trayIcon = New-Object System.Windows.Forms.NotifyIcon
$trayIcon.Icon = Get-FormIcon -dllPath $dll -iconIndex 170
$trayIcon.Visible = $true
$trayIcon.Text = "RDP-Client"

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$menuItemShow = $menu.Items.Add("Anmelden öffnen")
$menuItemShow.Add_Click({ $form.ShowDialog() | Out-Null })

$menuItemConfig = $menu.Items.Add("Konfiguration (Strg+Alt+C)")
$menuItemConfig.Add_Click({ Show-ConfigForm })

$menuItemExit = $menu.Items.Add("Beenden")
$menuItemExit.Add_Click({
    $trayIcon.Visible = $false
    $form.Close()
    [System.Windows.Forms.Application]::Exit()
    Stop-Process -Id $PID
})

$trayIcon.ContextMenuStrip = $menu

$form.Show()

# Timer zur Überwachung von mstsc.exe
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000  # alle 1 Sekunden prüfen
$timer.Add_Tick({
    $mstscRunning = Get-Process mstsc -ErrorAction SilentlyContinue
    if (-not $mstscRunning -and -not $form.Visible) {
        $form.Show()
    } elseif ($mstscRunning -and $form.Visible) {
        $form.Hide()
    }
})
$timer.Start()

# Hauptthread starten
[System.Windows.Forms.Application]::Run()
