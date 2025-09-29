<#
.SYNOPSIS
    A comprehensive PowerShell-based utility for downloading video and audio content
    using a highly resilient, multi-strategy approach powered by yt-dlp and FFmpeg.

.DESCRIPTION
    ARN-DL provides a rich, interactive console interface for fetching media from various
    sources. It is designed for maximum success rates through intelligent format analysis,
    robust fallback cascades, and multiple client emulation. The user experience is enhanced
    with custom animations and an integrated audio ambiance.

    This script is a labor of love, offered to the community. Please use it responsibly.

.AUTHOR
 ====== ARN Inside ====== 
 https://AlgoRythmic.Network/ARN-DL/
 Instagram : https://www.instagram.com/ARN.Inside/
#>
#==============================================================================
# DEFAULT CONFIGURATION SETTINGS
#==============================================================================
# This section contains the default script parameters.
# You can modify these settings to change the script's behavior.
#
# IMPORTANT NOTE ON OPTIONS:
# In the Show-OptionsMenu, the "Force MP4 re-encode" option is linked to the
# "Prefer .MP4" setting.
#
# - If '$script:PreferMp4Only' is set to '$true', the "Force MP4 re-encode"
#   option will be disabled (grayed out).

# --- Option switches ---
$script:PreferMp4Only       = $true
$script:ForceReencodeMP4    = $false 
$script:ReencodeKeepOriginal = $true
$script:ForceBruteForce     = $false

# --- Hidden part ---
$script:EnableLogging       = $false
$script:ReencodeCRF         = 18
$script:ReencodePreset      = 'medium'
$script:ReencodeAudioBitrate = '320k'

#==============================================================================
# END OF DEFAULT CONFIGURATION SETTINGS
#==============================================================================

$script:Version = "1.0.0"

$script:integrityFailureReported = $false

# --- Performance Throttling for Integrity Checks ---
$script:integrityCheckIntervalSeconds = 30  # Check every 30 seconds maximum.
$script:lastIntegrityCheckTimestamp = (Get-Date).AddHours(-1) # Initialize to the past to ensure the first check runs.

# --- Core Component Alias Definitions ---
# These are essential for stability
Set-Alias -Name Assert-MandatoryFun -Value Invoke-ARNIntegrityCheck -Scope Script
Set-Alias -Name Invoke-GodsDivineAudioPlan -Value Invoke-ARNIntegrityCheck -Scope Script # In honor of Terry
Set-Alias -Name Ensure-VibeCompliance -Value Invoke-ARNIntegrityCheck -Scope Script

$scriptFolder = (Get-Item -Path $MyInvocation.MyCommand.Path).Directory.FullName
$documentsPath = [Environment]::GetFolderPath('MyDocuments')

# --- Log File Initialization ---
# If logging is enabled, create a unique, timestamped log file path for the script run.
if ($script:EnableLogging) {
    $logFolder = $scriptFolder
    New-Item -Path $script:LogFolder -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $script:SessionLogFile = Join-Path $script:LogFolder "debug_run_log_$($timestamp).txt"
}

# -------------------- AESTHETICS CONFIGURATION --------------------
# Parameters for the Matrix animation. Governs density, speed, and keyword frequency.
$script:MatrixChars       = @('0','1','|','!','-','+',' ',' ',' ',' ','†')
$script:MatrixIntervals   = @{ Menu = 140; Analysis = 140; Download = 140 }
$script:MatrixWordChance  = @{ Menu = 0.45; Analysis = 0.64; Download = 0.55 }
$script:MatrixWords       = @{
    Menu     = @('ARN.Inside','AlgoRythmic.Network', 'ARN')
    Analysis = @('Inside', 'ARN.Inside','AlgoRythmic.Network','ARN', 'Algo')
    Download = @('CLOUD CONNEXION','GOD IS IN THE WIRE','Terry A. Devis' , 'TempleOS','August ††, 20†8','You Suck at Programming','†')
}

# Matrix Anti-flicker: Prevents visual glitches during intensive operations.
$script:MatrixConfig = [pscustomobject]@{
    AnimateDuringDownloads = $true
    MinWidth  = 90
    MinHeight = 28
}

# Common yt-dlp switches applied to most commands.
$script:YtDlpCommonSwitches = @(
    '--no-warnings',
    '--ignore-config',
    '--ignore-errors'
)

# ==============================================================================
# --- Performance and client profiles ---

# Defines the client emulation strategy. 'max' is more thorough but slower. 'safe' is faster.
$script:ClientsProfile = 'max'

function Get-ClientList {
    param(
        [ValidateSet('merge','progressive_non_android','progressive_android')][string]$Kind
    )
    if ($script:ClientsProfile -eq 'max') {
        $merge = @($null,'web','web_safari','web_embedded','mweb','ios','ios_embedded','tv','tv_embedded','web_music','android','android_embedded')
        $progNA = @($null,'web','web_safari','web_embedded','mweb','ios','ios_embedded','tv','tv_embedded','web_music')
        $progA = @('android','android_embedded')
    } else {
        $merge = @($null,'web','web_safari','mweb','ios','tv','android')
        $progNA = @($null,'web','web_safari','mweb','ios','tv')
        $progA = @('android')
    }
    switch ($Kind) {
        'merge' { return $merge }
        'progressive_non_android' { return $progNA }
        'progressive_android' { return $progA }
    }
}

# --- AUDIO (silent) ---
function Start-AudioLoop { param ([string]$Path) if (!(Test-Path -LiteralPath $Path)) { return }; try { Add-Type -AssemblyName System.Windows.Forms; $player = New-Object System.Media.SoundPlayer $Path; $player.PlayLooping(); $script:audioPlayer = $player } catch {} }
function Stop-AudioLoop  { if ($script:audioPlayer) { try { $script:audioPlayer.Stop(); $script:audioPlayer.Dispose(); Remove-Variable audioPlayer -Scope Script -ErrorAction Ignore } catch {} } }

# --- AUDIO: auto-pause on window minimize ---
# Leverages Win32 API to detect when the console window is minimized to pause audio.
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class Win32Min {
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool IsIconic(IntPtr hWnd);
}
"@ -ErrorAction SilentlyContinue

$script:audioDesiredPath = $null
$script:audioWasAutoPaused = $false
function Audio-AutoPauseStep {
    try {
        $hwnd = [Win32Min]::GetConsoleWindow()
        if ($hwnd -eq [IntPtr]::Zero) { return }
        $isMin = [Win32Min]::IsIconic($hwnd)
        if ($isMin) {
            if ($script:audioPlayer -and -not $script:audioWasAutoPaused) { Stop-AudioLoop; $script:audioWasAutoPaused = $true }
        } else {
            if ($script:audioWasAutoPaused -and $script:audioDesiredPath -and (Test-Path -LiteralPath $script:audioDesiredPath) -and -not $script:audioPlayer) { Start-AudioLoop -Path $script:audioDesiredPath; $script:audioWasAutoPaused = $false }
        }
    } catch {}
}

# ----- Audio Manager -----
$script:MenuAudioPath     = $null
$script:DownloadAudioPath = $null
$script:CurrentAudioMode  = 'Menu'

<#
.SYNOPSIS
    Locates and initializes core audio components from multiple possible locations.
.DESCRIPTION
    This function robustly searches for the essential .wav files in a prioritized list
    of directories. It then performs a mandatory asset validation check before proceeding.
#>
function Initialize-AudioPlusDoubleWav {
    try {
        # Resolve candidate paths for menu music (ARN_Inside.wav)
        $menuCandidates = @(
            (Join-Path $documentsPath "ARN-DL\Data_Inside\Core_audio_components\ARN_Inside.wav"),
            (Join-Path $scriptFolder    "Data_Inside\Core_audio_components\ARN_Inside.wav"),
            (Join-Path $scriptFolder    "Core_audio_components\ARN_Inside.wav"),
            (Join-Path $parentFolder    "Data_Inside\Core_audio_components\ARN_Inside.wav"),
            (Join-Path $scriptFolder    "ARN_Inside.wav")
        ) | Where-Object { Test-Path -LiteralPath $_ }
        if ($menuCandidates -and $menuCandidates[0]) { $script:MenuAudioPath = $menuCandidates[0] }

        # Resolve candidate paths for download music
        $dlCandidates = @(
            (Join-Path $documentsPath "ARN-DL\Data_Inside\Core_audio_components\Dave Eddy - TempleOS Hymn Risen (Remix).wav"),
            (Join-Path $scriptFolder    "Data_Inside\Core_audio_components\Dave Eddy - TempleOS Hymn Risen (Remix).wav"),
            (Join-Path $scriptFolder    "Core_audio_components\Dave Eddy - TempleOS Hymn Risen (Remix).wav"),
            (Join-Path $parentFolder    "Data_Inside\Core_audio_components\Dave Eddy - TempleOS Hymn Risen (Remix).wav"),
            (Join-Path $scriptFolder    "Dave Eddy - TempleOS Hymn Risen (Remix).wav")
        ) | Where-Object { Test-Path -LiteralPath $_ }
        if ($dlCandidates -and $dlCandidates[0]) { $script:DownloadAudioPath = $dlCandidates[0] }
    } catch {}
    Assert-MandatoryFun
}

function Set-AudioMode {
    param([ValidateSet('Menu','Download')][string]$Mode,[string]$Path)
    $prevDesired = $script:audioDesiredPath
    $script:CurrentAudioMode = $Mode
    $script:audioDesiredPath = $Path
    try {
        $hwnd = [Win32Min]::GetConsoleWindow()
        $isMin = $false
        if ($hwnd -ne [IntPtr]::Zero) { $isMin = [Win32Min]::IsIconic($hwnd) }
        if ($isMin) { Stop-AudioLoop; $script:audioWasAutoPaused = $true }
        else {
            if ($script:audioPlayer -and $prevDesired -and ($prevDesired -eq $Path)) {
                $script:audioWasAutoPaused = $false
            } else {
                Stop-AudioLoop
                if ($Path -and (Test-Path -LiteralPath $Path)) { Start-AudioLoop -Path $Path; $script:audioWasAutoPaused = $false }
            }
        }
    } catch {}
}
function Start-MenuMusic     { Set-AudioMode -Mode 'Menu'     -Path $script:MenuAudioPath }
function Start-DownloadMusic { Set-AudioMode -Mode 'Download' -Path $script:DownloadAudioPath }
function Stop-AllMusic { Stop-AudioLoop }

#==================== START OF HELIX ANIMATION FUNCTION ====================
function Show-HelixAnimation {
<#
.SYNOPSIS
    Displays a DNA helix text animation in the console
    with two distinct colors. Designed to be stable on PowerShell 5.
#>
param(
    [string]$Text = "ARN ARN ARN Inside ",
    [int]$DurationSeconds = 10,
    # Colors are simple strings to avoid errors.
    [string]$ColorDNA1 = "Cyan",
    [string]$ColorDNA2 = "DarkBlue",
    [int]$FrameRate = 30,
    [double]$Amplitude = 20.0,
    [double]$Frequency = 0.4,
    [double]$Pitch = 2.0,
    [double]$ScrollSpeed = 4,
    [double]$RotationSpeed = 0.01
)

# --- SAFE COLOR VALIDATION ---
# Convert color names (string) to actual console colors.
# If the provided name is invalid, use a default color (White) instead of crashing.
try {
    $validColor1 = [System.Enum]::Parse([System.ConsoleColor], $ColorDNA1, $true)
}
catch {
    Write-Warning "Color '$ColorDNA1' is not valid. Using default color 'White'."
    $validColor1 = [System.ConsoleColor]::White
}

try {
    $validColor2 = [System.Enum]::Parse([System.ConsoleColor], $ColorDNA2, $true)
}
catch {
    Write-Warning "Color '$ColorDNA2' is not valid. Using default color 'White'."
    $validColor2 = [System.ConsoleColor]::White
}


# --- INITIALIZATION ---
# Save the initial console state for restoration.
$initialForegroundColor = [System.Console]::ForegroundColor
$initialCursorVisible = [System.Console]::CursorVisible

try {
    # Hide the cursor for a clean animation.
    [System.Console]::CursorVisible = $false

    # Get console dimensions.
    $width = [System.Console]::WindowWidth
    $height = [System.Console]::WindowHeight
    
    # Center points for 3D -> 2D projection.
    $centerX = $width / 2
    $centerY = $height / 2

    # Create in-memory buffers for flicker-free rendering.
    $currentBuffer = New-Object 'psobject[,]' $width, $height
    $previousBuffer = New-Object 'psobject[,]' $width, $height
    $zBuffer = New-Object 'double[,]' $width, $height

    $emptyCell = @{ Char = ' '; Color = $initialForegroundColor }
    for ($y = 0; $y -lt $height; $y++) {
        for ($x = 0; $x -lt $width; $x++) {
            $currentBuffer[$x, $y] = $emptyCell
            $previousBuffer[$x, $y] = $emptyCell
        }
    }

    # Initialize animation state variables.
    $verticalOffset = 0.0
    $rotationOffset = 0.0
    $sleepDuration = [int](1000 / $FrameRate)

    # --- MAIN ANIMATION LOOP ---
    $startTime = Get-Date
    while (((Get-Date) - $startTime).TotalSeconds -lt $DurationSeconds) {
        # 1. COMPOSITION PHASE: Build the next frame in memory.
        $emptyCellRender = @{ Char = ' '; Color = [System.Console]::BackgroundColor }
        for ($y = 0; $y -lt $height; $y++) {
            for ($x = 0; $x -lt $width; $x++) {
                $currentBuffer[$x, $y] = $emptyCellRender
                $zBuffer[$x, $y] = [double]::NegativeInfinity
            }
        }

        # Iterate on the 't' parameter to generate the helix points.
        for ($t = 0; $t -lt (2 * $height); $t += 0.2) {
            
            # Calculate 3D coordinates for the two strands.
            $angle1 = $Frequency * $t + $rotationOffset
            $x1 = $Amplitude * [System.Math]::Cos($angle1)
            $y1 = $Pitch * $t - $verticalOffset
            $z1 = $Amplitude * [System.Math]::Sin($angle1)

            $angle2 = $angle1 + [System.Math]::PI
            $x2 = $Amplitude * [System.Math]::Cos($angle2)
            $y2 = $y1
            $z2 = $Amplitude * [System.Math]::Sin($angle2)

            $points = @(
                @{X=$x1; Y=$y1; Z=$z1; Strand=1},
                @{X=$x2; Y=$y2; Z=$z2; Strand=2}
            )

            foreach ($point in $points) {
                $projX = [int]($point.X + $centerX)
                $projY = [int]($point.Y + $centerY)

                if (($projX -ge 0) -and ($projX -lt $width) -and ($projY -ge 0) -and ($projY -lt $height)) {
                    if ($point.Z -gt $zBuffer[$projX, $projY]) {
                        $zBuffer[$projX, $projY] = $point.Z
                        $charIndex = ([int]($t * 1.5)) % $Text.Length
                        $charToDraw = $Text[$charIndex]
                        $colorToDraw = if ($point.Strand -eq 1) { $validColor1 } else { $validColor2 }
                        $currentBuffer[$projX, $projY] = @{ Char = $charToDraw; Color = $colorToDraw }
                    }
                }
            }
        }

        # 2. RENDER PHASE: Display the frame in the console.
        for ($y = 0; $y -lt $height; $y++) {
            for ($x = 0; $x -lt $width; $x++) {
                $currentCell = $currentBuffer[$x, $y]
                $previousCell = $previousBuffer[$x, $y]

                if (($currentCell.Char -ne $previousCell.Char) -or ($currentCell.Color -ne $previousCell.Color)) {
                    [System.Console]::SetCursorPosition($x, $y)
                    
                    if ([System.Console]::ForegroundColor -ne $currentCell.Color) {
                        [System.Console]::ForegroundColor = $currentCell.Color
                    }
                    
                    $charToWrite = $currentCell.Char
                    [System.Console]::Write($charToWrite)

                    $previousBuffer[$x, $y] = $currentCell
                }
            }
        }

        # 3. UPDATE PHASE.
        $verticalOffset += $ScrollSpeed
        $rotationOffset += $RotationSpeed
        Start-Sleep -Milliseconds $sleepDuration
    }
}
finally {
    # --- CLEANUP ---
    # Restore the initial console state, no matter what happens.
    [System.Console]::CursorVisible = $initialCursorVisible
    [System.Console]::ForegroundColor = $initialForegroundColor
    [System.Console]::Clear()
}
}
#==================== END OF HELIX ANIMATION FUNCTION ======================

# --- Next Alias runtime ---
Set-Alias -Name Confirm-Assets -Value Invoke-ARNIntegrityCheck -Scope Script
Set-Alias -Name Execute-SanityCheck -Value Invoke-ARNIntegrityCheck -Scope Script

# =========================================================
# ===   LOGO ANIMATION FUNCTION DEFINITION      ===
# =========================================================
function Show-LogoAnimation {
    # Define the "settings" that the function accepts
    param(
        [int]$Repetitions = 30,
        [System.ConsoleColor]$LogoForegroundColor = "Green",
        [System.ConsoleColor]$ScreenBackgroundColor = "DarkBlue"
    )

    # The logo is defined inside the function
    $logoLines = @(
    '░░░░░░░░░░█░░░█░░░█░░░█░░░',
    '░░░░░░█░░█░░░█░░░█░░░█░░░█',
    '░░█░░█░░▄▀▀▀▀▀▀▀▀▀▀▀▀▄░░█░',
    '░█░░▄▀▀▀▀░░░░░░░░░░░░▀▀▀▄░',
    '░▀▀▀▀░░░░░░░░░░░░░░░░░░░▀▀',
    '░░░░░░░░░░░░░░░░░░░░░░░░░░',
    '░█▀█░█▀▄░█▄░█░░░░░█▀▄░█░░░',
    '░█▀█░█▀▄░█░▀█░▀▀▀░█░█░█░░░',
    '░▀░▀░▀░▀░▀░░▀░░░░░▀▀▀░▀▀▀░',
    '░░░░░░░░░░░░░░░░░░░░░░░░░░',
    '░▄▄▄░░░░░░░░░░░░░░░░░░░░▄▄',
    '░█░▀▄▄▄░░░░░░░░░░░░░▄▄▄▄▀░',
    '█░░░█░▀▄▄▄▄▄▄▄▄▄▄▄▄▀░░░█░░',
    '░░░█░░░█░░░█░░░█░░░█░░█░░░',
    '░░░░░░█░░░█░░░█░░░█░░░░░░░'
    )

    try {
        [System.Console]::CursorVisible = $false
        
        $iterationCounter = 0
        while ($iterationCounter -lt $Repetitions) {
            
            $consoleWidth = $Host.UI.RawUI.WindowSize.Width
            $consoleHeight = $Host.UI.RawUI.WindowSize.Height
            Clear-Host

            $logoHeight = $logoLines.Count
            $paddingTop = [Math]::Floor(($consoleHeight - $logoHeight) / 2)
            $fillLine = [string]'░' * $consoleWidth

            # Display the TOP (uses the background color passed as a parameter)
            for ($i = 0; $i -lt $paddingTop; $i++) { Write-Host $fillLine -BackgroundColor $ScreenBackgroundColor }

            # Display the LOGO (uses the colors passed as parameters)
            foreach ($line in $logoLines) {
                $paddingLeftCount = [Math]::Floor(($consoleWidth - $line.Length) / 2)
                $paddingLeft = [string]'░' * $paddingLeftCount
                $paddingRightCount = $consoleWidth - $line.Length - $paddingLeftCount
                $paddingRight = [string]'░' * $paddingRightCount
                Write-Host $paddingLeft -BackgroundColor $ScreenBackgroundColor -NoNewline
                Write-Host $line -ForegroundColor $LogoForegroundColor -BackgroundColor $ScreenBackgroundColor -NoNewline
                Write-Host $paddingRight -BackgroundColor $ScreenBackgroundColor
            }

            # Display the BOTTOM (uses the background color passed as a parameter)
            $remainingLines = $consoleHeight - $logoHeight - $paddingTop
            for ($i = 0; $i -lt $remainingLines; $i++) { Write-Host $fillLine -BackgroundColor $ScreenBackgroundColor }

            Start-Sleep -Milliseconds 123
            $iterationCounter++
        }
    }
    finally {
        [System.Console]::CursorVisible = $true
    }
}


function Invoke-ARNIntegrityCheck {
<#
.SYNOPSIS
    Performs periodic and on-demand validation of core runtime components.
.DESCRIPTION
    This function ensures the integrity of essential application assets required for the
    intended user experience. It employs a throttled, performance-conscious approach
    for continuous "heartbeat" monitoring and a blocking check for initial startup validation.
    Failure to comply results in a controlled application halt.
#>
    param (
        # If set, enables silent mode. On failure, the function will lock the application
        # instead of causing an immediate exit.
        [switch]$Silent
    )

    # =========================================================
    # ===   PERFORMANCE THROTTLING LOGIC (HEARTBEAT)        ===
    # =========================================================
    if ($Silent) {
        $now = Get-Date
        if (($now - $script:lastIntegrityCheckTimestamp).TotalSeconds -lt $script:integrityCheckIntervalSeconds) {
            # Interval not yet elapsed, skip the expensive check for this heartbeat and assume everything is fine.
            return $true
        }
    }
    # =========================================================

    # --- Performance Optimization (Memoization) for non-silent startup check ---
    if ($script:IntegrityChecked -and -not $Silent) {
        return $true
    }

    # The Sacred hashes for core audio components.
    $ReferenceHashes = @{
        "ARN_inside.wav"                              = '44AE835B624D4204349A565F298A6598D7314598BAA7E62266EFF6389EB811F0'
        "Dave Eddy - TempleOS Hymn Risen (Remix).wav" = 'B31D0EF14762711E75CFAE238665CC49A3A6BE50C8BD85BD054904B89629573E'
    }

    # --- Verification Logic ---
    try {
        # Define files to verify based on existing global variables
        $filesToVerify = @{
            "ARN_Inside.wav"                              = $script:MenuAudioPath
            "Dave Eddy - TempleOS Hymn Risen (Remix).wav" = $script:DownloadAudioPath
        }

        foreach ($entry in $filesToVerify.GetEnumerator()) {
            $fileName = $entry.Name
            $filePath = $entry.Value
            
            if (-not ($filePath -and (Test-Path -LiteralPath $filePath))) {
                throw "Essential experience component cannot be located: $fileName"
            }

            $currentHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $filePath).Hash.ToUpperInvariant()
            $referenceHash = $ReferenceHashes[$fileName].ToUpperInvariant()

            if ($currentHash -ne $referenceHash) {
                throw "Integrity of experience component '$fileName' has been compromised. Invalid hash."
            }
        }

        # --- UPDATE TIMESTAMPS ON SUCCESS ---
        if ($Silent) {
            $script:lastIntegrityCheckTimestamp = Get-Date
        }
        # Mark as checked for the non-silent path memoization.
        $script:IntegrityChecked = $true
        return $true
    }
    catch {
        $script:IntegrityChecked = $false
        if ($Silent) {
            if (-not $script:integrityFailureReported) {
                $script:integrityFailureReported = $true
                $errorMessage = @"
CRITICAL USER EXPERIENCE INTEGRITY FAILURE

Core audio components are missing or have been tampered with.
Application has been locked to prevent further instability.
"@
                Show-FatalIntegrityError -Message $errorMessage
            }
            Stop-AllMusic
            while ($true) {
                Start-Sleep -Seconds 1
            }
            # =========================================================

        } else {
            # --- Startup Compliance Failure Protocol ---
            Write-Error "CRITICAL USER EXPERIENCE INTEGRITY FAILURE: Audio component validation failed. Message: $($_.Exception.Message)"
            if ($Host.Name -eq 'ConsoleHost') {
                Write-Host "The script will now terminate to preserve the intended user experience. Press Enter to exit." -ForegroundColor Red
                [void]::ReadKey($true)
            }
            exit 1
        }
    }
}


# =================
# Matrix Rendering
# =================
$script:Matrix = $null
$script:__HeavyOutput = $false

function New-MatrixLine {
    param([int]$Width,[string[]]$Chars,[string[]]$Words,[double]$WordChance = 0.2)
    if ($Width -lt 2) { return "" }
    $arr = New-Object char[] $Width
    for ($i=0; $i -lt $Width; $i++) { $arr[$i] = [char]($Chars | Get-Random) }
    if ($Words -and (Get-Random -Minimum 0.0 -Maximum 1.0) -lt $WordChance) {
        $w = ($Words | Get-Random); $wLen = $w.Length
        if ($wLen -lt $Width) { $start = Get-Random -Minimum 0 -Maximum ($Width - $wLen); $charsW = $w.ToCharArray(); for ($j=0; $j -lt $wLen; $j++) { $arr[$start + $j] = $charsW[$j] } }
    }
    -join $arr
}

function Write-MatrixBanner {
    param([int]$Lines = 4,[string]$Context = "Menu")
    try {
        $win = $Host.UI.RawUI; $width = $win.WindowSize.Width; if ($width -lt 3) { $width = 80 }; $width = [Math]::Max(2, $width - 1); $top = $win.CursorPosition.Y
        $words = $script:MatrixWords[$Context]; if (-not $words) { $words = @() }
        $interval = $script:MatrixIntervals[$Context]; if (-not $interval) { $interval = 120 }
        $wordChance = $script:MatrixWordChance[$Context]; if (-not $wordChance) { $wordChance = 0.2 }
        $buf = @(); for ($i=0; $i -lt $Lines; $i++) { $buf += (New-MatrixLine -Width $width -Chars $script:MatrixChars -Words $words -WordChance $wordChance) }
        for ($r=0; $r -lt $Lines; $r++) { $color = if ($r -eq 0) {"Green"} else {"DarkGreen"}; Write-Host $buf[$r] -ForegroundColor $color }
        $script:Matrix = [PSCustomObject]@{ Top=$top; Height=$Lines; Width=$width; Chars=$script:MatrixChars; Buffer=$buf; IntervalMs=$interval; LastTick=Get-Date; Words=$words; WordChance=$wordChance }
    } catch {}
}

function Step-MatrixAnimation {
    if (-not (Confirm-Assets -Silent)) { return } # Visual components must be validated before rendering a frame.
    if (-not $script:Matrix) { return }
    try {
        $now = Get-Date; $win = $Host.UI.RawUI; $ws = $win.WindowSize; $wp = $win.WindowPosition; $w = $ws.Width; $h = $ws.Height
        if ($w -lt 3 -or $h -lt 2) { return }
        $visibleTop = $wp.Y; $visibleBottom = $wp.Y + $h - 1; $matTop = $script:Matrix.Top; $matBottom = $script:Matrix.Top + $script:Matrix.Height - 1
        if (-not (($matBottom -ge $visibleTop) -and ($matTop -le $visibleBottom))) { return }
        $heavy = [bool]$script:__HeavyOutput; if ($heavy -and -not $script:MatrixConfig.AnimateDuringDownloads) { return }
        $smallWin = ($w -lt $script:MatrixConfig.MinWidth) -or ($h -lt $script:MatrixConfig.MinHeight); if ($heavy -and $smallWin) { return }
        $interval = $script:Matrix.IntervalMs; if ($heavy) { $interval = [int]([Math]::Max(120, $interval * 1.5)) }
        if ((($now - $script:Matrix.LastTick).TotalMilliseconds) -lt $interval) { return }
        $w = [Math]::Max(2, $w - 1)
        if ($w -ne $script:Matrix.Width) {
            $newBuf = @(); for ($i=0; $i -lt $script:Matrix.Height; $i++) { $newBuf += (New-MatrixLine -Width $w -Chars $script:Matrix.Chars -Words $script:Matrix.Words -WordChance $script:Matrix.WordChance) }
            $script:Matrix.Buffer = $newBuf; $script:Matrix.Width = $w
        }
        $newLine = New-MatrixLine -Width $script:Matrix.Width -Chars $script:Matrix.Chars -Words $script:Matrix.Words -WordChance $script:Matrix.WordChance
        if ($script:Matrix.Buffer.Count -gt 1) { $script:Matrix.Buffer = ,$newLine + $script:Matrix.Buffer[0..($script:Matrix.Buffer.Count-2)] } else { $script:Matrix.Buffer = ,$newLine }
        $savedPos = $win.CursorPosition
        for ($i=0; $i -lt $script:Matrix.Height; $i++) {
            $row = $script:Matrix.Top + $i; if ($row -ge $win.BufferSize.Height) { break }
            $line = $script:Matrix.Buffer[$i]; if ($line.Length -lt $script:Matrix.Width) { $line = $line.PadRight($script:Matrix.Width) }
            $win.CursorPosition = New-Object System.Management.Automation.Host.Coordinates 0, $row
            $fg = if ($i -eq 0) {'Green'} else {'DarkGreen'}; $currentFg = $win.ForegroundColor; $win.ForegroundColor = $fg
            Write-Host $line -NoNewline; $win.ForegroundColor = $currentFg
        }
        $win.CursorPosition = $savedPos; $script:Matrix.LastTick = $now
    } catch {}
}



# --- UI helpers ---
function Write-Centered {
    param(
        [string]$Text,
        [System.ConsoleColor]$ForegroundColor = "Gray",
        [System.ConsoleColor]$BackgroundColor
    )

    # Prepare the parameters for the Write-Host command
    $writeHostParams = @{
        ForegroundColor = $ForegroundColor
    }
    # Add the BackgroundColor parameter ONLY if it has been provided
    if ($PSBoundParameters.ContainsKey('BackgroundColor')) {
        $writeHostParams.Add('BackgroundColor', $BackgroundColor)
    }

    try {
        # Get the console width only once
        $consoleWidth = $Host.UI.RawUI.WindowSize.Width
        
        $lines = $Text.Split([System.Environment]::NewLine)
        foreach ($line in $lines) {
            

            # 1. Calculate left and right padding
            $padLeft = [Math]::Max(0, [int](($consoleWidth - $line.Length) / 2))
            $padRight = [Math]::Max(0, $consoleWidth - $line.Length - $padLeft)

            # 2. Create a string that fills the entire line
            $fullLine = (' ' * $padLeft) + $line + (' ' * $padRight)
            
            # 3. Add this full line to our parameters
            $writeHostParams.Object = $fullLine

            # 4. Display the full line. The background color will apply everywhere.
            Write-Host @writeHostParams
        }
    }
    catch {
        # In case of an error (e.g., if the console is not interactive), display the raw text
        Write-Host $Text
    }
}

function Show-FatalIntegrityError {
<#
.SYNOPSIS
    Displays a persistent, centered error message box for critical failures.
#>
    param(
        [string]$Message
    )
    try {
        $win = $Host.UI.RawUI
        $width = $win.WindowSize.Width
        $height = $win.WindowSize.Height

        # Message box dimensions
        $boxWidth = [Math]::Min(80, $width - 4)
        $lines = $Message.Split([System.Environment]::NewLine)
        $boxHeight = $lines.Count + 2

        # Start position (centered)
        $startX = [Math]::Floor(($width - $boxWidth) / 2)
        $startY = [Math]::Floor(($height - $boxHeight) / 2)

        # Draw the box
        for ($i = 0; $i -lt $boxHeight; $i++) {
            $win.CursorPosition = New-Object System.Management.Automation.Host.Coordinates $startX, ($startY + $i)
            if ($i -eq 0 -or $i -eq ($boxHeight - 1)) {
                $border = ' ' * $boxWidth
                Write-Host $border -BackgroundColor DarkRed -NoNewline
            } else {
                $line = $lines[$i - 1]
                $padding = $boxWidth - $line.Length
                $padLeft = [Math]::Floor($padding / 2)
                $padRight = $padding - $padLeft
                $content = (' ' * $padLeft) + $line + (' ' * $padRight)
                Write-Host $content -ForegroundColor White -BackgroundColor DarkRed -NoNewline
            }
        }
    } catch {
        # Fallback for non-interactive consoles
        Write-Error $Message
    }
}

function Wait-KeyNonBlocking {
<#
.SYNOPSIS
    A non-blocking key-read loop that keeps background animations and checks running.
#>
    # High-frequency asset check to prevent runtime anomalies.
    if (-not (Execute-SanityCheck -Silent)) { return $null }
    while ($true) { 
        Step-MatrixAnimation; Audio-AutoPauseStep; if ([System.Console]::KeyAvailable) { return [System.Console]::ReadKey($true) } Start-Sleep -Milliseconds 30 
    } 
}

function Read-LineAnimated {
    param([string]$Prompt)
    $win=$Host.UI.RawUI; $w=$win.WindowSize.Width; $left=[Math]::Max(0,[int](($w - ($Prompt.Length + 2))/2)); Write-Host (' ' * $left) -NoNewline; Write-Host $Prompt -ForegroundColor Yellow -NoNewline
    $startCol = $left + $Prompt.Length; $row = $win.CursorPosition.Y; $current=''
    while ($true) {
        $win.CursorPosition = New-Object System.Management.Automation.Host.Coordinates $startCol, $row
        $clearLen = [Math]::Max(1, $w - $startCol - 1); $display = if ($current.Length -gt $clearLen) { $current.Substring(0,$clearLen) } else { $current }; $pad=' ' * ($clearLen - $display.Length)
        Write-Host ($display + $pad) -NoNewline; $win.CursorPosition = New-Object System.Management.Automation.Host.Coordinates ($startCol + $display.Length), $row
        if ([System.Console]::KeyAvailable) {
            $ki=[System.Console]::ReadKey($true)
            switch ($ki.Key) {
                'Enter' { Write-Host ''; return $current }
                'Backspace' { if ($current.Length -gt 0) { $current = $current.Substring(0,$current.Length-1) } }
                'Escape' { Write-Host ''; return '' }
                default { $ch=$ki.KeyChar; if ($ch -and ([int][char]$ch) -ge 32) { $current += $ch } }
            }
        } else { Step-MatrixAnimation; Audio-AutoPauseStep; Start-Sleep -Milliseconds 30 }
    }
}

function Read-MultipleLinesAnimated {
    param([string]$Header = "Paste one or more video links.")
    Clear-Host; Write-MatrixBanner -Lines 4 -Context "Menu"; Write-Centered $Header "Yellow"; Write-Centered "Separate with comma (,), semicolon (;), or new lines."; Write-Centered "Press Enter on an empty line when you are done."; Write-Host ""
    $lines = New-Object System.Collections.Generic.List[string]
    while ($true) { $line = Read-LineAnimated -Prompt " -> "; if ([string]::IsNullOrWhiteSpace($line)) { break }; $lines.Add($line) }
    return $lines.ToArray()
}

# --- External execution (yt-dlp/ffmpeg) ---
function Quote-Arg { param([string]$Arg) if ($null -eq $Arg) { return '""' } if ($Arg -match '[\s"]') { return '"' + ($Arg -replace '"','\"') + '"' } return $Arg }
function Invoke-ExternalAnimated {
<#
.SYNOPSIS
    Executes an external process (like yt-dlp.exe) while keeping the UI animated.
#>
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [switch]$CaptureOutput,
        [switch]$Heavy = $true,
        [string]$WorkingDirectory = (Get-Location).Path,
        [int]$PollMs = 80
    )

    # All core functionalities are guided by a divine plan.
    if (-not (Invoke-GodsDivineAudioPlan -Silent)) { 
        return [PSCustomObject]@{ ExitCode = -999; Error = "Divine plan integrity check failed"; StdOut=@(); StdErr=@("Divine plan integrity check failed") }
    }


    $argsAll = @()
    if ($FilePath -eq $ytDlpExe) { $argsAll += $script:YtDlpCommonSwitches; $argsAll += (Get-CookiesArgs) }
    if ($Arguments) { $argsAll += $Arguments }
    $argString = ($argsAll | ForEach-Object { Quote-Arg $_ }) -join ' '
    
    $sp = @{ FilePath=$FilePath; ArgumentList=$argString; WorkingDirectory=$WorkingDirectory; PassThru=$true; NoNewWindow=$true }
    
    $tempOut=$null; $tempErr=$null
    if ($CaptureOutput) {
        $tempOut=[System.IO.Path]::GetTempFileName()
        $tempErr=[System.IO.Path]::GetTempFileName()
        $sp['RedirectStandardOutput']=$tempOut
        $sp['RedirectStandardError']=$tempErr
    }

    $setHeavy=$false;
    if ($Heavy) { $script:__HeavyOutput = $true; $setHeavy=$true }

    try {
        $proc = Start-Process @sp
        if (-not $proc) { return [PSCustomObject]@{ ExitCode=-1; StdOut=@(); StdErr=@(); Error="Failed to start $FilePath" } }
        
        while (-not $proc.HasExited) {
            Step-MatrixAnimation
            Audio-AutoPauseStep
            Start-Sleep -Milliseconds $PollMs
        }

        $outLines=@(); $errLines=@()
        if ($CaptureOutput) {
            # Use default encoding here, which is sufficient for simple titles.
            try { $outLines = Get-Content -LiteralPath $tempOut -Encoding Default -ErrorAction SilentlyContinue } catch {}
            try { $errLines = Get-Content -LiteralPath $tempErr -Encoding Default -ErrorAction SilentlyContinue } catch {}
        }
        return [PSCustomObject]@{ ExitCode=$proc.ExitCode; StdOut=$outLines; StdErr=$errLines; Error=$null }
    }
    finally {
        if ($setHeavy) { $script:__HeavyOutput = $false }
        if ($CaptureOutput) {
            try { Remove-Item -LiteralPath $tempOut -ErrorAction SilentlyContinue } catch {}
            try { Remove-Item -LiteralPath $tempErr -ErrorAction SilentlyContinue } catch {}
        }
    }
}


# ===================== Robust URL analysis helpers (restored + enhanced) =====================


function Remove-BOM {
    param([string]$s)
    if ($null -eq $s) { return $null }
    $bom = [char]0xFEFF
    if ($s.StartsWith($bom)) { return $s.Substring(1) }
    return $s
}

function Test-HttpUrl {
    param([string]$u)
    if ([string]::IsNullOrWhiteSpace($u)) { return $false }
    $u = $u.Trim()
    return ($u -match '^(https?|http)://')
}

function Normalize-YT-WatchUrl {
    param([string]$u)
    if ([string]::IsNullOrWhiteSpace($u)) { return $null }
    $u = $u.Trim()
    if ($u -match '^https?://youtu\.be/([^?\s&/]+)') {
        $id = $matches[1]
        $qs = ''
        if ($u -match '\?(.*)$') { $qs = '&' + $matches[1] }
        return 'https://www.youtube.com/watch?v=' + $id + $qs
    }
    if ($u -match '^https?://(www\.)?youtube\.com/shorts/([^?\s&/]+)') {
        $id = $matches[2]
        return 'https://www.youtube.com/watch?v=' + $id
    }
    return $u
}

function New-VideoEntry {
    param([string]$Title,[string]$Url,[string]$PlaylistTitle)
    if ([string]::IsNullOrWhiteSpace($Title) -or [string]::IsNullOrWhiteSpace($Url)) { return $null }
    $u = Normalize-YT-WatchUrl -u $Url
    if (-not (Test-HttpUrl -u $u)) { return $null }
    return [PSCustomObject]@{ title=$Title; webpage_url=$u; playlist_title= if ([string]::IsNullOrWhiteSpace($PlaylistTitle) -or $PlaylistTitle -eq 'NA') { $null } else { $PlaylistTitle } }
}

function Parse-YTDLP-PrintLines {
    param([string[]]$Lines,[string]$DefaultPlaylistTitle = $null)
    $out = @()
    if (-not $Lines) { return $out }
    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line.Split(';',3)
        $t = if ($parts.Length -ge 1) { $parts[0].Trim() } else { $null }
        $u = if ($parts.Length -ge 2) { $parts[1].Trim() } else { $null }
        $p = $null
        if ($parts.Length -ge 3) { $p = $parts[2].Trim() }
        if ([string]::IsNullOrWhiteSpace($p)) { $p = $DefaultPlaylistTitle }
        if ($u -in @('NA','N/A','null','None','')) { $u = $null }
        if ($t -in @('NA','N/A','null','None','')) { $t = $null }
        $e = New-VideoEntry -Title $t -Url $u -PlaylistTitle $p
        if ($e) { $out += $e }
    }
    return $out
}

function Resolve-URLVideoEntries {
<#
.SYNOPSIS
    Robustly resolves a single URL into a list of individual video entries.
.DESCRIPTION
    This function employs a multi-strategy approach to extract video information.
    It handles single videos, playlists, and various URL formats.
    It attempts several yt-dlp commands to maximize successful extraction.
#>
    param([string]$Url)
    $Url = $Url.Trim()
    $acc = @()
    $seen = New-Object System.Collections.Generic.HashSet[string]
    $plTitle = $null

    # Strategy 1: direct print
    $a1 = Invoke-ExternalAnimated -FilePath $ytDlpExe -Arguments @("--print","%(title)s;%(webpage_url)s;%(playlist_title)s", $Url) -CaptureOutput -Heavy:$false
    if ($a1.StdOut) {
        $entries = Parse-YTDLP-PrintLines -Lines $a1.StdOut
        foreach ($e in $entries) { if ($seen.Add($e.webpage_url)) { $acc += $e } }
    }

    # Strategy 2: flat playlist with id->watch
    $a2 = Invoke-ExternalAnimated -FilePath $ytDlpExe -Arguments @("--flat-playlist","--print","%(title)s;%(webpage_url)s;%(playlist_title)s", $Url) -CaptureOutput -Heavy:$false
    if ($a2.StdOut) {
        $entries = Parse-YTDLP-PrintLines -Lines $a2.StdOut
        foreach ($e in $entries) { if ($seen.Add($e.webpage_url)) { $acc += $e } }
    }

    # Strategy 3: JSON fallback
    if ($acc.Count -eq 0) {
        $a3 = Invoke-ExternalAnimated -FilePath $ytDlpExe -Arguments @("--flat-playlist","-J",$Url) -CaptureOutput -Heavy:$false
        if ($a3.StdOut) {
            try {
                $jsonText = ($a3.StdOut -join "`n")
                $obj = $jsonText | ConvertFrom-Json
                if ($obj.title) { $plTitle = $obj.title }
                if ($obj.entries) {
                    foreach ($e in $obj.entries) {
                        try {
                            $t = $e.title
                            $u = $null
                            if ($e.webpage_url -and (Test-HttpUrl $e.webpage_url)) { $u = $e.webpage_url }
                            elseif ($e.url -and (Test-HttpUrl $e.url)) { $u = $e.url }
                            $ent = New-VideoEntry -Title $t -Url $u -PlaylistTitle $plTitle
                            if ($ent) { if ($seen.Add($ent.webpage_url)) { $acc += $ent } }
                        } catch {}
                    }
                } else {
                    $t = $obj.title
                    $u = $null
                    if ($obj.webpage_url -and (Test-HttpUrl $obj.webpage_url)) { $u = $obj.webpage_url }
                    elseif ($obj.url -and (Test-HttpUrl $obj.url)) { $u = $obj.url }
                    elseif ($obj.id) { $u = "https://www.youtube.com/watch?v=$($obj.id)" }
                    $ent = New-VideoEntry -Title $t -Url $u -PlaylistTitle $null
                    if ($ent) { if ($seen.Add($ent.webpage_url)) { $acc += $ent } }
                }
            } catch {}
        }
    }

    # Strategy 4: accept raw watch/youtu.be/shorts as last resort
    if ($acc.Count -eq 0) {
        if ($Url -match '^https?://(www\.)?youtube\.com/watch\?v=' -or $Url -match '^https?://youtu\.be/' -or $Url -match '^https?://(www\.)?youtube\.com/shorts/') {
            $t = $null
            try {
                $a4 = Invoke-ExternalAnimated -FilePath $ytDlpExe -Arguments @("--print","%(title)s", $Url) -CaptureOutput -Heavy:$false
                if ($a4.StdOut -and $a4.StdOut.Count -ge 1) { $t = ($a4.StdOut[0]).Trim() }
            } catch {}
            if (-not $t) { $t = "YouTube Video" }
            $u = Normalize-YT-WatchUrl -u $Url
            $ent = New-VideoEntry -Title $t -Url $u -PlaylistTitle $null
            if ($ent) { if ($seen.Add($ent.webpage_url)) { $acc += $ent } }
        }
    }
    return $acc
}

# --- Formats / attempts ---
function Invoke-YTDLPVideoAttempt {
    param(
        [Parameter(Mandatory=$true)][string]$Fmt,
        [Parameter(Mandatory=$true)][string]$Out,
        [Parameter(Mandatory=$true)][string]$Url,
        [string]$Client = $null,
        [string]$MergeContainer = 'mp4'
    )
    $args = @()
    if ($Client) { $args += @('-N','3', '--extractor-args', "youtube:player_client=$Client") }
    $args += @(
        '-f', $Fmt,
        # FIX: Sorting is now permissive and prioritizes quality (resolution, bitrates).
        '-S', 'res,vbr,abr,fps,vcodec,acodec,ext',
        '--skip-unavailable-fragments',
        '--merge-output-format', $MergeContainer,
        '-o', $Out,
        $Url,
        '--retries','3','--fragment-retries','3','--sleep-interval','1','--max-sleep-interval','5'
    )
    [void](Invoke-ExternalAnimated -FilePath $ytDlpExe -Arguments $args)
    return (Test-Path -LiteralPath $Out)
}

function Invoke-YTDLPAudioAttempt {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Fmt,

        [Parameter(Mandatory=$true)]
        # The full path for the output audio file (.wav or .mp3)
        [string]$OutFile,

        [Parameter(Mandatory=$true)]
        [string]$Url,

        [string]$Client = $null,

        # The desired audio format ('wav' or 'mp3')
        [string]$AudioFormat = 'wav'
    )
    $args = @()
    if ($Client) { $args += @('-N','3', '--extractor-args', "youtube:player_client=$Client") }
    
    # Build the base arguments for yt-dlp
    $args += @(
        '-f', $Fmt,
        # Optimized audio sorting, prioritizing bitrate and sample rate.
        '-S', 'abr,asr,acodec,ext',
        '--skip-unavailable-fragments'
    )

    # Add format-specific arguments based on the user's choice
    if ($AudioFormat -eq 'wav') {
        $args += @('-x','--audio-format','wav')
    } else { # Assuming mp3
        # For MP3, use --audio-quality 0 (best VBR for the LAME codec) instead of a fixed bitrate.
        $args += @('-x','--audio-format','mp3', '--audio-quality', '0')
    }

    # Add the remaining arguments (output path, URL, and retry logic)
    $args += @(
        '-o', $OutFile,
        $Url,
        '--retries','3','--fragment-retries','3','--sleep-interval','1','--max-sleep-interval','5'
    )
    [void](Invoke-ExternalAnimated -FilePath $ytDlpExe -Arguments $args)
    return (Test-Path -LiteralPath $OutFile)
}


function Ensure-WavFormat {
<#
.SYNOPSIS
    Ensures a .WAV file conforms to a high-quality standard (24-bit, 48kHz).
#>
    param(
        [Parameter(Mandatory=$true)][string]$WavPath
    )
    try {
        if (!(Test-Path -LiteralPath $WavPath)) { return $false }

        # Force the best settings, because we ALWAYS want maximum quality.
        $targetCodec = 'pcm_s24le' # 24-bit audio (High Definition)
        $targetAr    = '48000'     # 48kHz (Studio Quality)

        $tmp = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($WavPath), [System.IO.Path]::GetFileNameWithoutExtension($WavPath) + ".__tmp__.wav")
        $args = @("-i", $WavPath, "-vn", "-acodec", $targetCodec, "-ar", $targetAr, $tmp, "-y","-hide_banner","-loglevel","error")
        [void](Invoke-ExternalAnimated -FilePath $ffmpegExe -Arguments $args -CaptureOutput)
        if (Test-Path -LiteralPath $tmp) {
            try { Remove-Item -LiteralPath $WavPath -Force -ErrorAction SilentlyContinue } catch {}
            try { Move-Item -LiteralPath $tmp -Destination $WavPath -Force } catch {}
            return (Test-Path -LiteralPath $WavPath)
        }
    } catch {}
    return $true
}


function Get-AudioFormatExpression {
    # Returns the most robust audio format selection cascade for yt-dlp.
    return 'bestaudio[acodec*=opus]/bestaudio[ext=m4a]/bestaudio'
}

function Reencode-MKV-To-MP4 {
    param(
        [Parameter(Mandatory=$true)][string]$InFile,
        [Parameter(Mandatory=$true)][string]$OutMp4
    )
    try {
        Write-Centered "High-quality re-encoding .MKV to .MP4" "Yellow"
        
        
            try {
                $ffprobeOutput = (& $ffprobeExe -v quiet -print_format json -show_format -show_streams $InFile) -join "`n"
                $fileInfo = $ffprobeOutput | ConvertFrom-Json

                $fileName = (Split-Path $InFile -Leaf)
                $durationSecs = [double]$fileInfo.format.duration
                $duration = [timespan]::FromSeconds($durationSecs).ToString('hh\:mm\:ss')
                
                $videoStream = $fileInfo.streams | Where-Object { $_.codec_type -eq 'video' } | Select-Object -First 1
                $audioStream = $fileInfo.streams | Where-Object { $_.codec_type -eq 'audio' } | Select-Object -First 1


                # Build the banner as a multi-line string first.
                $bannerText = @"
  > File    : $fileName
  > Duration: $duration

"@

                Write-Host $bannerText -ForegroundColor "White"

            } catch {

                Write-Centered "Starting high-quality re-encoding .MKV to .MP4..." "Yellow"
            }


            # ffmpeg arguments
            $args = @(
                "-i", $InFile,
                "-map", "0:v:0?", "-map", "0:a:0?",
                "-c:v", "libx264", "-crf", $script:ReencodeCRF, "-preset", $script:ReencodePreset,
                "-c:a", "aac", "-b:a", $script:ReencodeAudioBitrate,
                "-movflags", "+faststart",
                $OutMp4, "-y", "-hide_banner",
                "-loglevel", "fatal",
                "-stats" 
            )

            [void](Invoke-ExternalAnimated -FilePath $ffmpegExe -Arguments $args -CaptureOutput:$false)

            # The result of the conversion is stored in a variable first...
            $success = (Test-Path -LiteralPath $OutMp4)
            
            # ...so that we can display a message before exiting the function.
            if ($success) {
                Write-Centered "✔ Re-encoding successful!" "Green"
            } else {
                Write-Centered "❌ Re-encoding failed." "Red"
            }
            Start-Sleep -Seconds 2
            
            # Finally, the stored result is returned.
            return $success


    } catch { 
        return $false 
    }
}

function Set-FileMetadata {
<#
.SYNOPSIS
    Injects a comment into the metadata of a media file using FFmpeg.
.DESCRIPTION
    This function safely adds a comment to a file's metadata. It uses a fast,
    stream-copy method for containers like MP4/MKV, a specialized command for WAV files 
    to ensure Windows Explorer compatibility, and a specific ID3v2.3 command for MP3 files.
#>
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][string]$Comment
    )
    
    if (-not (Test-Path -LiteralPath $FilePath)) { return }

    # Create a temporary path for the output file to avoid in-place modification risks.
    $tempPath = [System.IO.Path]::Combine(
        [System.IO.Path]::GetDirectoryName($FilePath),
        ([System.IO.Path]::GetFileNameWithoutExtension($FilePath) + ".tmp" + [System.IO.Path]::GetExtension($FilePath))
    )

    try {
        $ffmpegArgs = @()

        # --- SMART COMMAND SELECTION BASED ON FILE TYPE ---
        $extension = [System.IO.Path]::GetExtension($FilePath).ToLower()

        if ($extension -eq '.wav') {
            # For WAV files, we must re-mux the file to write metadata.
            # This is lossless and fast as we specify the same PCM codec.
            $ffmpegArgs = @(
                "-i", $FilePath,
                "-map_metadata", "0",
                "-metadata", "album=$Comment",
                "-c:a", "pcm_s24le",
                $tempPath,
                "-y", "-hide_banner", "-loglevel", "fatal"
            )
        } elseif ($extension -eq '.mp3') {
            # For MP3 files, we must force ID3v2.3 for Windows Explorer compatibility.
            $ffmpegArgs = @(
                "-i", $FilePath,
                "-map_metadata", "0",
                "-metadata", "album=$Comment",
                "-c:a", "copy",

                "-b:a", "320k",            # Set a high bitrate for audio quality
                "-id3v2_version", "3",     # This is the critical flag for MP3
                $tempPath,
                "-y", "-hide_banner", "-loglevel", "fatal"
            )
        } else {
            # For modern containers (MP4, MKV), a simple stream copy is fast and effective.
            $ffmpegArgs = @(
                "-i", $FilePath,
                "-map_metadata", "0",
                "-metadata", "comment=$Comment",
                "-c", "copy",
                $tempPath,
                "-y", "-hide_banner", "-loglevel", "fatal"
            )
        }

        # Use the script's existing animated execution function for a consistent UI.
        $result = Invoke-ExternalAnimated -FilePath $ffmpegExe -Arguments $ffmpegArgs -CaptureOutput:$false -Heavy:$false
        
        # Verify that the new file was created successfully before replacing the original.
        if ((Test-Path -LiteralPath $tempPath) -and (Get-Item $tempPath).Length -gt 0) {
            # Safely replace the original file with the new one.
            Move-Item -LiteralPath $tempPath -Destination $FilePath -Force
        }
    }
    catch {
        # If an error occurs, we log it but don't halt the script.
        Write-Centered "Metadata injection failed for ${FilePath}: $($_.Exception.Message)" "Red"
    }
    finally {
        # Ensure the temporary file is always cleaned up, whether it succeeded or failed.
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function New-RiffInfoSubChunk {
<#
.SYNOPSIS
    Creates a binary sub-chunk for a RIFF 'INFO' list.

.DESCRIPTION
    This helper function constructs a single, properly formatted and padded sub-chunk 
    (like 'ICMT' for comment or 'IPRD' for product/album) according to RIFF specifications.
    It takes a 4-character ID and a string content, and returns a byte array.

.PARAMETER Id
    A 4-character string representing the chunk ID (e.g., 'ICMT', 'IPRD').

.PARAMETER Content
    The string content to be embedded in the chunk.

.EXAMPLE
    $commentChunkBytes = New-RiffInfoSubChunk -Id 'ICMT' -Content "My custom comment."

.NOTES
    The unary comma operator ',' in the return statement is critical. It ensures PowerShell 
    returns a single byte[] array object instead of unrolling the array elements, which 
    prevents type conversion errors.
#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Id,

        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    # Use a shared ASCII encoder for consistency
    $ascii = [System.Text.Encoding]::ASCII

    # Return null if there is no content to process
    if ([string]::IsNullOrEmpty($Content)) { return $null }

    # Convert the string to bytes and add a null terminator, as required by the RIFF spec
    $dataBytes = $ascii.GetBytes($Content) + [byte]0
    $dataSize = $dataBytes.Length
    
    # Ensure the data payload is padded to an even number of bytes (WORD-aligned)
    $paddedDataBytes = $dataBytes
    if ($dataSize % 2 -ne 0) { 
        $paddedDataBytes += [byte]0
    }
    
    # Construct the chunk header (4-byte ID + 4-byte size)
    $headerBytes = $ascii.GetBytes($Id) + [System.BitConverter]::GetBytes([uint32]$dataSize)
    
    # Return the full chunk as a single byte[] array object
    return ,($headerBytes + $paddedDataBytes)
}


#============================================================================
# MAIN FUNCTION
#============================================================================

function Set-WavMetadata {
<#
.SYNOPSIS
    Adds or replaces metadata in a WAV audio file using a memory-efficient streaming method.

.DESCRIPTION
    This function reads a source WAV file, extracts its essential audio format ('fmt ') and data ('data') chunks,
    and writes a new WAV file with the specified Album and Comment metadata.

    It is designed to handle very large files without consuming excessive RAM by streaming the large 'data'
    chunk directly from the source to the destination file. The original file is never modified.

.PARAMETER Path
    The full path to the source WAV file.

.PARAMETER OutputPath
    Optional. The full path for the new WAV file. If not provided, a new file is created
    in the same directory with a "-meta" suffix.

.PARAMETER Comment
    The comment string to embed in the metadata.

.PARAMETER Album
    The album name string to embed in the metadata.

.EXAMPLE
    Set-WavMetadata -Path "C:\Audio\MySong.wav" -Comment "Recorded in 2025" -Album "Greatest Hits" -Verbose

.OUTPUTS
    None. This function writes a file to disk.
#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [string]$Comment,

        [Parameter(Mandatory = $false)]
        [string]$Album
    )

    begin {
        # Reusable ASCII encoder for converting between strings and bytes
        $ascii = [System.Text.Encoding]::ASCII
    }

    process {
        # --- Initial Validation ---
        if (-not (Test-Path -Path $Path -PathType Leaf)) { throw "Input file not found: '$Path'" }
        if ([string]::IsNullOrEmpty($Comment) -and ([string]::IsNullOrEmpty($Album))) { Write-Warning "No Comment or Album metadata was provided. No action taken."; return }
        if ([string]::IsNullOrEmpty($OutputPath)) {
            $dirName = [System.IO.Path]::GetDirectoryName($Path)
            $fileName = [System.IO.Path]::GetFileNameWithoutExtension($Path)
            $extension = [System.IO.Path]::GetExtension($Path)
            $OutputPath = Join-Path -Path $dirName -ChildPath "$($fileName)-meta$($extension)"
        }

        # --- STEP 1: Create the new metadata 'LIST' chunk safely in memory ---
        $infoSubChunks = [byte[]]@()
        if (-not [string]::IsNullOrEmpty($Comment)) {
            $icmtChunk = New-RiffInfoSubChunk -Id 'ICMT' -Content $Comment
            if ($null -ne $icmtChunk) { $infoSubChunks += $icmtChunk }
        }
        if (-not [string]::IsNullOrEmpty($Album)) {
            $iprdChunk = New-RiffInfoSubChunk -Id 'IPRD' -Content $Album
            if ($null -ne $iprdChunk) { $infoSubChunks += $iprdChunk }
        }
        if ($infoSubChunks.Length -eq 0) { Write-Warning "No metadata to write."; return }

        # Use MemoryStream to safely build the final LIST chunk byte array, avoiding type corruption from '+' operator
        $listMemStream = New-Object System.IO.MemoryStream
        $listTypeBytes = $ascii.GetBytes('INFO')
        $listDataSize = $listTypeBytes.Length + $infoSubChunks.Length
        $listHeaderBytes = $ascii.GetBytes('LIST') + [System.BitConverter]::GetBytes([uint32]$listDataSize)

        $listMemStream.Write($listHeaderBytes, 0, $listHeaderBytes.Length)
        $listMemStream.Write($listTypeBytes, 0, $listTypeBytes.Length)
        $listMemStream.Write($infoSubChunks, 0, $infoSubChunks.Length)
        $listInfoChunk = $listMemStream.ToArray()
        $listMemStream.Close()
        
        Write-Verbose "New 'LIST INFO' chunk created with size $($listInfoChunk.Length) bytes."

        # --- STEP 2: Analyze the source file to locate essential chunks ---
        $fmtChunkBytes = $null
        $dataChunkPosition = -1
        $dataChunkSize = -1
        $reader = $null
        try {
            $reader = New-Object System.IO.BinaryReader([System.IO.File]::OpenRead($Path), $ascii)
            # Validate RIFF/WAVE header
            if ($ascii.GetString($reader.ReadBytes(4)) -ne 'RIFF' -or ($reader.ReadUInt32() -eq 0) -or $ascii.GetString($reader.ReadBytes(4)) -ne 'WAVE') {
                throw "'$Path' is not a valid WAV file."
            }

            # Loop through the file to find chunks
            while ($reader.BaseStream.Position + 8 -le $reader.BaseStream.Length) {
                $chunkIdBytes = $reader.ReadBytes(4)
                $chunkId = $ascii.GetString($chunkIdBytes)
                $chunkSize = $reader.ReadUInt32()
                
                if ($chunkId -eq 'fmt ') {
                    Write-Verbose "Found 'fmt ' chunk. Copying to memory."
                    $fmtChunkContent = $reader.ReadBytes($chunkSize)
                    
                    # Safely construct the full fmt chunk byte array to avoid type corruption
                    $memStream = New-Object System.IO.MemoryStream
                    $memStream.Write($chunkIdBytes, 0, $chunkIdBytes.Length)
                    $sizeBytes = [System.BitConverter]::GetBytes($chunkSize)
                    $memStream.Write($sizeBytes, 0, $sizeBytes.Length)
                    $memStream.Write($fmtChunkContent, 0, $fmtChunkContent.Length)
                    $fmtChunkBytes = $memStream.ToArray()
                    $memStream.Close()

                } elseif ($chunkId -eq 'data') {
                    Write-Verbose "Found 'data' chunk. Storing position $($reader.BaseStream.Position) and size $chunkSize."
                    $dataChunkPosition = $reader.BaseStream.Position # Position of the payload, after ID and size
                    $dataChunkSize = $chunkSize
                    $reader.BaseStream.Seek($chunkSize, [System.IO.SeekOrigin]::Current) | Out-Null
                } else {
                    # Skip all other chunks
                    $reader.BaseStream.Seek($chunkSize, [System.IO.SeekOrigin]::Current) | Out-Null
                }

                # Advance past the padding byte in the source stream if the chunk size is odd
                if ($chunkSize % 2 -ne 0) { $reader.ReadByte() | Out-Null }
            }
        } finally {
            if ($reader) { $reader.Close() }
        }

        if ($null -eq $fmtChunkBytes -or $dataChunkPosition -eq -1) {
            throw "Essential 'fmt ' or 'data' chunks were not found in the source file."
        }
        
        # --- STEP 3: Faithfully reconstruct the new file in the correct order ---
        $inputStream = $null
        $writer = $null
        try {
            # Calculate the final file size, accounting for padding on each chunk's data payload
            $fmtDataSize = $fmtChunkBytes.Length - 8
            $fileBodySize = $fmtChunkBytes.Length
            if ($fmtDataSize % 2 -ne 0) { $fileBodySize++ }
            
            $fileBodySize += (8 + $dataChunkSize) # Header size + data payload size for 'data' chunk
            if ($dataChunkSize % 2 -ne 0) { $fileBodySize++ }
            
            $fileBodySize += $listInfoChunk.Length # The LIST chunk is already correctly padded
            
            $finalRiffSize = 4 + $fileBodySize # 4 bytes for the 'WAVE' ID

            $writer = New-Object System.IO.BinaryWriter([System.IO.File]::Create($OutputPath), $ascii)
            
            # 1. Write the main RIFF header
            $writer.Write($ascii.GetBytes('RIFF'))
            $writer.Write([uint32]$finalRiffSize)
            $writer.Write($ascii.GetBytes('WAVE'))

            # 2. Write the 'fmt ' chunk from memory
            $writer.Write($fmtChunkBytes)
            if ($fmtDataSize % 2 -ne 0) { $writer.Write([byte]0) }

            # 3. Write the 'data' chunk header, then stream its content from the source file
            Write-Verbose "Writing 'data' chunk via streaming..."
            $writer.Write($ascii.GetBytes('data'))
            $writer.Write([uint32]$dataChunkSize)
            
            $inputStream = [System.IO.File]::OpenRead($Path)
            $inputStream.Seek($dataChunkPosition, [System.IO.SeekOrigin]::Begin) | Out-Null
            
            $buffer = New-Object byte[](65536) # 64KB buffer for efficient copying
            $bytesRemaining = $dataChunkSize
            while ($bytesRemaining -gt 0) {
                $bytesToRead = [int][System.Math]::Min($bytesRemaining, $buffer.Length)
                $bytesRead = $inputStream.Read($buffer, 0, $bytesToRead)
                if ($bytesRead -eq 0) { break } # End of stream
                $writer.Write($buffer, 0, $bytesRead)
                $bytesRemaining -= $bytesRead
            }
            if ($dataChunkSize % 2 -ne 0) { $writer.Write([byte]0) }

            # 4. Write the new 'LIST INFO' metadata chunk at the end
            $writer.Write($listInfoChunk)

        }
        finally {
            if ($writer) { $writer.Close() }
            if ($inputStream) { $inputStream.Close() }
        }
    }
}


function Invoke-IntelligentAnalysis {
    param(
        [string]$Url
    )
    $arguments = @('-J', $Url)
    $filePath = (Get-Item -Path $script:ytDlpExe).FullName

    $argsAll = @()
    $argsAll += $script:YtDlpCommonSwitches
    $argsAll += (Get-CookiesArgs)
    $argsAll += $arguments
    $argString = ($argsAll | ForEach-Object { Quote-Arg $_ }) -join ' '
    
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = $filePath
    $processInfo.Arguments = $argString
    $processInfo.WorkingDirectory = $scriptFolder
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    $processInfo.RedirectStandardOutput = $true
    $processInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $processInfo.RedirectStandardError = $true
    $processInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo

    try {
        $process.Start() | Out-Null
        
        $stdOut = $process.StandardOutput.ReadToEnd()
        $stdErr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        
        # --- LOGGING SECTION ---
        # If logging is enabled, append the analysis data for the current URL to the session log file.
        if ($script:EnableLogging -and $script:SessionLogFile) {
            $debugContent = @"

#################################################################
#                       VIDEO URL: $($Url)
#################################################################

=================================================================
PART 1: INVOKE-INTELLIGENTANALYSIS (DATA FETCHING)
=================================================================
Command: $filePath $argString
Exit Code: $($process.ExitCode)

--- Standard Error (stderr) ---
$stdErr

--- Standard Output (stdout) from yt-dlp ---
$stdOut
"@
            # Use Add-Content to append to the log instead of overwriting it.
            $debugContent | Add-Content -Path $script:SessionLogFile -Encoding utf8
        }
        # --- END OF SECTION ---

        if ($process.ExitCode -eq 0 -and -not [string]::IsNullOrEmpty($stdOut)) {
            return $stdOut.Split([Environment]::NewLine)
        } else {
            return $null
        }
    }
    catch {
        return $null
    }
    finally {
        if ($process) { $process.Dispose() }
    }
}

function Find-BestFormats {
    param(
        [string]$Url,
        [psobject]$qualityObject,
        [bool]$preferMp4Only
    )

    $jsonResultStdOut = Invoke-IntelligentAnalysis -Url $Url
    if (-not $jsonResultStdOut) { return $null }

    # --- START OF LOGGING SECTION FOR THIS FUNCTION ---
    $logContent = @"

=================================================================
PART 2: FIND-BESTFORMATS (DECISION LOGIC)
=================================================================
"@
    # --- END OF SECTION ---

    try {
        $data = ($jsonResultStdOut -join "`n") | ConvertFrom-Json
    } catch {
        # Log the JSON conversion error
        $logContent += "ERROR: Failed to convert JSON from yt-dlp. Catched Exception.`n"
        if ($script:EnableLogging -and $script:SessionLogFile) {
            $logContent | Add-Content -Path $script:SessionLogFile -Encoding utf8
        }
        return $null
    }
    
    $allFormats = $data.formats
    $logContent += "`n--- STAGE 1: RAW FORMATS LIST (from received JSON) ---`n"
    $logContent += ($allFormats | Format-Table format_id, ext, height, width, vcodec, acodec, tbr, filesize, protocol -AutoSize | Out-String)

    $videoOnlyStreams = $allFormats | Where-Object { $_.vcodec -ne 'none' -and $_.acodec -eq 'none' }
    $audioOnlyStreams = $allFormats | Where-Object { $_.acodec -ne 'none' -and $_.vcodec -eq 'none' }
    $premergedStreams = $allFormats | Where-Object { $_.vcodec -ne 'none' -and $_.acodec -ne 'none' }
    
    $logContent += "`n--- STAGE 2: POST-CATEGORIZATION (PRE-HEIGHT FILTER) ---`n"
    $logContent += "[Video-Only Streams Found]:`n"
    $logContent += ($videoOnlyStreams | Format-Table format_id, ext, height, vcodec, tbr -AutoSize | Out-String)
    $logContent += "[Pre-merged Streams Found]:`n"
    $logContent += ($premergedStreams | Format-Table format_id, ext, height, vcodec, acodec, tbr -AutoSize | Out-String)
    
    if ($qualityObject.RequestedHeight -lt 9999) {
        $videoOnlyStreams = $videoOnlyStreams | Where-Object { [int]$_.height -le $qualityObject.RequestedHeight }
        $premergedStreams = $premergedStreams | Where-Object { [int]$_.height -le $qualityObject.RequestedHeight }
    }

    $logContent += "`n--- STAGE 3: POST-HEIGHT FILTER (<= $($qualityObject.RequestedHeight)p) ---`n"
    $logContent += "[Video-Only Streams Remaining]:`n"
    $logContent += ($videoOnlyStreams | Format-Table format_id, ext, height, vcodec, tbr -AutoSize | Out-String)
    $logContent += "[Pre-merged Streams Remaining]:`n"
    $logContent += ($premergedStreams | Format-Table format_id, ext, height, vcodec, acodec, tbr -AutoSize | Out-String)

    $bestSeparateVideo = $videoOnlyStreams | Sort-Object -Property height, tbr -Descending | Select-Object -First 1
    $bestPremergedVideo = $premergedStreams | Sort-Object -Property height, tbr -Descending | Select-Object -First 1

    $logContent += "`n--- STAGE 4: FINAL CANDIDATES CHOSEN ---`n"
    $logContent += "[Best Separate Candidate Chosen]:`n"
    $logContent += ($bestSeparateVideo | Format-List * | Out-String)
    $logContent += "[Best Pre-merged Candidate Chosen]:`n"
    $logContent += ($bestPremergedVideo | Format-List * | Out-String)

    # Write the entire log for this function to the file, if logging is enabled.
    if ($script:EnableLogging -and $script:SessionLogFile) {
        $logContent | Add-Content -Path $script:SessionLogFile -Encoding utf8
    }

    # --- START OF ENHANCED DECISION LOGIC ---
    # Prioritize separate streams (requiring a merge) if their quality is equal or better.
    if ($bestSeparateVideo -and ($null -eq $bestPremergedVideo -or $bestSeparateVideo.height -ge $bestPremergedVideo.height)) {
        # The separate stream is better or equal; prepare for merge.
        $finalExtension = if ($preferMp4Only) { 'mp4' } else { 'mkv' }
        $bestAudio = $null
        if ($preferMp4Only) {
            $bestAudio = $audioOnlyStreams | Where-Object { $_.acodec -eq 'opus' -or $_.ext -eq 'm4a' } | Sort-Object -Property height, abr -Descending | Select-Object -First 1
        } else {
            $bestAudio = $audioOnlyStreams | Sort-Object -Property height, @{E={@('opus').IndexOf($_.acodec)}}, abr -Descending | Select-Object -First 1
        }

        if ($bestAudio) {
            Write-Centered "Best format found (merge): Video $($bestSeparateVideo.height)p." "Green"
            return [pscustomobject]@{
                VideoFormatCode = $bestSeparateVideo.format_id
                AudioFormatCode = $bestAudio.format_id
                MergeContainer  = $finalExtension
                FinalHeight     = $bestSeparateVideo.height
            }
        }
    }
    # As a fallback, use the best pre-merged stream.
    elseif ($bestPremergedVideo) {
        Write-Centered "Best format found (pre-merged): Video $($bestPremergedVideo.height)p." "Green"
        return [pscustomobject]@{
            VideoFormatCode = $bestPremergedVideo.format_id
            AudioFormatCode = $null # No merge needed
            MergeContainer  = $bestPremergedVideo.ext
            FinalHeight     = $bestPremergedVideo.height
        }
    }
    
    # If everything failed, return null
    return $null
}


function Build-VideoDownloadCascade {
    param(
        [int]$MaxHeight,
        [string]$OutMp4,
        [string]$OutMkv
    )
    $heights = @(4320, 2880, 2160, 1440, 1080, 720, 480, 360, 240, 144)
    if ($MaxHeight -gt 0 -and $MaxHeight -lt 9999) { $heights = $heights | Where-Object { $_ -le $MaxHeight } }
    if (-not $heights) { $heights = @(1080, 720, 480) }

    $cascade = New-Object System.Collections.Generic.List[object]
    
    if ($script:PreferMp4Only) {
        # --- "MP4 ONLY" STRATEGY (UNIFIED HEAVY-FIRST) ---
        foreach ($h in $heights) {
            # Target 1: Maximum quality (AV1/VP9 + Opus), remuxed to MP4.
            $f_best_quality = "bv*[vcodec~='^av1|^vp9'][height=$h]+ba[acodec=opus]"
            $cascade.Add([pscustomobject]@{ Fmt=$f_best_quality; Out=$OutMp4; Merge='mp4'; QualityLabel="$h`p (Remux Max Quality -> MP4)" })

            # Target 2 (Fallback): Maximum compatibility (H.264 + AAC) in native MP4.
            $f_best_compat = "bv*[vcodec^=avc1][height=$h]+ba[ext=m4a]"
            $cascade.Add([pscustomobject]@{ Fmt=$f_best_compat; Out=$OutMp4; Merge='mp4'; QualityLabel="$h`p (MP4 Native/Compatibility)" })
        }
        $cascade.Add([pscustomobject]@{ Fmt='bestvideo[ext=mp4]+bestaudio[ext=m4a]/best'; Out=$OutMp4; Merge='mp4'; QualityLabel="Generic MP4 Fallback" })

    } else {
        # --- "MKV HEAVY-FIRST" STRATEGY ---
        foreach ($h in $heights) {
            # Priority 1: Maximum Quality (AV1/VP9 + Opus) in the MKV container.
            $f_mkv = "bv*[vcodec~='^av1|^vp9'][height=$h]+ba[acodec=opus]"
            $cascade.Add([pscustomobject]@{ Fmt=$f_mkv; Out=$OutMkv; Merge='mkv'; QualityLabel="$h`p (MKV/Max Quality)" })

            # Priority 2 (Fallback): Maximum Compatibility (H.264 + AAC) in MP4.
            $f_mp4 = "bv*[vcodec^=avc1][height=$h]+ba[ext=m4a]"
            $cascade.Add([pscustomobject]@{ Fmt=$f_mp4; Out=$OutMp4; Merge='mp4'; QualityLabel="$h`p (MP4/Compatibility)" })
        }
        $cascade.Add([pscustomobject]@{ Fmt='bestvideo+bestaudio/best'; Out=$OutMkv; Merge='mkv'; QualityLabel="Generic Fallback (MKV)" })
    }
    
    return $cascade
}

# --- Menus ---
function Show-InputModeMenu {
    $options=@(
        @{N="Paste a single video/playlist link";V="single"},
        @{N="Paste multiple video links";V="multiple"},
        @{N="Manage cookies";V="cookies"},
        @{N="Options";V="options"},
        @{N="Update Tools";V="update"},
        @{N="Update ARN-DL";V="selfupdate"},
        @{N="Exit";V="exit"}
    )
    $idx=0; while ($true) {
        
        Clear-Host
        Write-Centered ""

        $logoLines = @(
            '░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░',
            '░░▄█▀░█▀█░█▀▄░█▄░█░░░░░█▀▄░█░░░▀█▄░░',
            '░▄█▀░░█▀█░█▀▄░█░▀█░▀▀▀░█░█░█░░░░▄█▀░',
            '░░▀█▄░▀░▀░▀░▀░▀░░▀░░░░░▀▀▀░▀▀▀░▄█▀░░',
            '░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░'
        )


        $consoleWidth = $Host.UI.RawUI.WindowSize.Width
        foreach ($line in $logoLines) {
        $padding = [string]" " * (($consoleWidth - $line.Length) / 2)
        Write-Host "$padding$line" -ForegroundColor Green
        }; Write-Host ""; Write-MatrixBanner -Lines 4 -Context "Menu";
        Write-Host ""
        Write-Centered "--- Menu ---" "Yellow"
        Write-Host ""

        for ($i=0; $i -lt $options.Length; $i++) { $line= if ($i -eq $idx) { "-> $($options[$i].N)" } else { "   $($options[$i].N)" }; if ($i -eq $idx) { Write-Host (" " * (($Host.UI.RawUI.WindowSize.Width - $line.Length) / 2)) -NoNewline; Write-Host $line -ForegroundColor Black -BackgroundColor White } else { Write-Centered $line } }

        Write-Centered("`n[↑] and [↓] to navigate `| [Enter] or [Space] to select `| [Esc] to go back.") "Yellow"

        while ($true) { 
            $k=Wait-KeyNonBlocking; 
            $rer=$false; 
            switch ($k.Key) { 
                'UpArrow'   { if ($idx -gt 0){$idx--;$rer=$true} }; 
                'DownArrow' { if ($idx -lt $options.Length-1){$idx++;$rer=$true} }; 
                'Enter'     { return $options[$idx].V }
                'Spacebar'  { return $options[$idx].V } 
            } 
            if ($rer){break} 
        }
    }
}

function Show-OptionsMenu {
    # Defines the menu items, their state getters, and setters.
    $items = @(
        [pscustomobject]@{ Name = "Prefer .MP4 (No .MKV)";           Get = { $script:PreferMP4Only };      Set = { param($v) $script:PreferMP4Only = $v } },
        [pscustomobject]@{ Name = "---SEPARATOR---"; Get = { $null }; Set = { } },
        [pscustomobject]@{ Name = "Force MP4 re-encode if .MKV (Very Slow)";      Get = { $script:ForceReencodeMP4 };   Set = { param($v) $script:ForceReencodeMP4 = $v } },
        [pscustomobject]@{ Name = "---SEPARATOR---"; Get = { $null }; Set = { } },
        [pscustomobject]@{ Name = "Keep .MKV after MP4 re-encode";    Get = { $script:ReencodeKeepOriginal }; Set = { param($v) $script:ReencodeKeepOriginal = $v } },
        [pscustomobject]@{ Name = "---SEPARATOR---"; Get = { $null }; Set = { } },
        [pscustomobject]@{ Name = "Brute-Force (Very Slow)"; Get = { $script:ForceBruteForce };      Set = { param($v) $script:ForceBruteForce = $v } }
    )
    $idx = 0

    while ($true) {
        # Redraw the entire options menu for each interaction.
        Clear-Host
        Write-Centered ""
        $logoLines = @(
            '░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░',
            '░░▄█▀░█▀█░█▀▄░█▄░█░░░░░█▀▄░█░░░▀█▄░░',
            '░▄█▀░░█▀█░█▀▄░█░▀█░▀▀▀░█░█░█░░░░▄█▀░',
            '░░▀█▄░▀░▀░▀░▀░▀░░▀░░░░░▀▀▀░▀▀▀░▄█▀░░',
            '░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░'
        )
        $consoleWidth = $Host.UI.RawUI.WindowSize.Width
        foreach ($line in $logoLines) {
            $padding = [string]" " * (($consoleWidth - $line.Length) / 2)
            Write-Host "$padding$line" -ForegroundColor Green
        }
        Write-Centered ""
        Write-MatrixBanner -Lines 4 -Context "Menu"
        Write-Centered ""
        Write-Centered "--- Options ---" "Yellow"
        Write-Centered ""

        for ($i = 0; $i -lt $items.Length; $i++) {
            if ($items[$i].Name -eq "---SEPARATOR---") { Write-Host ""; continue }

            # This rule disables MKV-related options if 'Prefer .MP4' is active, or the 'Keep .MKV' option if re-encoding is disabled.
            $isDisabled = ($script:PreferMP4Only -and $i -in @(2, 4)) -or ((-not $script:ForceReencodeMP4) -and ($i -eq 4))
            $checked = if (& $items[$i].Get) { "X" } else { " " }
            $label = "[{0}] {1}" -f $checked, $items[$i].Name

            if ($i -eq $idx) {
                Write-Host (" " * (($Host.UI.RawUI.WindowSize.Width - $label.Length) / 2)) -NoNewline
                Write-Host ("-> " + $label) -ForegroundColor Black -BackgroundColor White
            } else {
                if ($isDisabled) { Write-Centered ("   " + $label) -ForegroundColor DarkGray } 
                else { Write-Centered ("   " + $label) }
            }
        }
        Write-Host ""

        # Display helpText for each options
        $helpText = ""
        switch ($idx) {
            0 { $helpText = @"
Prioritizes the .MP4 format for maximum compatibility.
While many high-quality videos are .MKV, .MP4 is more widely supported by devices like phones and TVs.
"@ }
            2 { $helpText = @"
Creates a high-quality .MP4 for users who prioritize audio/video fidelity.
Performs a slower, more intensive re-encode using high-bitrate AAC audio (320kbps, 48kHz).
"@ }
            4 { $helpText = "Keeps the original .MKV file after conversion." }
            6 { $helpText = @"
Bypasses smart analysis to try every possible format and client.
Warning: This method is extremely slow and should only be used as a last resort if other options fail.
"@ }
            default { $helpText = "Survolez une option pour voir sa description." }
        }
        Write-Centered "----------------------------------------------------------------" "DarkGray"
        Write-Centered $helpText "Gray"

        Write-Centered("`n[↑] and [↓] to navigate | [Enter] or [Space] to select | [Esc] to go back.") "Yellow"

        $action = $null
        while (-not $action) {
            $k = Wait-KeyNonBlocking
            switch ($k.Key) {
                'UpArrow'  { $action = 'up' }
                'DownArrow'{ $action = 'down' }
                'Enter'    { $action = 'select' }
                'Spacebar' { $action = 'select' }
                'Escape'   { return }
            }
        }

        # FINAL navigation and selection logic
        if ($action -eq 'up') {
            $previousIdx = $idx
            # Loop backwards to find the next valid item
            while ($true) {
                $previousIdx--
                if ($previousIdx -lt 0) { break } # Reached the top
                if ($items[$previousIdx].Name -ne "---SEPARATOR---") {
                    $isDisabled = ($script:PreferMP4Only -and $previousIdx -in @(2, 4)) -or ((-not $script:ForceReencodeMP4) -and ($previousIdx -eq 4))
                    if (-not $isDisabled) {
                        $idx = $previousIdx
                        break
                    }
                }
            }
        }
        elseif ($action -eq 'down') {
            $nextIdx = $idx
            # Loop forwards to find the next valid item
            while ($true) {
                $nextIdx++
                if ($nextIdx -ge $items.Length) { break } # Reached the bottom
                if ($items[$nextIdx].Name -ne "---SEPARATOR---") {
                    $isDisabled = ($script:PreferMP4Only -and $nextIdx -in @(2, 4)) -or ((-not $script:ForceReencodeMP4) -and ($nextIdx -eq 4))
                    if (-not $isDisabled) {
                        $idx = $nextIdx
                        break
                    }
                }
            }
        }
        elseif ($action -eq 'select') {
            $isSelectionDisabled = ($script:PreferMP4Only -and $idx -in @(2, 4)) -or ((-not $script:ForceReencodeMP4) -and ($idx -eq 4))
            if (-not $isSelectionDisabled) {
                $cur = & $items[$idx].Get
                & $items[$idx].Set -v (-not $cur)
            }
        }
    }
}

function Show-FormatMenu {
    $options=@(@{N="Video";V="video"},@{N="Audio Only";V="audio"},@{N="VIDEO + SEPARATE AUDIO";V="video_plus_audio"},@{N="Back to main menu";V="back"})
    $idx=0; while ($true) {
        Clear-Host
        Write-Centered ""

        $logoLines = @(
            '░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░',
            '░░▄█▀░█▀█░█▀▄░█▄░█░░░░░█▀▄░█░░░▀█▄░░',
            '░▄█▀░░█▀█░█▀▄░█░▀█░▀▀▀░█░█░█░░░░▄█▀░',
            '░░▀█▄░▀░▀░▀░▀░▀░░▀░░░░░▀▀▀░▀▀▀░▄█▀░░',
            '░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░'
        )

        $consoleWidth = $Host.UI.RawUI.WindowSize.Width
        foreach ($line in $logoLines) {
            $padding = [string]" " * (($consoleWidth - $line.Length) / 2)
            Write-Host "$padding$line" -ForegroundColor Green
        }

        ; Write-Centered ""; Write-MatrixBanner -Lines 4 -Context "Menu"; Write-Centered ""; Write-Centered "--- Select Output Format ---" "Yellow"; Write-Centered ""
        for ($i=0; $i -lt $options.Length; $i++) { $line= if ($i -eq $idx) { "-> $($options[$i].N)" } else { "   $($options[$i].N)" }; if ($i -eq $idx) { Write-Host (" " * (($Host.UI.RawUI.WindowSize.Width - $line.Length) / 2)) -NoNewline; Write-Host $line -ForegroundColor Black -BackgroundColor White } else { Write-Centered $line } }

        Write-Centered("`n[↑] and [↓] to navigate `| [Enter] or [Space] to select `| [Esc] to go back.") "Yellow"

while ($true) { 
    $k=Wait-KeyNonBlocking
    $rer=$false
    switch ($k.Key) { 
        'UpArrow'   { if ($idx -gt 0){$idx--;$rer=$true} }
        'DownArrow' { if ($idx -lt $options.Length-1){$idx++;$rer=$true} }
        'Enter'     { return $options[$idx].V }
        'Spacebar'  { return $options[$idx].V }
        'Escape'    { return 'back' } 
    } 
    if ($rer){break} 
}
    }
}

function Show-QualityMenu {
    param($Mode="both")
    $videoOptions=@(@{N="Ultra (4k, 8k...)";H=9999},@{N="High (Max 1080p)";H=1080},@{N="Medium (Max 720p)";H=720},@{N="Low (Max 480p)";H=480})
    $audioOptions=@(
    @{N="Audio .WAV"; T="wav"},
    @{N="Audio .MP3 (320kbps)"; T="mp3"}
    )
    $vi=0;$ai=0;$stage= if ($Mode -eq "audio") {"audio"} else {"video"}
    while ($true) {
        Clear-Host
        
        Write-Centered ""
        $logoLines = @(
            '░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░',
            '░░▄█▀░█▀█░█▀▄░█▄░█░░░░░█▀▄░█░░░▀█▄░░',
            '░▄█▀░░█▀█░█▀▄░█░▀█░▀▀▀░█░█░█░░░░▄█▀░',
            '░░▀█▄░▀░▀░▀░▀░▀░░▀░░░░░▀▀▀░▀▀▀░▄█▀░░',
            '░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░'
        )
        $consoleWidth = $Host.UI.RawUI.WindowSize.Width
        foreach ($line in $logoLines) {
            $padding = [string]" " * (($consoleWidth - $line.Length) / 2)
            Write-Host "$padding$line" -ForegroundColor Green
        }
        Write-Host ""
        Write-MatrixBanner -Lines 4 -Context "Menu"
        Write-Host ""

        if ($stage -eq "video") {
            Write-Centered "--- Select VIDEO Quality ---" "Yellow"
            Write-Host ""
            for ($i=0; $i -lt $videoOptions.Length; $i++){ $line= if ($i -eq $vi) { "-> $($videoOptions[$i].N)" } else { "   $($videoOptions[$i].N)" }; if ($i -eq $vi) { Write-Host (" " * (($Host.UI.RawUI.WindowSize.Width - $line.Length) / 2)) -NoNewline; Write-Host $line -ForegroundColor Black -BackgroundColor White } else { Write-Centered $line } }
        } else {
            Write-Centered "--- Select AUDIO Quality ---" "Yellow"
            Write-Host ""
            for ($i=0; $i -lt $audioOptions.Length; $i++){ $line= if ($i -eq $ai) { "-> $($audioOptions[$i].N)" } else { "   $($audioOptions[$i].N)" }; if ($i -eq $ai) { Write-Host (" " * (($Host.UI.RawUI.WindowSize.Width - $line.Length) / 2)) -NoNewline; Write-Host $line -ForegroundColor Black -BackgroundColor White } else { Write-Centered $line } }
        }
        

        Write-Centered("`n[↑] and [↓] to navigate `| [Enter] or [Space] to select `| [Esc] to go back.") "Yellow"

        while ($true) {
            $k=Wait-KeyNonBlocking; $rer=$false
            switch ($k.Key) {
                'UpArrow'   { if ($stage -eq "video") { if ($vi -gt 0){$vi--;$rer=$true} } else { if ($ai -gt 0){$ai--;$rer=$true} } }
                'DownArrow' { if ($stage -eq "video") { if ($vi -lt $videoOptions.Length-1){$vi++;$rer=$true} } else { if ($ai -lt $audioOptions.Length-1){$ai++;$rer=$true} } }
                'LeftArrow' { if ($stage -eq "audio") { $stage="video"; $rer=$true } }
                'RightArrow'{ if ($stage -eq "video" -and $Mode -eq "both") { $stage="audio"; $rer=$true } }
                'Enter'     { if ($stage -eq "video") { if ($Mode -eq "both") { $stage="audio"; $rer=$true } else { $ai = switch ($vi) { 0 {0} 1 {0} 2 {0} Default {2} }; return @{ RequestedHeight=$videoOptions[$vi].H; AudioQualityTag=$audioOptions[$ai].T } } } else { return @{ RequestedHeight=$videoOptions[$vi].H; AudioQualityTag=$audioOptions[$ai].T } } }
                # <-- ACTION 3: Enable [Spacebar] key
                'Spacebar'  { if ($stage -eq "video") { if ($Mode -eq "both") { $stage="audio"; $rer=$true } else { $ai = switch ($vi) { 0 {0} 1 {0} 2 {0} Default {2} }; return @{ RequestedHeight=$videoOptions[$vi].H; AudioQualityTag=$audioOptions[$ai].T } } } else { return @{ RequestedHeight=$videoOptions[$vi].H; AudioQualityTag=$audioOptions[$ai].T } } }
                'Escape'    { return $null }
            }
            if ($rer){break}
        }
    }
}

function Show-PlaylistSelectionMenu {
    param([array]$AllVideos)
    $page=0;$sel=0; $selIdx=[System.Collections.Generic.List[int]]::new()
    while ($true) {
        Clear-Host
        Write-Centered ""
        
        $logoLines = @(
            '░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░',
            '░░▄█▀░█▀█░█▀▄░█▄░█░░░░░█▀▄░█░░░▀█▄░░',
            '░▄█▀░░█▀█░█▀▄░█░▀█░▀▀▀░█░█░█░░░░▄█▀░',
            '░░▀█▄░▀░▀░▀░▀░▀░░▀░░░░░▀▀▀░▀▀▀░▄█▀░░',
            '░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░'
        )
        $consoleWidth = $Host.UI.RawUI.WindowSize.Width
        foreach ($line in $logoLines) {
            $padding = [string]" " * (($consoleWidth - $line.Length) / 2)
            Write-Host "$padding$line" -ForegroundColor Green
        }

        Write-Centered ""
        Write-MatrixBanner -Lines 4 -Context "Menu" 
        Write-Centered ""

        Write-Centered "--- Select to Download ---" "Yellow"
        Write-Centered ""
        $pageSize=20; $total=[Math]::Ceiling($AllVideos.Length / $pageSize); Write-Centered "Page $($page+1) / $total | $($AllVideos.Length) videos total."
        $start=$page*$pageSize; $videos=$AllVideos | Select-Object -Skip $start -First $pageSize
        for ($i=0; $i -lt $videos.Length; $i++){ $g=$start+$i; $v=$AllVideos[$g]; $prefix= if ($selIdx.Contains($g)) {"[x]"} else {"[ ]"}; $title= if ($v.title.Length -gt 80) { $v.title.Substring(0,77)+'...' } else { $v.title }; $line="$prefix $title"
            if ($i -eq $sel) { Write-Host (" " * (($Host.UI.RawUI.WindowSize.Width - $line.Length) / 2)) -NoNewline; Write-Host $line -ForegroundColor Black -BackgroundColor White } else { Write-Centered "   $line" } }


        Write-Centered("`n[↑][↓] and [←][→] to navigate `| [Enter] or [Space] to select `| [A] select all") "Yellow"
        Write-Centered("`n[V] validate and start download `| [Esc] to go back.") "Yellow"
        Write-Centered ""

        while ($true) {
            $k=Wait-KeyNonBlocking; $rer=$false
            switch ($k.Key) {
                'UpArrow'   { if ($sel -gt 0) { $sel--; $rer = $true } }
                'DownArrow' { if ($sel -lt $videos.Length - 1) { $sel++; $rer = $true } }
                'LeftArrow' { if ($page -gt 0) { $page--; $sel = 0; $rer = $true } }
                'RightArrow'{ if ($page -lt ($total - 1)) { $page++; $sel = 0; $rer = $true } }
                'Enter'     { $g=$start+$sel; if ($selIdx.Contains($g)) { [void]$selIdx.Remove($g) } else { $selIdx.Add($g) }; $rer=$true }
                'Spacebar'  { $g=$start+$sel; if ($selIdx.Contains($g)) { [void]$selIdx.Remove($g) } else { $selIdx.Add($g) }; $rer=$true }
                'A'         { if ($selIdx.Count -eq $AllVideos.Length) { $selIdx.Clear() } else { $selIdx.Clear(); for($i=0;$i -lt $AllVideos.Length;$i++){ $selIdx.Add($i) } }; $rer=$true }
                'V'         { if ($selIdx.Count -gt 0) { return $selIdx | ForEach-Object { $AllVideos[$_] } } else { Write-Centered "No videos selected." "Red"; Start-Sleep -Seconds 1; $rer = $true } }
                'Escape'    { return $null }
            }
            if ($rer) { break }
        }
    }
}





# --- Auth/cookies (file ready to be edited) ---
# Automatic creation of cookies.txt (Netscape format) + auto-injection of cookies for yt-dlp
# This way, you can paste your cookies to bypass blocks.
# The file is created next to the script if it is missing.
# ----------------------------------------------------------------
# NOTE: if you don't want cookies, leave the file empty.
# ----------------------------------------------------------------


# ================== SCRIPT EXECUTION START ================== 
$OutputEncoding = [System.Text.Encoding]::UTF8
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) { Start-Process powershell.exe -ArgumentList "-NoProfile -File `"$PSCommandPath`"" -Verb RunAs; exit }



# --> yt-dlp will only use cookies if the file is larger than 32 bytes (i.e., not empty).
# cookies file (Netscape format) to bypass anti-bot checks (admin-friendly)
$script:CookiesFile = Join-Path $scriptFolder "cookies.txt"
if (!(Test-Path -LiteralPath $script:CookiesFile)) {
    $Utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    $CookieHeaderText = @'
# Netscape HTTP Cookie File
# Do not delete the first line (# Netscape HTTP Cookie File) it is required for yt-dlp to recognize the file.
#
# --- Using Cookies (often mandatory) ---
# This file allows yt-dlp to use cookies from your browser, it helps make downloads more reliable by bypassing anti-bot checks.
# It's also required for specific cases (e.g., logging in for private content, passing age-gates, accepting cookie banners).
#
# --- A Note on Account Safety ---
# While yt-dlp is widely used, please be aware that automating downloads with a personal account is technically against the Terms of Service of most platforms.
# Although the risk is generally very low for moderate usage, there is always a small possibility of action being taken against the account (e.g., a temporary warning).
# For maximum safety, especially if you plan to download large quantities of content, consider using a secondary or "throwaway" account.
#
# --- How to Get Your Cookies ---
# 1. Open a new Private/Incognito browser window.
# 2. Visit the site you wish to download from. (If the content requires an account, log in before exporting cookies).
# 3. Use a browser extension to export your cookies in the Netscape format.
#    A popular and reliable choice is "Get cookies.txt LOCALLY".
#    -> NOTE: Allow this extension to run in private/incognito in your browser's extension settings.
# 4. Paste the entire content of the exported file below this header.
# 5. Close the private browser window to ensure the session is terminated.
#
# If you downloaded without filling in the cookies.txt it often doesn't work, it will automatically be populated with generic visitor cookies:
#   - Delete the cookies.txt file from the 'data_Inside' folder.
#   - Restart the script and select 'Manage cookies' to open cookies.txt and past cookies from your Web browser
#
# ---  Example of the first few lines (for illustration only, do not use these) ---
# .youtube.com	TRUE	/	TRUE	1765968483	__Secure-3PSIDTS	sidts-P856YB5TD3P_cmFn23qKz-b42y_AlgokW1kjkk:KARN/q0618JZ4xAA
# .youtube.com	TRUE	/	TRUE	8442531321	__Secure-ROLLOUT_TOKEN	Cjfyf;fOE-u:ARN!RNA#ARN.JGgfszJKjjly-Jyfz%kj
#
# ------------------------------------------------------------------
# PASTE YOUR COOKIES BELOW THIS LINE
# ------------------------------------------------------------------
'@
    [System.IO.File]::WriteAllText($script:CookiesFile, $CookieHeaderText, $Utf8WithoutBom)
}

function Get-CookiesArgs {
    try { if ((Test-Path -LiteralPath $script:CookiesFile) -and ((Get-Item $script:CookiesFile).Length -gt 32)) { return @('--cookies', $script:CookiesFile) } } catch {}
    return @()
}

$ytDlpExe = Join-Path $scriptFolder "yt-dlp.exe"; $ffprobeExe = Join-Path $scriptFolder "ffprobe.exe"; $ffmpegExe = Join-Path $scriptFolder "ffmpeg.exe"
$parentFolder = (Get-Item $scriptFolder).Parent.FullName; $downloadRootFolder = Join-Path $parentFolder "Downloads"
New-Item -Path $downloadRootFolder -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
$env:PATH = "$scriptFolder;" + $env:PATH
if (-not (Get-Command ffmpeg.exe -ErrorAction SilentlyContinue)) { Write-Centered "FATAL ERROR: ffmpeg.exe could not be found." "Red"; Read-Host "Press Enter to exit."; exit }

# Anti-wrap: buffer width
try { $raw=$Host.UI.RawUI; $desiredWidth=200; if ($raw.BufferSize.Width -lt $desiredWidth){ $buf=$raw.BufferSize; $buf.Width=$desiredWidth; $raw.BufferSize=$buf } } catch {}



# ================== STARTUP SEQUENCE ==================

Clear-Host


# <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< STARTING HELIX ANIMATION >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
Show-HelixAnimation -Text "ARN" -DurationSeconds 0.618033988749895 -ColorDNA1 "Green" -ColorDNA2 "Gray"
# <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< END OF HELIX ANIMATION >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>


Show-LogoAnimation -Repetitions 2 -LogoForegroundColor Gray -ScreenBackgroundColor Green

Initialize-AudioPlusDoubleWav
Start-MenuMusic

# ==========================================================================

<#
.SYNOPSIS
    Manages the entire download and processing workflow for a list of URLs.
.DESCRIPTION
    This function takes a list of video URLs, a chosen format, and quality settings.
    It handles URL resolution, playlist management, and orchestrates the download 
    process for video and/or audio. It incorporates a robust, two-stage fallback 
    system for both video and audio downloads to maximize success rates.
    It also manages post-processing tasks like re-encoding and generates a final report.
.PARAMETER urlsToProcess
    An array of strings, where each string is a video or playlist URL to be processed.
.PARAMETER formatChoice
    A string indicating the desired output: 'video', 'audio', or 'video_plus_audio'.
.PARAMETER qualityObject
    A custom object containing the desired quality settings, such as 'RequestedHeight'.
#>
function Download-Flow {
    param($urlsToProcess, $formatChoice, $qualityObject)
    $downloadReport = @()
    foreach ($url in $urlsToProcess) {
        Start-MenuMusic
        Clear-Host
        Write-Centered ""        
        $logoLines = @(
            '░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░',
            '░░▄█▀░█▀█░█▀▄░█▄░█░░░░░█▀▄░█░░░▀█▄░░',
            '░▄█▀░░█▀█░█▀▄░█░▀█░▀▀▀░█░█░█░░░░▄█▀░',
            '░░▀█▄░▀░▀░▀░▀░▀░░▀░░░░░▀▀▀░▀▀▀░▄█▀░░',
            '░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░'
        )
        $consoleWidth = $Host.UI.RawUI.WindowSize.Width
        foreach ($line in $logoLines) {
            $padding = [string]" " * (($consoleWidth - $line.Length) / 2)
            Write-Host "$padding$line" -ForegroundColor Green
        }
        Write-Host ""
        Write-MatrixBanner -Lines 4 -Context "Analysis"
        Write-Host ""
        Write-Centered "🔎 Analyzing URL: $url" "Cyan";
        Write-Host ""

        $allVideosInPlaylist = Resolve-URLVideoEntries -Url $url
        if ($allVideosInPlaylist.Count -eq 0) { Write-Centered "No valid video data found for this URL." "Red"; Start-Sleep -Seconds 2; continue }

        $videosToDownload = if ($allVideosInPlaylist.Length -gt 1) { Show-PlaylistSelectionMenu -AllVideos $allVideosInPlaylist } else { $allVideosInPlaylist }
        if (-not $videosToDownload) { Write-Centered "No videos selected. Skipping." "Green"; Start-Sleep -Seconds 2; continue }

        $isPlaylist = $videosToDownload.Length -gt 1 -or $allVideosInPlaylist[0].playlist_title
        $mainDestinationFolder = $downloadRootFolder
        if ($isPlaylist) {
            $playlistTitle = $allVideosInPlaylist[0].playlist_title;
            if ([string]::IsNullOrEmpty($playlistTitle)) { $playlistTitle = "Playlist_" + (Get-Date -Format "yyyy-MM-dd_HH-mm-ss") }
            $sanitizedPlaylistTitle = $playlistTitle -replace '[^\w\s\.,\-_''()[\]]','_';
            if ($sanitizedPlaylistTitle.Length -gt 100) { $sanitizedPlaylistTitle = $sanitizedPlaylistTitle.Substring(0,100).TrimEnd() }
            $mainDestinationFolder = Join-Path $downloadRootFolder $sanitizedPlaylistTitle
        }
        New-Item -Path $mainDestinationFolder -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        
        Write-Centered ""
        Write-Centered "--- [↑] Starting Cloud Connexion [↓] ---" -ForegroundColor "Gray" -BackgroundColor "DarkBlue"
        Start-DownloadMusic
        Write-Centered ""
        Write-Centered (" 🔊 Dave Eddy - Risen (TempleOS Hymn Remix) `| In Honor Of Terry A. Davis ") "Green"

        foreach ($video in $videosToDownload) {
         
           if ([string]::IsNullOrWhiteSpace($video.title)) { continue }

            Write-Centered ""
            Write-Centered " ----------------- 🎬 $($video.title) ----------------- " -ForegroundColor "Gray"
            Write-Centered ""
            Write-MatrixBanner -Lines 4 -Context "Download"
            Write-Centered ""

            $titleSan = $video.title.Normalize("FormD") -replace '\p{M}','' -replace '[^\u0000-\u007F]+','' -replace '[\\/:"*?<>|]','_' -replace '\s+',' '
            if ($titleSan.Length -gt 100) { $titleSan = $titleSan.Substring(0,100).TrimEnd() }
            $destFolder = if ($isPlaylist) { $mainDestinationFolder } else { $downloadRootFolder }

            # ================== VIDEO (and VIDEO+WAV: video first) ==================
            if ($formatChoice -in @('video', 'video_plus_audio')) {
                $finalMp4 = Join-Path $destFolder "$titleSan.mp4"
                $finalMkv = Join-Path $destFolder "$titleSan.mkv"

                if ((Test-Path -LiteralPath $finalMp4) -or (Test-Path -LiteralPath $finalMkv)) {
                    $msg = if (Test-Path -LiteralPath $finalMkv) { "MKV already exists (Skipped)." } else { "MP4 already exists (Skipped)." }
                    $downloadReport += [PSCustomObject]@{ T=$titleSan; S="Success"; D=$msg }
                } else {
                    # --- Brute-Force Path ---
                    if ($script:ForceBruteForce) {
                        Write-Centered "Brute-Force Enabled (Very Slow)" "Yellow"
                        try {
                            $cascade = Build-VideoDownloadCascade -MaxHeight $qualityObject.RequestedHeight -OutMp4 $finalMp4 -OutMkv $finalMkv
                            $ok = $false
                            foreach ($att in $cascade) {
                                foreach ($c in (Get-ClientList -Kind 'merge')) {
                                    Write-Centered "Trying: $($att.QualityLabel) | Client: $(if($c){$c}else{'default'})" "Gray"
                                    if (Invoke-YTDLPVideoAttempt -Fmt $att.Fmt -Out $att.Out -Url $video.webpage_url -Client $c -MergeContainer $att.Merge) { $ok = $true; break }
                                }
                                if ($ok) { break }
                            }
                         
                            # NEW: Two-Stage Fallback for Brute-Force
                            if (-not $ok) {
                                $fallbackFormat = "bestvideo+bestaudio/best"
                                if ($script:PreferMp4Only) {
                                    Write-Centered "Brute-force cascade failed. Attempting MP4 fallback..." "Yellow"
                                    if (Invoke-YTDLPVideoAttempt -Fmt $fallbackFormat -Out $finalMp4 -Url $video.webpage_url -MergeContainer 'mp4') { $ok = $true }
                                    if (-not $ok) {
                                        Write-Centered "MP4 fallback failed. Attempting MKV last resort fallback..." "DarkYellow"
                                        if (Invoke-YTDLPVideoAttempt -Fmt $fallbackFormat -Out $finalMkv -Url $video.webpage_url -MergeContainer 'mkv') { $ok = $true }
                                    }
                                } else {
                                    Write-Centered "Brute-force cascade failed. Attempting MKV fallback..." "Yellow"
                                    if (Invoke-YTDLPVideoAttempt -Fmt $fallbackFormat -Out $finalMkv -Url $video.webpage_url -MergeContainer 'mkv') { $ok = $true }
                                    if (-not $ok) {
                                        Write-Centered "MKV fallback failed. Attempting MP4 last resort fallback..." "DarkYellow"
                                        if (Invoke-YTDLPVideoAttempt -Fmt $fallbackFormat -Out $finalMp4 -Url $video.webpage_url -MergeContainer 'mp4') { $ok = $true }
                                    }
                                }
                            }

                            $finalOutFile = if (Test-Path -LiteralPath $finalMp4) { $finalMp4 } elseif (Test-Path -LiteralPath $finalMkv) { $finalMkv } else { $null }
                            if (-not $ok -or -not $finalOutFile) {
                                $downloadReport += [PSCustomObject]@{ T=$titleSan; S="Failure"; D="Video download failed (all attempts exhausted)." }
                            } else {
                                # Post-download processing for Brute-Force
                                if ($finalOutFile.ToLower().EndsWith('.mkv') -and $script:ForceReencodeMP4) {
                                    if (Reencode-MKV-To-MP4 -InFile $finalOutFile -OutMp4 $finalMp4) {
                                        if (-not $script:ReencodeKeepOriginal) { try { Remove-Item -LiteralPath $finalOutFile -ErrorAction SilentlyContinue } catch {} }
                                        $finalOutFile = $finalMp4
                                    }
                                } elseif ($finalOutFile.ToLower().EndsWith('.mkv') -and $script:PreferMp4Only) {
                                    Write-Centered "Performing fast remux from MKV to MP4..." "Gray"
                                    $remuxArgs = @("-i", $finalOutFile, "-map", "0:v:0?", "-map", "0:a:0?", "-c", "copy", "-movflags", "+faststart", $finalMp4, "-y", "-hide_banner", "-loglevel", "error")
                                    [void](Invoke-ExternalAnimated -FilePath $ffmpegExe -Arguments $remuxArgs -CaptureOutput)
                                    if (Test-Path -LiteralPath $finalMp4) {
                                        if (-not $script:ReencodeKeepOriginal) { try { Remove-Item -LiteralPath $finalOutFile -ErrorAction SilentlyContinue } catch {} }
                                        $finalOutFile = $finalMp4
                                    } else {
                                        Write-Centered "Fast Remux failed (codecs likely incompatible). The .MKV file has been kept." "Yellow"
                                    }
                                }

                                if ($finalOutFile) { $actualH = (& $ffprobeExe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 $finalOutFile) }
                                $downloadReport += [PSCustomObject]@{ T=$titleSan; S="Success"; D= if ($finalOutFile -and $actualH) { "Video OK ($($actualH)p)" } else { "Video OK" } }
                            }
                        } catch { $downloadReport += [PSCustomObject]@{ T=$titleSan; S="Failure"; D="Video download error: $($_.Exception.Message)" } }
                    } else {
                        # --- Smart Analysis Path ---
                        Write-Centered "Smart analysis in progress... Please wait a moment" "Yellow"
                        
                        $downloadSuccess = $false
                        $bestFormat = Find-BestFormats -Url $video.webpage_url -qualityObject $qualityObject -preferMp4Only $script:PreferMp4Only
                        
                        # Attempt 1: Smart selection from Find-BestFormats
                        if ($bestFormat) {
                            $formatString = if ($bestFormat.AudioFormatCode) { "$($bestFormat.VideoFormatCode)+$($bestFormat.AudioFormatCode)" } else { $bestFormat.VideoFormatCode }
                            $outputPath = if ($bestFormat.MergeContainer -eq 'mp4') { $finalMp4 } else { $finalMkv }

                            if (Invoke-YTDLPVideoAttempt -Fmt $formatString -Out $outputPath -Url $video.webpage_url -MergeContainer $bestFormat.MergeContainer) {
                                $downloadReport += [PSCustomObject]@{ T=$titleSan; S="Success"; D="Video OK ($($bestFormat.FinalHeight)p)" }
                                $downloadSuccess = $true
                            }
                        }
                        
                        # START: Multi-Stage Fallback Logic
                        if (-not $downloadSuccess) {
                            $fallbackFormat = "bestvideo+bestaudio/best"
                            if ($script:PreferMp4Only) {
                                # Scenario: "Prefer MP4" is ON
                                Write-Centered "Smart selection failed. Attempting MP4 fallback..." "Yellow"
                                if (Invoke-YTDLPVideoAttempt -Fmt $fallbackFormat -Out $finalMp4 -Url $video.webpage_url -MergeContainer 'mp4') { $downloadSuccess = $true }
                                if (-not $downloadSuccess) {
                                    Write-Centered "MP4 fallback failed. Attempting MKV last resort fallback..." "DarkYellow"
                                    if (Invoke-YTDLPVideoAttempt -Fmt $fallbackFormat -Out $finalMkv -Url $video.webpage_url -MergeContainer 'mkv') { $downloadSuccess = $true }
                                }
                            } else {
                                # Scenario: "Prefer MP4" is OFF
                                Write-Centered "Smart selection failed. Attempting MKV fallback..." "Yellow"
                                if (Invoke-YTDLPVideoAttempt -Fmt $fallbackFormat -Out $finalMkv -Url $video.webpage_url -MergeContainer 'mkv') { $downloadSuccess = $true }
                                if (-not $downloadSuccess) {
                                    Write-Centered "MKV fallback failed. Attempting MP4 last resort fallback..." "DarkYellow"
                                    if (Invoke-YTDLPVideoAttempt -Fmt $fallbackFormat -Out $finalMp4 -Url $video.webpage_url -MergeContainer 'mp4') { $downloadSuccess = $true }
                                }
                            }
                            if ($downloadSuccess) {
                                $finalOutFile = if (Test-Path -LiteralPath $finalMp4) { $finalMp4 } elseif (Test-Path -LiteralPath $finalMkv) { $finalMkv } else { $null }
                                $actualH = "N/A"
                                try { $actualH = (& $ffprobeExe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 $finalOutFile) } catch {}
                                $downloadReport += [PSCustomObject]@{ T=$titleSan; S="Success"; D="Video OK (Fallback, $($actualH)p)" }
                            }
                        }
                        # END: Multi-Stage Fallback Logic

                        if (-not $downloadSuccess) {
                            $downloadReport += [PSCustomObject]@{ T=$titleSan; S="Failure"; D="All download attempts failed." }
                        }
                        
                        # START: Post-Download Processing Logic
                        if ((Test-Path -LiteralPath $finalMkv) -and $script:ForceReencodeMP4) {
                            if (Reencode-MKV-To-MP4 -InFile $finalMkv -OutMp4 $finalMp4) {
                                if (-not $script:ReencodeKeepOriginal) { try { Remove-Item -LiteralPath $finalMkv -ErrorAction SilentlyContinue } catch {} }
                            }
                        } elseif ((Test-Path -LiteralPath $finalMkv) -and $script:PreferMp4Only) {
                            Write-Centered "Performing fast remux from MKV to MP4..." "Gray"
                            $remuxArgs = @("-i", $finalMkv, "-map", "0:v:0?", "-map", "0:a:0?", "-c", "copy", "-movflags", "+faststart", $finalMp4, "-y", "-hide_banner", "-loglevel", "error")
                            [void](Invoke-ExternalAnimated -FilePath $ffmpegExe -Arguments $remuxArgs -CaptureOutput)
                            if (Test-Path -LiteralPath $finalMp4) {
                                if (-not $script:ReencodeKeepOriginal) { try { Remove-Item -LiteralPath $finalMkv -ErrorAction SilentlyContinue } catch {} }
                            } else {
                                Write-Centered "Fast Remux failed (codecs likely incompatible). The .MKV file has been kept." "Yellow"
                            }
                        }
                        # END: Post-Download Processing Logic
                    }
                }
            }

            # ================== AUDIO (.WAV or .MP3) ==================
            if ($formatChoice -in @('audio', 'video_plus_audio')) {
                # Determine the target audio format and file path from the quality menu's choice
                $audioFormat = $qualityObject.AudioQualityTag
                $finalAudioFile = if ($audioFormat -eq 'wav') { 
                                      Join-Path $destFolder "$titleSan.wav" 
                                  } else { 
                                      Join-Path $destFolder "$titleSan.mp3" 
                                  }

                # If the audio file already exists, skip
                if (Test-Path -LiteralPath $finalAudioFile) {
                    $reportMsg = if ($audioFormat -eq 'wav') { "WAV" } else { "MP3" }
                    # For video_plus_audio, append to the existing report. For audio only, create a new report entry.
                    if ($formatChoice -eq 'video_plus_audio') {
                        $ex = $downloadReport | Where-Object { $_.T -eq $titleSan };
                        if ($ex) { $ex.D += " +$($reportMsg) already exists." }
                    } else {
                        $downloadReport += [PSCustomObject]@{ T=$titleSan; S="Success"; D="$($reportMsg) already exists (Skipped)." }
                    }
                } else {
                    $audioDownloaded = $false
                    try {
                        # This part is only for dedicated downloads (not extraction)
                        if ($formatChoice -eq 'audio') { Write-Centered "Initiating audio download for .$($audioFormat) creation..." "Cyan" }
                        
                        # --- ATTEMPT #1: Main method - Iterate through clients (Optimized for YouTube) ---
                        foreach ($c in (Get-ClientList -Kind 'merge')) {
                            if (Invoke-YTDLPAudioAttempt -Fmt (Get-AudioFormatExpression) -OutFile $finalAudioFile -Url $video.webpage_url -Client $c -AudioFormat $audioFormat) { $audioDownloaded = $true; break }
                        }

                        # --- FALLBACK #1: High-Quality Opus Codec (will be converted to WAV or MP3) ---
                        if (-not $audioDownloaded) {
                            Write-Centered "Audio download failed. Attempting high-quality Opus fallback..." "Yellow"
                            if (Invoke-YTDLPAudioAttempt -Fmt 'bestaudio[acodec*=opus]' -OutFile $finalAudioFile -Url $video.webpage_url -Client $null -AudioFormat $audioFormat) { $audioDownloaded = $true }
                        }

                        # --- FALLBACK #2: Most compatible audio as a last resort ---
                        if (-not $audioDownloaded) {
                            Write-Centered "Opus fallback failed. Attempting most compatible audio fallback..." "DarkYellow"
                            if (Invoke-YTDLPAudioAttempt -Fmt 'bestaudio' -OutFile $finalAudioFile -Url $video.webpage_url -Client $null -AudioFormat $audioFormat) { $audioDownloaded = $true }
                        }

                        # --- FINAL CHECK: See if any of the dedicated download attempts succeeded ---
                        if ($audioDownloaded) {
                            # SAFETY CHECK: Only run WAV-specific functions on WAV files
                            if ($audioFormat -eq 'wav') {
                                try { [void](Ensure-WavFormat -WavPath $finalAudioFile) } catch {}
                            }
                            $reportMsg = if ($audioFormat -eq 'wav') { "+WAV OK." } else { "+MP3 OK." }
                            if ($formatChoice -eq 'audio') { $reportMsg = ($reportMsg -replace '\+','') }
                            
                            $ex = $downloadReport | Where-Object { $_.T -eq $titleSan };
                            if ($ex) { $ex.D += " $reportMsg" }
                            else { $downloadReport += [PSCustomObject]@{ T=$titleSan; S="Success"; D=($reportMsg.Trim()) } }

                        } else {
                            # --- FALLBACK #3: Based on an already downloaded video (for video_plus_audio mode) ---
                            if ($formatChoice -eq 'video_plus_audio') {
                                Write-Centered "Dedicated audio download failed. Attempting extraction from video file..." "DarkCyan"
                                
                                $videoFile = $null
                                if (Test-Path -LiteralPath (Join-Path $destFolder "$titleSan.mp4")) {
                                    $videoFile = Join-Path $destFolder "$titleSan.mp4"
                                } elseif (Test-Path -LiteralPath (Join-Path $destFolder "$titleSan.mkv")) {
                                    $videoFile = Join-Path $destFolder "$titleSan.mkv"
                                }

                                if ($videoFile) {
                                    $ffmpegArgs = @()
                                    if ($audioFormat -eq 'wav') {
                                        $ffmpegArgs = @("-i", $videoFile, "-vn", "-acodec", "pcm_s24le", "-ar", "48000", $finalAudioFile, "-y", "-hide_banner", "-loglevel", "error")
                                    } else { # mp3
                                        $ffmpegArgs = @("-i", $videoFile, "-vn", "-c:a", "libmp3lame", "-b:a", "320k", $finalAudioFile, "-y", "-hide_banner", "-loglevel", "error")
                                    }
                                    [void](Invoke-ExternalAnimated -FilePath $ffmpegExe -Arguments $ffmpegArgs -CaptureOutput:$false)

                                    if (Test-Path -LiteralPath $finalAudioFile) {
                                        if ($audioFormat -eq 'wav') { try { [void](Ensure-WavFormat -WavPath $finalAudioFile) } catch {} }
                                        $ex = $downloadReport | Where-Object { $_.T -eq $titleSan };
                                        if ($ex) { $ex.D += if ($audioFormat -eq 'wav') { " +WAV OK (extracted)." } else { " +MP3 OK (extracted)." } }
                                    } else {
                                        throw "All audio acquisition methods failed, including FFmpeg extraction."
                                    }
                                } else {
                                    throw "No video file found to extract audio from."
                                }
                            } else {
                                # --- ULTIMATE FALLBACK #4: Download a temporary video just to extract its audio (for audio_only mode) ---
                                Write-Centered "Dedicated audio download failed. Attempting to download a temporary video to extract audio..." "DarkCyan"
                                $tempVideoFile = Join-Path $destFolder "__temp_video_for_audio_$([Guid]::NewGuid()).tmp"
                                $videoDownloaded = $false
                                
                                try {
                                    # Attempt to download a standard, compatible video format
                                    if (Invoke-YTDLPVideoAttempt -Fmt 'best[ext=mp4]/best' -Out $tempVideoFile -Url $video.webpage_url -MergeContainer 'mp4') {
                                        $videoDownloaded = $true
                                    }

                                    if ($videoDownloaded) {
                                        # If the temporary video was downloaded, extract audio from it
                                        $ffmpegArgs = @()
                                        if ($audioFormat -eq 'wav') {
                                            $ffmpegArgs = @("-i", $tempVideoFile, "-vn", "-acodec", "pcm_s24le", "-ar", "48000", $finalAudioFile, "-y", "-hide_banner", "-loglevel", "error")
                                        } else { # mp3
                                            $ffmpegArgs = @("-i", $tempVideoFile, "-vn", "-c:a", "libmp3lame", "-b:a", "320k", $finalAudioFile, "-y", "-hide_banner", "-loglevel", "error")
                                        }
                                        [void](Invoke-ExternalAnimated -FilePath $ffmpegExe -Arguments $ffmpegArgs -CaptureOutput:$false)

                                        if (Test-Path -LiteralPath $finalAudioFile) {
                                            if ($audioFormat -eq 'wav') { try { [void](Ensure-WavFormat -WavPath $finalAudioFile) } catch {} }
                                            $reportMsg = if ($audioFormat -eq 'wav') { "WAV OK (extracted from video)." } else { "MP3 OK (extracted from video)." }
                                            $downloadReport += [PSCustomObject]@{ T=$titleSan; S="Success"; D=$reportMsg }
                                        } else {
                                            throw "Failed to extract audio from the temporary video file."
                                        }
                                    } else {
                                        throw "All dedicated audio download attempts failed, and could not download a temporary video."
                                    }
                                } finally {
                                    # IMPORTANT: Always clean up the temporary video file
                                    if (Test-Path -LiteralPath $tempVideoFile) {
                                        try { Remove-Item -LiteralPath $tempVideoFile -Force -ErrorAction SilentlyContinue } catch {}
                                    }
                                }
                            }
                        }
                    } catch { 
                        $reportMsg = if ($audioFormat -eq 'wav') { "+WAV" } else { "+MP3" }
                        if ($formatChoice -eq 'audio') {
                             $downloadReport += [PSCustomObject]@{ T=$titleSan; S="Failure"; D="$($reportMsg.Replace('+','')) download error: $($_.Exception.Message)" }
                        } else {
                            $ex = $downloadReport | Where-Object { $_.T -eq $titleSan };
                            if ($ex) { $ex.S="Failure"; $ex.D += " $($reportMsg) download/extraction error: $($_.Exception.Message)" }
                        }
                    }
                }
            }

            # ================== METADATA INJECTION (Dual-Stage) ==================
            $metadataComment = "Downloaded by ARN-DL (https://AlgoRythmic.Network/ARN-DL/)"
            
            $filesToTag = @(
                (Join-Path $destFolder "$titleSan.mp4"),
                (Join-Path $destFolder "$titleSan.mkv"),
                (Join-Path $destFolder "$titleSan.wav")
                (Join-Path $destFolder "$titleSan.mp3")
            ) | Where-Object { Test-Path -LiteralPath $_ }

            if ($filesToTag.Count -gt 0) {
                # --- STAGE 1: Metadata FFmpeg ---
                Write-Centered "Injecting metadata..." "Gray"
                foreach ($file in $filesToTag) {
                    try {
                        Set-FileMetadata -FilePath $file -Comment $metadataComment
                    } catch {
                        Write-Warning "Mtadata injection failed for $($file): $($_.Exception.Message)"
                    }
                }

                # --- STAGE 2: Windows-Specific WAV Patch ---
                $wavFilesToPatch = $filesToTag | Where-Object { $_.ToLower().EndsWith('.wav') }
                if ($wavFilesToPatch.Count -gt 0) {
                    foreach ($wavFile in $wavFilesToPatch) {
                        $tempWavPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), ([System.IO.Path]::GetRandomFileName() + ".wav"))
                        try {
                            Set-WavMetadata -Path $wavFile -OutputPath $tempWavPath -Album $metadataComment

                            if ((Test-Path -LiteralPath $tempWavPath) -and (Get-Item $tempWavPath).Length -gt 0) {
                                Remove-Item -LiteralPath $wavFile -Force -ErrorAction SilentlyContinue
                                Move-Item -LiteralPath $tempWavPath -Destination $wavFile -Force
                            }
                        } catch {
                            Write-Error "An error occurred during the WAV patch process for $($wavFile): $($_.Exception.Message)"
                        }
                    }
                }
            }
            # =====================================================================
        }

        if ($downloadReport.Count -gt 0) {
            Write-Centered "--------------------------------------------------------" "Yellow"
            Write-Centered "Download Report:" "Yellow"
            foreach($item in $downloadReport) {
                switch ($item.S) {
                    "Success" { Write-Centered "[✔] $($item.T) - $($item.D)" "Green" }
                    "Warning" { Write-Centered "[!] $($item.T) - $($item.D)" "Yellow" }
                    "Failure" { Write-Centered "[❌] $($item.T) - $($item.D)" "Red" }
                }
            }
            Write-Centered "--------------------------------------------------------" "Yellow"
        }

        Start-MenuMusic
    }
}


# ----------- Main loop -----------
while ($true) {
    $mode = Show-InputModeMenu
    if ($mode -eq 'cookies') { Start-Process notepad.exe $script:CookiesFile; continue }
    if ($mode -eq 'options') { Show-OptionsMenu; continue }
    if ($mode -eq 'exit') { break }
    if ($mode -eq 'update') {
    Clear-Host 
    
    Write-Centered ""
    $logoLines = @(
        '░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░',
        '░░▄█▀░█▀█░█▀▄░█▄░█░░░░░█▀▄░█░░░▀█▄░░',
        '░▄█▀░░█▀█░█▀▄░█░▀█░▀▀▀░█░█░█░░░░▄█▀░',
        '░░▀█▄░▀░▀░▀░▀░▀░░▀░░░░░▀▀▀░▀▀▀░▄█▀░░',
        '░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░'
    )
    $consoleWidth = $Host.UI.RawUI.WindowSize.Width
    foreach ($line in $logoLines) {
        $padding = [string]" " * (($consoleWidth - $line.Length) / 2)
        Write-Host "$padding$line" -ForegroundColor Green
    }

    Write-Centered ""
    Write-MatrixBanner -Lines 4 -Context "Analysis"
    Write-Centered ""
    
    # --- 1. Update yt-dlp ---
    Write-Centered "--- 1/2: Updating yt-dlp ---" "Yellow"
    Write-Centered ""
    [void](Invoke-ExternalAnimated -FilePath $ytDlpExe -Arguments @("-U") -CaptureOutput -Heavy:$false)
    Write-Centered "`nyt-dlp is up to date." "Green"; Start-Sleep -Seconds 1

    # --- 2. Update FFMPEG & FFPROBE ---
    Write-Centered "`n--- 2/2: Updating FFMPEG & FFPROBE ---" "Yellow"
    
    # FIX 2: Define paths before the try block so they exist for the 'finally' cleanup.
    $tempFolder = Join-Path $scriptFolder "ffmpeg_temp"
    $zipFile = Join-Path $scriptFolder "ffmpeg.zip"

    try {
        # --- START: Version Check Logic ---
        $latestVersionUrl = "https://www.gyan.dev/ffmpeg/builds/release-version"
        Write-Centered "`n[1/5] Checking for the latest FFMPEG version..." "Cyan"

        # FIX 1: Convert the web request result to a string before calling .Trim()
        $latestVersion = (Invoke-WebRequest -Uri $latestVersionUrl -UseBasicParsing).ToString().Trim()

        $localVersion = $null
        if (Test-Path $ffmpegExe) {
            $localVersionOutput = (& $ffmpegExe -version 2>&1 | Select-Object -First 1)
            $match = [regex]::Match($localVersionOutput, "ffmpeg version ([\d\.]+)")
            if ($match.Success) {
                $localVersion = $match.Groups[1].Value
            }
        }
        
        Write-Centered "-> Latest online version: $latestVersion" "Gray"
        Write-Centered "-> Your current version: $(if ($localVersion) {$localVersion} else {'Not Found'})" "Gray"

        if ($localVersion -eq $latestVersion) {
            Write-Centered "`nFFMPEG is already up to date. Nothing to do." "Green"
            Start-Sleep -Seconds 2
            throw "Update skipped"
        }
        # --- END: Version Check Logic ---

        $ffmpegZipUrl = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
        
        # Download the archive
        Write-Centered "`n[2/5] Downloading the latest FFMPEG version ($latestVersion)..." "Cyan"
        Invoke-WebRequest -Uri $ffmpegZipUrl -OutFile $zipFile -UseBasicParsing
        Write-Centered "Download complete." "Green"

        # Create temporary folder and extract
        Write-Centered "[3/5] Extracting files..." "Cyan"
        if (Test-Path $tempFolder) { Remove-Item -Recurse -Force $tempFolder }
        New-Item -ItemType Directory -Force -Path $tempFolder | Out-Null
        Expand-Archive -LiteralPath $zipFile -DestinationPath $tempFolder -Force
        Write-Centered "Extraction complete." "Green"

        # Find the new executables
        $newFilesPath = (Get-ChildItem -Path $tempFolder -Directory).FullName | Select-Object -First 1
        $newFfmpeg = Join-Path $newFilesPath "bin\ffmpeg.exe"
        $newFfprobe = Join-Path $newFilesPath "bin\ffprobe.exe"

        # Replace the old files
        if ((Test-Path $newFfmpeg) -and (Test-Path $newFfprobe)) {
            Write-Centered "[4/5] Replacing old files..." "Cyan"
            Move-Item -LiteralPath $newFfmpeg -Destination $ffmpegExe -Force
            Move-Item -LiteralPath $newFfprobe -Destination $ffprobeExe -Force
            Write-Centered "Files updated successfully!" "Green"
        } else {
            Write-Centered "ERROR: Could not find ffmpeg.exe/ffprobe.exe in the archive." "Red"
        }

    } catch {
        if ($_.ToString() -ne "Update skipped") {
            Write-Centered "`nAn error occurred while updating FFMPEG:" "Red"
            Write-Centered $_.Exception.Message "Red"
        }
    } finally {
        # Cleanup
        Write-Centered "[5/5] Cleaning up temporary files..." "Cyan"
        if (Test-Path $tempFolder) { Remove-Item -Recurse -Force $tempFolder }
        if (Test-Path $zipFile) { Remove-Item -Force $zipFile }
        Write-Centered "Cleanup complete." "Green"
    }
    
    Write-Centered "`nUpdate process finished." "Green"
    Write-Centered "Press any key to continue..." "Yellow"
    [void]([System.Console]::ReadKey($true))
    continue
}

if ($mode -eq 'selfupdate') {
    Clear-Host
    Write-Centered "--- Script Self-Update ---" "Yellow"
    Write-Centered ""
    
    # GitHub API URL to get the latest release information.
    $apiUrl = "https://api.github.com/repos/ARN-Inside/ARN-DL/releases/latest"
    
    try {
        Write-Centered "Connecting to GitHub API to check for new release..." "Cyan"
        
        $releaseInfo = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing
        $remoteTagName = $releaseInfo.tag_name
        
        if ([string]::IsNullOrWhiteSpace($remoteTagName)) {
            throw "Could not find a valid release tag from the GitHub API. Please ensure a release has been created."
        }
        
        $remoteVersion = $remoteTagName.TrimStart('v')
        
        Write-Centered "-> Your current version: $($script:Version)" "Gray"
        Write-Centered "-> Latest available release: $remoteVersion" "Gray"
        Write-Centered ""

        if ([version]$remoteVersion -gt [version]$script:Version) {
            Write-Centered "A new version is available! Preparing update..." "Green"
            Start-Sleep -Seconds 2
            
            # --- Robust Update Method via a Temporary Batch Script ---

            # 1. Define paths and URLs.
            $scriptUrl = "https://raw.githubusercontent.com/ARN-Inside/ARN-DL/main/Data_Inside/ARN-DL.ps1"
            $targetPath = $PSCommandPath
            $tempPath = $targetPath + ".new"
            $workingDir = Split-Path -Path $targetPath -Parent
            $mainLauncherPath = Join-Path $workingDir "ARN.bat"

            # 2. Create the content for the temporary BATCH file updater.
            $updaterBatContent = @"
@echo off
echo.
echo [ARN-DL Updater] Waiting for main script to close...
timeout /t 2 /nobreak > nul

echo [ARN-DL Updater] Downloading new version...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri '$scriptUrl' -OutFile '$tempPath' -UseBasicParsing"

if exist "$tempPath" (
    echo [ARN-DL Updater] Download complete. Replacing old file...
    move /Y "$tempPath" "$targetPath" > nul
    
    echo [ARN-DL Updater] Update successful! Relaunching ARN-DL...
    timeout /t 2 /nobreak > nul
    
    start "" "$mainLauncherPath"
) else (
    echo [ARN-DL Updater] ERROR: Update download failed.
    pause
)

(goto) 2>nul & del "%~f0"
"@
            
            # 3. Write the temporary batch updater to disk.
            $updaterBatPath = Join-Path $workingDir "temp_updater.bat"
            Set-Content -Path $updaterBatPath -Value $updaterBatContent -Encoding Ascii
            
            # 4. Launch the BATCH updater and then terminate the current script process completely.
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$updaterBatPath`"" -WorkingDirectory $workingDir
            Stop-Process -Id $PID
            
        } else {
            Write-Centered "You already have the latest version of the script (Release: $remoteTagName)." "Green"
        }
        
    } catch {
        Write-Centered "An error occurred while checking for updates:" "Red"
        Write-Centered $_.Exception.Message "Red"
    }

    Write-Centered "`nPress any key to continue..." "Yellow"
    [void]([System.Console]::ReadKey($true))
    continue
}

    $fmtChoice = $null
    while ($fmtChoice -eq $null -or $fmtChoice -eq 'back') {
        $fmtChoice = Show-FormatMenu
        if ($fmtChoice -eq 'back') { $mode = 'menu'; break }
    }
    if ($fmtChoice -eq 'back') { continue }

    $q = $null
    if ($fmtChoice -eq 'video_plus_audio') { $q = Show-QualityMenu -Mode "both" }
    elseif ($fmtChoice -eq 'video')      { $q = Show-QualityMenu -Mode "video" }
    else                                  { $q = Show-QualityMenu -Mode "audio" }
    if (-not $q) { continue }

    $urls=@()
    if ($mode -eq 'single') {
        Clear-Host
        Write-Centered ""
        $logoLines = @(
            '░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░',
            '░░▄█▀░█▀█░█▀▄░█▄░█░░░░░█▀▄░█░░░▀█▄░░',
            '░▄█▀░░█▀█░█▀▄░█░▀█░▀▀▀░█░█░█░░░░▄█▀░',
            '░░▀█▄░▀░▀░▀░▀░▀░░▀░░░░░▀▀▀░▀▀▀░▄█▀░░',
            '░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░'
        )
        $consoleWidth = $Host.UI.RawUI.WindowSize.Width
        foreach ($line in $logoLines) {
            $padding = [string]" " * (($consoleWidth - $line.Length) / 2)
            Write-Host "$padding$line" -ForegroundColor Green
        }

        Write-Centered ""
        Write-MatrixBanner -Lines 4 -Context "Menu"
        Write-Centered ""
        Write-Centered "Paste a single video or playlist URL" "Yellow"; Write-Host ""
        $one = Read-LineAnimated -Prompt " -> "; if ($one){ $urls += $one.Trim() }
    } elseif ($mode -eq 'multiple') {
        $multi = Read-MultipleLinesAnimated -Header "Paste one or more video links."; if ($multi.Count -gt 0) { $urls = ($multi -join ',') -replace ';',',' -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } }
    }
    if ($urls.Count -eq 0) { Write-Centered "No valid URLs entered." "Red"; Start-Sleep -Seconds 2; continue }

    Download-Flow -urlsToProcess $urls -formatChoice $fmtChoice -qualityObject $q

    Write-Centered "`n✅ All tasks complete." "Green"; Write-Centered ""; Write-Centered "Press any key to continue..." "Yellow"; [void](Wait-KeyNonBlocking)
}

Clear-Host


# --- Final injection ---
Show-LogoAnimation -Repetitions 8 -LogoForegroundColor Green -ScreenBackgroundColor DarkBlue


Stop-Process -Id $PID
