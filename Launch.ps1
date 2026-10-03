# Launch.ps1 - Haupteinstiegspunkt fuer den Boost Roleplay PC Checker
# Prueft Administrator-Rechte, laedt alle Module und startet die Benutzeroberflaeche.
# Versteckt das Konsolenfenster automatisch fuer ein professionelles App-Feeling.

[CmdletBinding()]
param(
    [switch]$NoElevation
)

$ErrorActionPreference = "Continue"

# --- 1. Arbeitsverzeichnis und absoluten Skriptpfad robust bestimmen ---
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $ScriptDir -or -not (Test-Path -LiteralPath (Join-Path $ScriptDir "Modules"))) {
    $ScriptDir = (Get-Location).Path
}

Set-Location -LiteralPath $ScriptDir
$scriptPath = Join-Path $ScriptDir "Launch.ps1"
$ModulesDir = Join-Path $ScriptDir "Modules"

# --- 2. Administrator-Rechte pruefen & anfordern ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin -and -not $NoElevation) {
    try {
        Start-Process powershell.exe -Verb RunAs -WorkingDirectory $ScriptDir -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-STA",
            "-File", "`"$scriptPath`""
        )
        exit
    } catch {
        # Falls UAC abgelehnt wurde
    }
}

# --- 3. Konsolenfenster sofort ausblenden (Reiner GUI-Modus) ---
try {
    if (-not ([System.Management.Automation.PSTypeName]'BoostCheckerLauncher.Win32ConsoleHelper').Type) {
        $typeDef = @"
        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
        [DllImport("kernel32.dll")]
        public static extern IntPtr GetConsoleWindow();
"@
        Add-Type -MemberDefinition $typeDef -Name "Win32ConsoleHelper" -Namespace "BoostCheckerLauncher" -ErrorAction SilentlyContinue
    }
    $consoleHWnd = [BoostCheckerLauncher.Win32ConsoleHelper]::GetConsoleWindow()
    if ($consoleHWnd -and $consoleHWnd -ne [IntPtr]::Zero) {
        [BoostCheckerLauncher.Win32ConsoleHelper]::ShowWindow($consoleHWnd, 0)
    }
} catch { }

# --- 4. STA-Modus sicherstellen (fuer WPF benoetigt) ---
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
    Start-Process powershell.exe -WorkingDirectory $ScriptDir -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-STA",
        "-File", "`"$scriptPath`"",
        "-NoElevation"
    )
    exit
}

# --- 5. Geschuetztes Core-Paket (AES-256) in RAM laden & ausfuehren ---
$pkgPath = Join-Path $ScriptDir "Core\BoostCore.pkg"
$loaded = $false
$loadError = ""
$global:BoostCheckerRoot = $ScriptDir

if (Test-Path -LiteralPath $pkgPath) {
    try {
        $encryptedBytes = [System.IO.File]::ReadAllBytes($pkgPath)
        $__kc = [int[]]@(66,48,111,115,116,45,82,48,108,101,112,108,97,121,58,58,75,51,114,110,101,108,67,111,114,101,58,58,50,48,50,54,58,58,118,50,58,58,57,102,51,97,49,99,50,101); $aesKey = [System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes((-join ($__kc | ForEach-Object { [char]$_ }))))
        $aesIv  = [byte[]]@(0x2A, 0x5F, 0x11, 0x9B, 0x44, 0xEE, 0x33, 0x12, 0x77, 0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE)

        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.Key = $aesKey
        $aes.IV = $aesIv
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7

        $decryptor = $aes.CreateDecryptor()
        $compressedBytes = $decryptor.TransformFinalBlock($encryptedBytes, 0, $encryptedBytes.Length)
        $aes.Dispose()

        $msIn = [System.IO.MemoryStream]::new($compressedBytes)
        $gz = [System.IO.Compression.GZipStream]::new($msIn, [System.IO.Compression.CompressionMode]::Decompress)
        $msOut = [System.IO.MemoryStream]::new()
        $gz.CopyTo($msOut)
        $gz.Dispose()
        $msIn.Dispose()

        $codeBytes = $msOut.ToArray()
        $msOut.Dispose()
        $coreCode = [System.Text.Encoding]::UTF8.GetString($codeBytes)
        $coreCode = $coreCode.Replace([string][char]0xFEFF, "")

        $initHeader = "`$global:BoostCheckerRoot = `"$($ScriptDir -replace '"', '`"')`"; `$PSScriptRoot = `"$($ScriptDir -replace '"', '`"')\Modules`";`n"
        . ([scriptblock]::Create($initHeader + $coreCode))
        $loaded = $true
    } catch {
        $loaded = $false
        $loadError = $_.Exception.ToString()
    }
}

if (-not $loaded) {
    # Fallback fuer lokale Entwicklung
    $moduleFiles = @(
        "Signatures.ps1", "ScreenshareSignatures.ps1", "FileScanner.ps1", "ProcessScanner.ps1",
        "DriverScanner.ps1", "RegistryScanner.ps1", "EventLogScanner.ps1", "DnsScanner.ps1",
        "UsnJournalScanner.ps1", "MemoryScanner.ps1", "PrefetchScanner.ps1", "BrowserScanner.ps1",
        "USBScanner.ps1", "FiveMScanner.ps1", "AntiBypassScanner.ps1", "ShellBagScanner.ps1",
        "CrashDumpScanner.ps1", "SystemMemoryScanner.ps1", "AmcacheShimScanner.ps1",
        "IdentifierScanner.ps1", "DeepForensicsScanner.ps1", "ReportExporter.ps1",
        "DiscordWebhook.ps1", "ScanEngine.ps1", "GUI.ps1"
    )
    foreach ($mod in $moduleFiles) {
        $fullModPath = Join-Path $ModulesDir $mod
        if (Test-Path -LiteralPath $fullModPath) {
            try { . $fullModPath } catch { }
        }
    }
}

# --- 6. Verifizierungsfenster oeffnen ---
try {
    if (-not (Get-Command Show-ScanWindow -ErrorAction SilentlyContinue)) {
        throw "Show-ScanWindow wurde nicht geladen.`n$loadError"
    }
    Show-ScanWindow
} catch {
    Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
    [System.Windows.MessageBox]::Show(
        "Fehler beim Starten der Benutzeroberflaeche:`n$($_.Exception.Message)",
        "Boost Roleplay - Fehler",
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error
    )
}

# --- 7. Selbstzerstoerung: heruntergeladene Kopie nach dem Check vom PC entfernen ---
try {
    $root = $global:BoostCheckerRoot
    $tempBase = [System.IO.Path]::GetTempPath()
    if ($root -and $root.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $root)) {
        $parent = Split-Path $root -Parent
        $delCmd = "Start-Sleep -Seconds 2; Remove-Item -LiteralPath '$root' -Recurse -Force -ErrorAction SilentlyContinue; if ((Split-Path '$parent' -Leaf) -eq 'BoostChecker_Client') { Remove-Item -LiteralPath '$parent' -Recurse -Force -ErrorAction SilentlyContinue }"
        Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-Command', $delCmd) -ErrorAction SilentlyContinue
    }
} catch { }
