param(
    [Parameter(Mandatory = $true)]
    [string]$ScrcpyDir,
    [string]$Version = '3.1.0.0'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Definition)
$SrcDir = Join-Path $Root 'src'
$DistDir = Join-Path $Root 'dist'
$Ps1 = Join-Path $SrcDir 'ScrcpyTS.ps1'
$Ico = Join-Path $SrcDir 'icon.ico'
$TmpExe = Join-Path $Root '_build_tmp.exe'
$OutExe = Join-Path $DistDir '投屏助手.exe'

function Step($m) { Write-Host "[*] $m" -ForegroundColor Cyan }
function Done($m) { Write-Host "[+] $m" -ForegroundColor Green }

if (-not (Test-Path $Ps1)) { throw "找不到源码: $Ps1" }
if (-not (Test-Path $ScrcpyDir)) { throw "找不到 scrcpy 目录: $ScrcpyDir" }
if (-not (Get-Command Invoke-PS2EXE -ErrorAction SilentlyContinue)) {
    throw '缺少 ps2exe 模块，请先执行: Install-Module ps2exe -Scope CurrentUser'
}
if (-not (Test-Path $DistDir)) { [void](New-Item -ItemType Directory -Path $DistDir -Force) }

Step '语法检查'
$tokens = $null; $errs = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($Ps1, [ref]$tokens, [ref]$errs)
if ($errs -and $errs.Count -gt 0) {
    $errs | Select-Object -First 10 | ForEach-Object { Write-Host ("    line {0}: {1}" -f $_.Extent.StartLineNumber, $_.Message) -ForegroundColor Red }
    throw '语法检查未通过'
}
Done '语法检查通过'

if (-not (Test-Path $Ico)) {
    Step '生成图标'
    if (-not (Get-Command python -ErrorAction SilentlyContinue)) { throw '缺少 icon.ico，且未找到 python 无法生成' }
    Push-Location $SrcDir
    try { & python (Join-Path $SrcDir 'make_icon.py') } finally { Pop-Location }
    Done '图标已生成'
}

Step '打包为 exe'
Invoke-PS2EXE -InputFile $Ps1 -OutputFile $TmpExe -STA -IconFile $Ico `
    -Title 'scrcpy 投屏助手' -Description 'scrcpy over Tailscale' -Product 'scrcpy-ts' -Version $Version | Out-Null
Done ('生成主程序 ' + [math]::Round((Get-Item $TmpExe).Length / 1KB, 1) + ' KB')

Step '压缩 scrcpy 运行时'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$Zip = Join-Path $env:TEMP ('scrcpy_payload_' + [guid]::NewGuid().ToString('N') + '.zip')
$files = Get-ChildItem $ScrcpyDir -File
[System.IO.Compression.ZipFile]::CreateFromDirectory(
    $ScrcpyDir, $Zip,
    [System.IO.Compression.CompressionLevel]::Optimal, $false)
Done ("压缩 {0} 个文件 -> {1} MB" -f $files.Count, [math]::Round((Get-Item $Zip).Length / 1MB, 2))

Step '追加 payload 并写入页脚'
$base = [System.IO.File]::ReadAllBytes($TmpExe)
$payload = [System.IO.File]::ReadAllBytes($Zip)
$footer = [System.Text.Encoding]::ASCII.GetBytes('TSZP') + [System.BitConverter]::GetBytes([int64]$payload.Length)
$out = New-Object byte[] ($base.Length + $payload.Length + $footer.Length)
[Array]::Copy($base, 0, $out, 0, $base.Length)
[Array]::Copy($payload, 0, $out, $base.Length, $payload.Length)
[Array]::Copy($footer, 0, $out, $base.Length + $payload.Length, $footer.Length)
[System.IO.File]::WriteAllBytes($OutExe, $out)
Remove-Item $TmpExe, $Zip -Force -ErrorAction SilentlyContinue

Done ('输出 ' + $OutExe)
Write-Host ''
Write-Host ('    最终大小: {0} MB' -f [math]::Round((Get-Item $OutExe).Length / 1MB, 2)) -ForegroundColor White
