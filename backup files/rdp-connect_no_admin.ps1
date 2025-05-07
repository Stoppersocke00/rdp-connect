Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Web.Extensions

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

$ConfigPath = "$env:AppData\RDP-Connect\config.json"
New-Item -ItemType Directory -Force -Path (Split-Path $ConfigPath) | Out-Null

function Load-Config {
    if (Test-Path $ConfigPath) {
        return Get-Content $ConfigPath | ConvertFrom-Json
    } else {
        return [PSCustomObject]@{
            RdpServer = "localhost"
            RdpFile   = ""
            Fullscreen = $true
            MultiMon = $true
            KioskMode = $false
        }
    }
}

function Save-Config($config) {
    $config | ConvertTo-Json | Set-Content -Path $ConfigPath
}

function Show-ConfigForm {
    $config = Load-Config

    $form = New-Object Windows.Forms.Form
    $form.Text = "RDP Konfiguration"
    $form.Size = New-Object Drawing.Size(440, 370)
    $form.StartPosition = "CenterScreen"
    $form.TopMost = $true

    $dll = "C:\Windows\System32\imageres.dll"
    $form.Icon = Get-FormIcon -dllPath $dll -iconIndex 64

    $lbl1 = New-Object Windows.Forms.Label
    $lbl1.Text = "RDP-Server:"
    $lbl1.Location = '10,20'
    $lbl1.AutoSize = $true
    $form.Controls.Add($lbl1)

    $txtServer = New-Object Windows.Forms.TextBox
    $txtServer.Size = '250,20'
    $txtServer.Location = '150,18'
    $txtServer.Text = $config.RdpServer
    $form.Controls.Add($txtServer)

    $lbl2 = New-Object Windows.Forms.Label
    $lbl2.Text = "RDP-Datei:"
    $lbl2.Location = '10,55'
    $lbl2.AutoSize = $true
    $form.Controls.Add($lbl2)

    $txtFile = New-Object Windows.Forms.TextBox
    $txtFile.Size = '220,20'
    $txtFile.Location = '150,53'
    $txtFile.Text = $config.RdpFile
    $form.Controls.Add($txtFile)

    $picBrowse = New-Object Windows.Forms.PictureBox
    $picBrowse.Size = '20,20'
    $picBrowse.Location = '380,53'
    $picBrowse.Image = Get-IconFromDll -dllPath $dll -iconIndex 203
    $picBrowse.SizeMode = 'StretchImage'
    $picBrowse.Cursor = [System.Windows.Forms.Cursors]::Hand
    $picBrowse.Add_Click({
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Filter = "RDP-Dateien (*.rdp)|*.rdp"
        if ($dialog.ShowDialog() -eq "OK") {
            $txtFile.Text = $dialog.FileName
        }
    })
    $form.Controls.Add($picBrowse)

    $chkFullscreen = New-Object Windows.Forms.CheckBox
    $chkFullscreen.Text = "Vollbildmodus"
    $chkFullscreen.Location = '150,90'
    $chkFullscreen.AutoSize = $true
    $chkFullscreen.Checked = $config.Fullscreen
    $form.Controls.Add($chkFullscreen)

    $chkMultiMon = New-Object Windows.Forms.CheckBox
    $chkMultiMon.Text = "Mehrere Anzeigen"
    $chkMultiMon.Location = '150,120'
    $chkMultiMon.AutoSize = $true
    $chkMultiMon.Checked = $config.MultiMon
    $form.Controls.Add($chkMultiMon)

    $chkKiosk = New-Object Windows.Forms.CheckBox
    $chkKiosk.Text = "Kiosk-Modus"
    $chkKiosk.Location = '150,150'
    $chkKiosk.AutoSize = $true
    $chkKiosk.Checked = $config.KioskMode
    $chkKiosk.Add_CheckedChanged({
        if ($chkKiosk.Checked -ne $config.KioskMode) {
            [System.Windows.Forms.MessageBox]::Show("Die Änderung wird nach einem Neustart aktiv und erfordert Administratorrechte beim Speichern.", "Hinweis", "OK", "Information")
        }
    })
    $form.Controls.Add($chkKiosk)

    $btnSave = New-Object Windows.Forms.Button
    $btnSave.Text = "Speichern"
    $btnSave.Location = '150,200'
    $btnSave.Size = '100,30'
    $btnSave.Add_Click({
        $originalConfig = Load-Config

        $config.RdpServer = $txtServer.Text
        $config.RdpFile = $txtFile.Text
        $config.Fullscreen = $chkFullscreen.Checked
        $config.MultiMon = $chkMultiMon.Checked
        $config.KioskMode = $chkKiosk.Checked

        $kioskChanged = $originalConfig.KioskMode -ne $chkKiosk.Checked

        if ($kioskChanged) {
            $desiredShell = if ($chkKiosk.Checked) { "rdp-connect.exe" } else { "explorer.exe" }
            try {
                Start-Process -FilePath "powershell" -ArgumentList "-ExecutionPolicy Bypass -NoProfile -Command `"Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'Shell' -Value '$desiredShell'`"" -Verb RunAs -WindowStyle Hidden
                [System.Windows.Forms.MessageBox]::Show("Kiosk-Modus wurde angepasst. Die Änderung wird nach dem nächsten Neustart wirksam. Der Kiosk-Modus kann über Strg + Alt + C deaktiviert werden.", "Kiosk-Modus", "OK", "Information")
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Fehler beim Setzen des Kiosk-Modus. Bitte als Administrator starten.", "Fehler", "OK", "Error")
            }
        }

        Save-Config -config $config
        $form.Close()
    })
    $form.Controls.Add($btnSave)

    $btnCancel = New-Object Windows.Forms.Button
    $btnCancel.Text = "Abbrechen"
    $btnCancel.Location = '260,200'
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
    $_.Cancel = $true  # verhindert das Schließen
    $form.Hide()       # optional: stattdessen einfach verstecken
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
        if ($cfg.RdpServer) {
            $args += "/v:$($cfg.RdpServer)"
        }
        if ($cfg.Fullscreen) { $args += "/f" }
        if ($cfg.MultiMon) { $args += "/multimon" }
        $args += "/public"
        $args += "/prompt"
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