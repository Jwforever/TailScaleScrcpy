$ErrorActionPreference = 'Continue'

$script:DbgLog = Join-Path $env:TEMP 'scrcpy-ts-debug.log'
function Dbg($m) {
    try { [System.IO.File]::AppendAllText($script:DbgLog, ((Get-Date -Format 'HH:mm:ss') + '  ' + [string]$m + "`r`n")) } catch { }
}
Dbg '=== start ==='
trap { Dbg ('EXCEPTION: ' + ($_ | Out-String)); exit 1 }

try {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class WinConHide {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
'@ -ErrorAction Stop
    $hwnd = [WinConHide]::GetConsoleWindow()
    if ($hwnd -ne [IntPtr]::Zero) { [void][WinConHide]::ShowWindow($hwnd, 0) }
} catch { }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
Dbg 'winforms loaded'

# ================= 路径 =================
$exePath = ''
try { $exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName } catch { }
$AppDir = ''
if ($exePath -and ($exePath -notmatch 'powershell')) { $AppDir = Split-Path -Parent $exePath }
elseif ($PSScriptRoot) { $AppDir = $PSScriptRoot }
else { $AppDir = (Get-Location).Path }
$CfgPath = Join-Path $AppDir 'scrcpy-ts.json'

# ---- 自解包 ----
function Expand-EmbeddedScrcpy {
    if (-not $exePath) { return }
    if ($exePath -notmatch '\.exe$') { return }
    if (-not (Test-Path $exePath)) { return }
    try {
        $len = ([System.IO.FileInfo]$exePath).Length
        if ($len -lt 65536) { return }
        $fs = [System.IO.File]::Open($exePath, 'Open', 'Read', 'ReadWrite')
        try {
            $tail = New-Object byte[] 12
            [void]$fs.Seek(-12, 'End')
            [void]$fs.Read($tail, 0, 12)
            if ([System.Text.Encoding]::ASCII.GetString($tail, 0, 4) -ne 'TSZP') { return }
            $plen = [System.BitConverter]::ToInt64($tail, 4)
            if ($plen -le 0 -or $plen -gt ($len - 65536)) { return }
            $targetDir = Join-Path $AppDir 'scrcpy'
            $marker = Join-Path $targetDir '.payload'
            if ((Test-Path (Join-Path $targetDir 'scrcpy.exe')) -and (Test-Path $marker)) {
                $old = (Get-Content $marker -Raw -ErrorAction SilentlyContinue)
                if ($old -and $old.Trim() -eq [string]$plen) { return }
            }
            Dbg ('extracting payload: ' + $plen)
            $zip = Join-Path $env:TEMP ('scrcpy_ts_' + $plen + '.zip')
            [void]$fs.Seek(($len - 12 - $plen), 'Begin')
            $ofs = [System.IO.File]::Create($zip)
            try {
                $buf = New-Object byte[] 262144
                $left = $plen
                while ($left -gt 0) {
                    $want = [int][Math]::Min(262144, $left)
                    $got = $fs.Read($buf, 0, $want)
                    if ($got -le 0) { break }
                    $ofs.Write($buf, 0, $got); $left -= $got
                }
            } finally { $ofs.Close() }
            if (-not (Test-Path $targetDir)) { [void](New-Item -ItemType Directory -Path $targetDir -Force) }
            Expand-Archive -Path $zip -DestinationPath $targetDir -Force -ErrorAction Stop
            Set-Content -Path $marker -Value ([string]$plen) -Encoding ASCII
            Remove-Item $zip -Force -ErrorAction SilentlyContinue
            Dbg 'payload extracted'
        } finally { $fs.Close() }
    } catch { Dbg ('extract FAIL: ' + $_.Exception.Message) }
}
Expand-EmbeddedScrcpy

# ================= 配置 =================
$script:cfg = @{ ScrcpyPath=''; AdbPath=''; DeviceIp=''; Port=''; MaxSize='1280'; BitRate='6M'; MaxFps=''; Preset='均衡' }
if (Test-Path $CfgPath) {
    try {
        $j = Get-Content $CfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($k in @($script:cfg.Keys)) {
            if ($j.PSObject.Properties.Name -contains $k) { $v = [string]$j.$k; if ($v) { $script:cfg[$k] = $v } }
        }
    } catch { }
}
function Save-Cfg { try { ($script:cfg | ConvertTo-Json) | Set-Content -Path $CfgPath -Encoding UTF8 } catch { } }

function Find-Scrcpy {
    if ($script:cfg.ScrcpyPath -and (Test-Path $script:cfg.ScrcpyPath)) { return $script:cfg.ScrcpyPath }
    $c = @()
    if ($PSScriptRoot) { $c += (Join-Path $PSScriptRoot 'scrcpy.exe') }
    $c += @((Join-Path $AppDir 'scrcpy\scrcpy.exe'), (Join-Path $AppDir 'scrcpy.exe'))
    foreach ($p in $c) { if ($p -and (Test-Path $p)) { return $p } }
    return ''
}
function Find-Adb($s) {
    if ($script:cfg.AdbPath -and (Test-Path $script:cfg.AdbPath)) { return $script:cfg.AdbPath }
    if ($s) { $a = Join-Path (Split-Path -Parent $s) 'adb.exe'; if (Test-Path $a) { return $a } }
    $g = Get-Command 'adb' -ErrorAction SilentlyContinue
    if ($g) { return $g.Source }
    return ''
}
function Find-Tailscale {
    $g = Get-Command 'tailscale' -ErrorAction SilentlyContinue
    if ($g) { return $g.Source }
    foreach ($p in @("$env:ProgramFiles\Tailscale\tailscale.exe", "${env:ProgramFiles(x86)}\Tailscale\tailscale.exe")) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    return ''
}
$script:scrcpyPath = Find-Scrcpy
$script:adbPath = Find-Adb $script:scrcpyPath

# ================= 视觉常量 =================
$C_BG      = [System.Drawing.Color]::FromArgb(242, 243, 245)
$C_CARD    = [System.Drawing.Color]::White
$C_LINE    = [System.Drawing.Color]::FromArgb(232, 234, 237)
$C_FIELD   = [System.Drawing.Color]::FromArgb(244, 245, 247)
$C_TEXT    = [System.Drawing.Color]::FromArgb(26, 26, 28)
$C_MUTED   = [System.Drawing.Color]::FromArgb(138, 143, 153)
$C_ACCENT  = [System.Drawing.Color]::FromArgb(52, 120, 246)
$C_ACC_D   = [System.Drawing.Color]::FromArgb(32, 96, 214)
$C_HOVER   = [System.Drawing.Color]::FromArgb(240, 241, 244)
$C_DARK    = [System.Drawing.Color]::FromArgb(14, 15, 18)

$F_TITLE  = New-Object System.Drawing.Font('Microsoft YaHei UI', 15, [System.Drawing.FontStyle]::Bold)
$F_BODY   = New-Object System.Drawing.Font('Microsoft YaHei UI', 9.5)
$F_SMALL  = New-Object System.Drawing.Font('Microsoft YaHei UI', 8.5)
$F_BTN    = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
$F_BTNB   = New-Object System.Drawing.Font('Microsoft YaHei UI', 10, [System.Drawing.FontStyle]::Bold)
$F_MONO   = New-Object System.Drawing.Font('Consolas', 9)

function RoundPath($w, $h, $r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    if ($d -gt $w) { $d = $w }
    if ($d -gt $h) { $d = $h }
    $p.AddArc(0, 0, $d, $d, 180, 90)
    $p.AddArc(($w - $d), 0, $d, $d, 270, 90)
    $p.AddArc(($w - $d), ($h - $d), $d, $d, 0, 90)
    $p.AddArc(0, ($h - $d), $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

function New-Card($x, $y, $w, $h, $r = 12, $fill = $null) {
    if (-not $fill) { $fill = $C_CARD }
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = New-Object System.Drawing.Point($x, $y)
    $p.BackColor = $fill
    $p.Tag = @{ R = $r; Fill = $fill; Line = $C_LINE }
    $p.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = 'AntiAlias'
        $t = $s.Tag
        if ($t.Fill -ne $s.BackColor) {
            $b = New-Object System.Drawing.SolidBrush($s.BackColor)
            $g.FillRectangle($b, 0, 0, $s.Width, $s.Height); $b.Dispose()
        }
        $gp = RoundPath ($s.Width - 1) ($s.Height - 1) $t.R
        if ($t.Line -ne [System.Drawing.Color]::Transparent) {
            $pen = New-Object System.Drawing.Pen($t.Line, 1)
            $g.DrawPath($pen, $gp); $pen.Dispose()
        }
        $gp.Dispose()
    })
    $p.Add_Resize({
        param($s, $e)
        $gp = RoundPath $s.Width $s.Height ([int]$s.Tag.R)
        $s.Region = New-Object System.Drawing.Region($gp)
        $gp.Dispose()
    })
    $p.Size = New-Object System.Drawing.Size($w, $h)
    return $p
}

function New-FlatButton($text, $x, $y, $w, $h, $kind = 'ghost') {
    $f = $F_BTN
    $fill = [System.Drawing.Color]::White
    $hover = $C_HOVER
    $down = [System.Drawing.Color]::FromArgb(228, 230, 234)
    $border = [System.Drawing.Color]::FromArgb(219, 222, 227)
    $fg = $C_TEXT
    if ($kind -eq 'primary') {
        $fill = $C_ACCENT; $hover = [System.Drawing.Color]::FromArgb(66, 133, 248)
        $down = $C_ACC_D; $border = $C_ACCENT; $fg = [System.Drawing.Color]::White; $f = $F_BTNB
    } elseif ($kind -eq 'segment') {
        $fill = [System.Drawing.Color]::Transparent; $hover = $C_HOVER
        $down = $C_HOVER; $border = [System.Drawing.Color]::Transparent; $fg = $C_MUTED
    }
    $b = New-Object System.Windows.Forms.Panel
    $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.BackColor = [System.Drawing.Color]::Transparent
    $b.Cursor = 'Hand'
    $b.Tag = @{ Text=$text; Font=$f; Fill=$fill; HoverFill=$hover; DownFill=$down; Border=$border; TextColor=$fg; Kind=$kind; Hover=$false; Down=$false; R=$(if ($kind -eq 'segment') { 8 } else { 10 }) }
    $b.Add_Paint({
        param($s, $e)
        try {
            $t = $s.Tag
            $g = $e.Graphics
            $g.SmoothingMode = 'AntiAlias'
            $rect = New-Object System.Drawing.Rectangle(0, 0, ($s.Width - 1), ($s.Height - 1))
            $gp = RoundPath ($s.Width - 1) ($s.Height - 1) $t.R
            $fill = $t.Fill
            if ($t.Down) { $fill = $t.DownFill } elseif ($t.Hover) { $fill = $t.HoverFill }
            if ($fill.A -gt 0) {
                $br = New-Object System.Drawing.SolidBrush($fill)
                $g.FillPath($br, $gp); $br.Dispose()
            }
            if ($t.Border -ne [System.Drawing.Color]::Transparent) {
                $pen = New-Object System.Drawing.Pen($t.Border, 1)
                $g.DrawPath($pen, $gp); $pen.Dispose()
            }
            $gp.Dispose()
            $sf = New-Object System.Drawing.StringFormat
            $sf.Alignment = 'Center'
            $sf.LineAlignment = 'Center'
            $tb = New-Object System.Drawing.SolidBrush($t.TextColor)
            $rf = New-Object System.Drawing.RectangleF(0, 0, [float]$s.Width, [float]$s.Height)
            $g.DrawString([string]$t.Text, $t.Font, $tb, $rf, $sf)
            $tb.Dispose(); $sf.Dispose()
        } catch {
            Dbg ('btn paint: ' + $_.Exception.Message)
        }
    })
    $b.Add_MouseEnter({ param($s, $e) $s.Tag.Hover = $true; $s.Invalidate() })
    $b.Add_MouseLeave({ param($s, $e) $s.Tag.Hover = $false; $s.Tag.Down = $false; $s.Invalidate() })
    $b.Add_MouseDown({ param($s, $e) $s.Tag.Down = $true; $s.Invalidate() })
    $b.Add_MouseUp({ param($s, $e) $s.Tag.Down = $false; $s.Invalidate() })
    $b.Size = New-Object System.Drawing.Size($w, $h)
    return $b
}

function New-Field($x, $y, $w, $h, $textVal = '', $readonly = $false) {
    $wrap = New-Object System.Windows.Forms.Panel
    $wrap.Location = New-Object System.Drawing.Point($x, $y)
    $wrap.BackColor = $C_FIELD
    $wrap.Tag = $h
    $wrap.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = 'AntiAlias'
        $gp = RoundPath ($s.Width) ($s.Height) 8
        $br = New-Object System.Drawing.SolidBrush($C_FIELD)
        $g.FillPath($br, $gp); $br.Dispose(); $gp.Dispose()
    })
    $wrap.Add_Resize({
        param($s, $e)
        $gp = RoundPath $s.Width $s.Height 8
        $s.Region = New-Object System.Drawing.Region($gp)
        $gp.Dispose()
    })
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.BorderStyle = 'None'
    $tb.BackColor = $C_FIELD
    $tb.ForeColor = $C_TEXT
    $tb.Font = $F_BODY
    $tb.Text = $textVal
    $tb.ReadOnly = $readonly
    $tb.Location = New-Object System.Drawing.Point(10, [int](($h - 18) / 2))
    $tb.Width = $w - 20
    $wrap.Controls.Add($tb)
    $wrap.Size = New-Object System.Drawing.Size($w, $h)
    $wrap.Tag = @{ H = $h; Box = $tb }
    return $wrap
}

# ================= 窗体 =================
$form = New-Object System.Windows.Forms.Form
$form.Text = 'scrcpy 投屏助手'
$form.ClientSize = New-Object System.Drawing.Size(640, 720)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.BackColor = $C_BG
$form.Font = $F_BODY
try {
    if ($exePath -and (Test-Path $exePath) -and ($exePath -notmatch 'powershell')) {
        $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($exePath)
        if ($ico) { $form.Icon = $ico }
    }
} catch { }

function Add-Lbl($parent, $text, $x, $y, $w, $h, $font, $color) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text
    $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.Size = New-Object System.Drawing.Size($w, $h)
    $l.Font = $font
    $l.ForeColor = $color
    $l.BackColor = [System.Drawing.Color]::Transparent
    $l.TextAlign = 'MiddleLeft'
    $parent.Controls.Add($l)
    return $l
}

$lblTitle = Add-Lbl $form '投屏助手' 24 14 300 34 $F_TITLE $C_TEXT
$lblSub = Add-Lbl $form 'scrcpy  ·  Tailscale 无线投屏' 26 50 400 20 $F_SMALL $C_MUTED

# ---- 卡片1 设备 ----
$card1 = New-Card 16 84 608 168
$form.Controls.Add($card1)
Add-Lbl $card1 '设备' 18 10 200 20 $F_SMALL $C_MUTED | Out-Null

$cmbDev = New-Object System.Windows.Forms.ComboBox
$cmbDev.Location = New-Object System.Drawing.Point(18, 34)
$cmbDev.Size = New-Object System.Drawing.Size(472, 30)
$cmbDev.DropDownStyle = 'DropDownList'
$cmbDev.FlatStyle = 'Flat'
$cmbDev.BackColor = $C_FIELD
$cmbDev.ForeColor = $C_TEXT
$cmbDev.Font = $F_BODY
$cmbDev.DrawMode = 'OwnerDrawFixed'
$cmbDev.ItemHeight = 20
$cmbDev.Add_DrawItem({
    param($s, $e)
    try {
        $g = $e.Graphics
        $g.SmoothingMode = 'AntiAlias'
        $isEdit = (($e.State -band [System.Windows.Forms.DrawItemState]::ComboBoxEdit) -ne 0)
        $isSel = (($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0)
        if ($isEdit) { $bg = $C_FIELD; $fg = $C_TEXT }
        elseif ($isSel) { $bg = $C_ACCENT; $fg = [System.Drawing.Color]::White }
        else { $bg = [System.Drawing.Color]::White; $fg = $C_TEXT }
        $br = New-Object System.Drawing.SolidBrush($bg)
        $g.FillRectangle($br, $e.Bounds); $br.Dispose()
        if ($e.Index -ge 0) {
            $txt = [string]$s.Items[$e.Index]
            $rf = New-Object System.Drawing.RectangleF([float]($e.Bounds.X + 6), [float]$e.Bounds.Y, [float]($e.Bounds.Width - 12), [float]$e.Bounds.Height)
            $sf = New-Object System.Drawing.StringFormat
            $sf.LineAlignment = 'Center'
            $tb = New-Object System.Drawing.SolidBrush($fg)
            $g.DrawString($txt, $F_BODY, $tb, $rf, $sf)
            $tb.Dispose(); $sf.Dispose()
        }
    } catch { }
})
$card1.Controls.Add($cmbDev)

$btnRefresh = New-FlatButton '刷新' 500 34 90 30 'ghost'
$card1.Controls.Add($btnRefresh)

Add-Lbl $card1 'IP' 18 78 24 24 $F_SMALL $C_MUTED | Out-Null
$fieldIp = New-Field 46 74 174 30 $script:cfg.DeviceIp
$card1.Controls.Add($fieldIp)
$txtIp = $fieldIp.Tag.Box

Add-Lbl $card1 '端口' 236 78 34 24 $F_SMALL $C_MUTED | Out-Null
$fieldPort = New-Field 274 74 84 30 $script:cfg.Port
$card1.Controls.Add($fieldPort)
$txtPort = $fieldPort.Tag.Box

Add-Lbl $card1 '无线调试页顶部' 370 78 130 24 $F_SMALL $C_MUTED | Out-Null

Add-Lbl $card1 '引擎' 18 120 34 24 $F_SMALL $C_MUTED | Out-Null
$fieldEng = New-Field 56 116 436 30 $script:scrcpyPath $true
$card1.Controls.Add($fieldEng)
$txtScrcpy = $fieldEng.Tag.Box

$btnBrowse = New-FlatButton '浏览' 500 116 90 30 'ghost'
$card1.Controls.Add($btnBrowse)

# ---- 卡片2 画质 ----
$card2 = New-Card 16 264 608 128
$form.Controls.Add($card2)
Add-Lbl $card2 '画质' 18 10 200 20 $F_SMALL $C_MUTED | Out-Null

$segWrap = New-Card 16 34 384 34 9 $C_FIELD
$segWrap.Tag.Line = [System.Drawing.Color]::Transparent
$card2.Controls.Add($segWrap)

$script:segNames = @('省流', '均衡', '清晰', '原画')
$script:segIdx = 1
$script:segBtns = @()
for ($i = 0; $i -lt 4; $i++) {
    $sb = New-FlatButton $script:segNames[$i] (4 + $i * 94) 3 90 28 'segment'
    $sb.Name = "seg$i"
    $segWrap.Controls.Add($sb)
    $script:segBtns += $sb
}

Add-Lbl $card2 '尺寸' 18 82 34 24 $F_SMALL $C_MUTED | Out-Null
$fieldSize = New-Field 54 78 82 30 $script:cfg.MaxSize
$card2.Controls.Add($fieldSize)
$txtSize = $fieldSize.Tag.Box

Add-Lbl $card2 '码率' 150 82 34 24 $F_SMALL $C_MUTED | Out-Null
$fieldBit = New-Field 186 78 82 30 $script:cfg.BitRate
$card2.Controls.Add($fieldBit)
$txtBit = $fieldBit.Tag.Box

Add-Lbl $card2 '帧率' 282 82 34 24 $F_SMALL $C_MUTED | Out-Null
$fieldFps = New-Field 318 78 82 30 $script:cfg.MaxFps
$card2.Controls.Add($fieldFps)
$txtFps = $fieldFps.Tag.Box

Add-Lbl $card2 '留空 = 自动　尺寸 0 = 原画' 414 82 180 24 $F_SMALL $C_MUTED | Out-Null

# ---- 操作区 ----
$btnPair = New-FlatButton '配对' 16 404 100 44 'ghost'
$form.Controls.Add($btnPair)
$btnConnect = New-FlatButton '连接' 128 404 100 44 'ghost'
$form.Controls.Add($btnConnect)
$btnDisconnect = New-FlatButton '断开' 240 404 100 44 'ghost'
$form.Controls.Add($btnDisconnect)
$btnMirror = New-FlatButton '开始投屏' 352 404 272 44 'primary'
$form.Controls.Add($btnMirror)

# ---- 控制台 ----
$conWrap = New-Card 16 462 608 212 12 $C_DARK
$conWrap.Tag.Line = [System.Drawing.Color]::Transparent
$form.Controls.Add($conWrap)

$rtb = New-Object System.Windows.Forms.RichTextBox
$rtb.Location = New-Object System.Drawing.Point(14, 14)
$rtb.Size = New-Object System.Drawing.Size(580, 184)
$rtb.ReadOnly = $true
$rtb.BackColor = $C_DARK
$rtb.ForeColor = [System.Drawing.Color]::FromArgb(226, 228, 232)
$rtb.Font = $F_MONO
$rtb.BorderStyle = 'None'
$rtb.WordWrap = $true
$rtb.ScrollBars = 'Vertical'
$conWrap.Controls.Add($rtb)

$lblStatus = Add-Lbl $form '就绪' 24 682 600 22 $F_SMALL $C_MUTED

function F-Log($msg) {
    try {
        $rtb.SelectionStart = $rtb.TextLength
        $rtb.SelectionLength = 0
        $rtb.SelectionColor = [System.Drawing.Color]::FromArgb(226, 228, 232)
        $rtb.AppendText(('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $msg) + "`r`n")
        $rtb.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    } catch { }
}
function F-Warn($msg) {
    try {
        $rtb.SelectionStart = $rtb.TextLength
        $rtb.SelectionLength = 0
        $rtb.SelectionColor = [System.Drawing.Color]::FromArgb(255, 176, 120)
        $rtb.AppendText(('[{0}] [!] {1}' -f (Get-Date -Format 'HH:mm:ss'), $msg) + "`r`n")
        $rtb.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    } catch { }
}
function F-Status($t) { $lblStatus.Text = $t; [System.Windows.Forms.Application]::DoEvents() }

# ================= 逻辑 =================
function Get-Serial { return ('{0}:{1}' -f $txtIp.Text.Trim(), $txtPort.Text.Trim()) }

function Get-AdbState($serial) {
    if (-not $script:adbPath) { return 'noadb' }
    $out = & $script:adbPath devices 2>$null
    foreach ($l in $out) {
        if ($l -match '^\s*(\S+)\s+(device|offline|unauthorized)\s*$') {
            if ($matches[1] -eq $serial) { return $matches[2] }
        }
    }
    return 'missing'
}

function Get-TsDevices {
    $ts = Find-Tailscale
    if (-not $ts) { return @() }
    $out = @()
    foreach ($l in (& $ts status 2>$null)) {
        $t = @($l -split '\s+' | Where-Object { $_ -ne '' })
        if ($t.Count -ge 4 -and $t[0] -match '^\d+\.\d+\.\d+\.\d+$' -and $t[3] -eq 'android') {
            $out += [pscustomobject]@{ Ip = $t[0]; Name = $t[1] }
        }
    }
    return $out
}

function Set-Seg($idx) {
    $script:segIdx = $idx
    for ($i = 0; $i -lt $script:segBtns.Count; $i++) {
        $b = $script:segBtns[$i]
        if ($i -eq $idx) {
            $b.Tag.Fill = [System.Drawing.Color]::White
            $b.Tag.TextColor = $C_ACCENT
            $b.Tag.Font = $F_BTNB
        } else {
            $b.Tag.Fill = [System.Drawing.Color]::Transparent
            $b.Tag.TextColor = $C_MUTED
            $b.Tag.Font = $F_BTN
        }
        $b.Invalidate()
    }
    switch ($idx) {
        0 { $txtSize.Text = '720';  $txtBit.Text = '3M';  $txtFps.Text = '30' }
        1 { $txtSize.Text = '1280'; $txtBit.Text = '6M';  $txtFps.Text = '' }
        2 { $txtSize.Text = '1600'; $txtBit.Text = '12M'; $txtFps.Text = '' }
        3 { $txtSize.Text = '0';    $txtBit.Text = '20M'; $txtFps.Text = '' }
    }
    Save-FormCfg
}

function Save-FormCfg {
    $script:cfg.DeviceIp = $txtIp.Text.Trim()
    $script:cfg.Port     = $txtPort.Text.Trim()
    $script:cfg.MaxSize  = $txtSize.Text.Trim()
    $script:cfg.BitRate  = $txtBit.Text.Trim()
    $script:cfg.MaxFps   = $txtFps.Text.Trim()
    $script:cfg.Preset   = $script:segNames[$script:segIdx]
    Save-Cfg
}

function Set-Port5555 {
    $ip = $txtIp.Text.Trim()
    if (-not $ip) { return $false }
    $serial = ('{0}:{1}' -f $ip, $txtPort.Text.Trim())
    F-Log '正在把 adb 端口固定为 5555 ...'
    foreach ($l in (& $script:adbPath -s $serial tcpip 5555 2>&1)) { F-Log ([string]$l) }
    Start-Sleep -Seconds 2
    $null = & $script:adbPath connect ('{0}:5555' -f $ip) 2>&1
    Start-Sleep -Milliseconds 900
    $st = Get-AdbState ('{0}:5555' -f $ip)
    if ($st -eq 'device') {
        $txtPort.Text = '5555'
        Save-FormCfg
        F-Log '端口已固定为 5555，以后打开直接点「开始投屏」'
        F-Status 'adb 已连接  (5555)'
        return $true
    }
    F-Warn ('固定 5555 失败（' + $st + '），已回退到原端口')
    $null = & $script:adbPath connect $serial 2>&1
    return $false
}

# ================= 事件 =================
for ($i = 0; $i -lt 4; $i++) {
    $script:segBtns[$i].Add_MouseUp({
        param($s, $e)
        $n = [int]([string]$s.Name).Substring(3)
        Set-Seg $n
    })
}

function Update-Devices {
    F-Status '正在扫描 tailnet ...'
    $cmbDev.Items.Clear()
    $devs = @(Get-TsDevices)
    if ($devs.Count -eq 0) {
        F-Warn '没扫到安卓设备，检查 Tailscale 是否安装并登录'
    } else {
        foreach ($d in $devs) { [void]$cmbDev.Items.Add(('{0}   ({1})' -f $d.Name, $d.Ip)) }
        $cmbDev.SelectedIndex = 0
        F-Log ('扫到 {0} 台安卓设备：' -f $devs.Count)
        foreach ($d in $devs) { F-Log ('    {0}   {1}' -f $d.Ip, $d.Name) }
    }
    F-Status '就绪'
}
$btnRefresh.Add_MouseUp({ Update-Devices })

$cmbDev.Add_SelectedIndexChanged({
    if ($cmbDev.SelectedIndex -lt 0) { return }
    $txt = [string]$cmbDev.SelectedItem
    if ($txt -match '\(([\d\.]+)\)') { $txtIp.Text = $matches[1] }
})

$btnBrowse.Add_MouseUp({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = '选择 scrcpy.exe'
    $dlg.Filter = 'scrcpy.exe|scrcpy.exe|可执行文件|*.exe'
    if ($dlg.ShowDialog() -eq 'OK') {
        $script:scrcpyPath = $dlg.FileName
        $script:cfg.ScrcpyPath = $dlg.FileName
        $a = Join-Path (Split-Path -Parent $dlg.FileName) 'adb.exe'
        if (Test-Path $a) { $script:adbPath = $a; $script:cfg.AdbPath = $a }
        $txtScrcpy.Text = $dlg.FileName
        Save-Cfg
        F-Log ('已切换 scrcpy: ' + $dlg.FileName)
    }
})

$btnPair.Add_MouseUp({
    $ip = $txtIp.Text.Trim()
    if (-not $ip) { F-Warn '请先填 IP'; return }
    F-Log '平板 → 开发者选项 → 无线调试 → 使用配对码配对设备'
    $d1 = New-Object System.Windows.Forms.Form
    $d1.Text = '配对'
    $d1.ClientSize = New-Object System.Drawing.Size(360, 214)
    $d1.StartPosition = 'CenterParent'
    $d1.FormBorderStyle = 'FixedDialog'
    $d1.MaximizeBox = $false
    $d1.MinimizeBox = $false
    $d1.BackColor = [System.Drawing.Color]::White
    $d1.Font = $F_BODY

    $l1 = New-Object System.Windows.Forms.Label
    $l1.Text = '配对端口'; $l1.Location = New-Object System.Drawing.Point(22, 26); $l1.Size = New-Object System.Drawing.Size(80, 22)
    $l1.ForeColor = $C_MUTED; $l1.Font = $F_SMALL
    $d1.Controls.Add($l1)
    $f1 = New-Field 108 22 200 30 ''
    $d1.Controls.Add($f1)

    $l2 = New-Object System.Windows.Forms.Label
    $l2.Text = '配对码'; $l2.Location = New-Object System.Drawing.Point(22, 68); $l2.Size = New-Object System.Drawing.Size(80, 22)
    $l2.ForeColor = $C_MUTED; $l2.Font = $F_SMALL
    $d1.Controls.Add($l2)
    $f2 = New-Field 108 64 200 30 ''
    $d1.Controls.Add($f2)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = '配对成功后填连接端口 → 点连接 → 自动固定 5555'
    $hint.Location = New-Object System.Drawing.Point(22, 104)
    $hint.Size = New-Object System.Drawing.Size(320, 22)
    $hint.ForeColor = $C_MUTED; $hint.Font = $F_SMALL
    $d1.Controls.Add($hint)

    $bok = New-FlatButton '开始配对' 108 140 108 36 'primary'
    $bok.Tag.Text = '开始配对'
    $d1.Controls.Add($bok)
    $bcancel = New-FlatButton '取消' 228 140 88 36 'ghost'
    $d1.Controls.Add($bcancel)

    $script:dlgOk = $false
    $bok.Add_MouseUp({ $script:dlgOk = $true; $d1.Close() })
    $bcancel.Add_MouseUp({ $d1.Close() })
    [void]$d1.ShowDialog($form)

    $pp = $f1.Tag.Box.Text.Trim()
    $code = $f2.Tag.Box.Text.Trim()
    if (-not $script:dlgOk) { return }
    if (-not $pp -or -not $code) { F-Warn '端口或配对码为空'; return }

    F-Status '正在配对 ...'
    $out = & $script:adbPath pair ('{0}:{1}' -f $ip, $pp) $code 2>&1
    foreach ($l in $out) { F-Log ([string]$l) }
    if (($out | Out-String) -match 'Successfully paired') {
        F-Log '配对成功，密钥已保存'
        F-Log '下一步：把「连接端口」填到主窗口，点「连接」，会自动固定为 5555'
    } else {
        F-Warn '配对失败（配对窗口关掉就失效，重开再试）'
    }
    F-Status '就绪'
})

$btnConnect.Add_MouseUp({
    $sock = Get-Serial
    if ($sock -eq ':') { F-Warn '请先填 IP 和端口'; return }
    Save-FormCfg
    F-Status '正在连接 ...'
    foreach ($l in (& $script:adbPath connect $sock 2>&1)) { F-Log ([string]$l) }
    Start-Sleep -Milliseconds 700
    $st = Get-AdbState $sock
    if ($st -eq 'device') {
        F-Log ('已连接 ' + $sock)
        if ($txtPort.Text.Trim() -ne '5555') { [void](Set-Port5555) }
        else { F-Status 'adb 已连接  (5555)' }
    } elseif ($st -eq 'unauthorized') {
        F-Warn '未授权，请在平板上点「允许」'; F-Status 'adb: unauthorized'
    } else {
        F-Warn ('连接失败：' + $st)
        F-Log '平板重启后端口会变，去无线调试页看新的'
        F-Status ('adb: ' + $st)
    }
})

$btnDisconnect.Add_MouseUp({
    foreach ($l in (& $script:adbPath disconnect (Get-Serial) 2>&1)) { F-Log ([string]$l) }
    F-Status '已断开'
})

$btnMirror.Add_MouseUp({
    Save-FormCfg
    if (-not $script:scrcpyPath) { F-Warn '找不到 scrcpy.exe，点「浏览」指定'; return }
    $sock = Get-Serial
    if ($sock -eq ':') { F-Warn '请先填 IP 和端口'; return }
    F-Status '正在连接 ...'
    $null = & $script:adbPath connect $sock 2>&1
    Start-Sleep -Milliseconds 800
    if ((Get-AdbState $sock) -ne 'device') {
        F-Warn '连接失败，先点「连接」排查'
        F-Status '连接失败'
        return
    }
    $a = @('-s', $sock)
    if ($txtSize.Text.Trim() -and $txtSize.Text.Trim() -ne '0') { $a += ('--max-size=' + $txtSize.Text.Trim()) }
    if ($txtBit.Text.Trim()) { $a += ('--video-bit-rate=' + $txtBit.Text.Trim()) }
    if ($txtFps.Text.Trim()) { $a += ('--max-fps=' + $txtFps.Text.Trim()) }
    F-Log ('scrcpy ' + ($a -join ' '))
    $cmdPath = Join-Path $AppDir '_run_scrcpy.cmd'
    $lines = @(
        '@echo off',
        ('"' + $script:scrcpyPath + '" ' + ($a -join ' ')),
        'set RC=%ERRORLEVEL%',
        'if not "%RC%"=="0" (',
        '  echo.',
        '  echo ==================================================',
        '  echo  scrcpy 异常退出，退出码 %RC%',
        '  echo  上面就是错误信息，按任意键关闭窗口',
        '  echo ==================================================',
        '  pause >nul',
        ')',
        'exit /b %RC%'
    )
    try {
        Set-Content -Path $cmdPath -Value $lines -Encoding Default -ErrorAction Stop
        Start-Process -FilePath $cmdPath -WorkingDirectory (Split-Path -Parent $script:scrcpyPath)
        F-Log '已启动 scrcpy（异常退出时窗口会停住显示原因）'
        F-Status '投屏中'
    } catch {
        F-Warn ('启动失败：' + $_.Exception.Message)
        F-Status '启动失败'
    }
})

$form.Add_Shown({
    Dbg 'form shown'
    F-Log '投屏助手已启动'
    if ($script:scrcpyPath) { F-Log ('scrcpy: ' + $script:scrcpyPath) } else { F-Warn '未找到 scrcpy.exe，请点「浏览」' }
    if ($script:adbPath) { F-Log ('adb: ' + $script:adbPath) } else { F-Warn '未找到 adb.exe' }
    if (Find-Tailscale) { F-Log 'Tailscale 已就绪' } else { F-Warn '未检测到 Tailscale' }

    $idx = 1
    for ($i = 0; $i -lt 4; $i++) { if ($script:segNames[$i] -eq $script:cfg.Preset) { $idx = $i } }
    Set-Seg $idx
    $txtSize.Text = $script:cfg.MaxSize
    $txtBit.Text = $script:cfg.BitRate
    $txtFps.Text = $script:cfg.MaxFps

    if ($txtIp.Text -and $txtPort.Text) { F-Status ('adb: ' + (Get-AdbState (Get-Serial))) }
    Update-Devices
})

$form.Add_FormClosing({ Save-FormCfg })

Dbg 'ui built, calling ShowDialog'
[void]$form.ShowDialog()
Dbg 'ShowDialog returned'
