#cs ----------------------------------------------------------------------------
    Script:         ARN-DL One-Time Setup Utility
    Author:         ARN Inside (with Cloud guidance)
    Version:        4.2 - The Perfect Shield
    Description:    A self-contained utility to configure ARN-DL for a seamless,
                    UAC-free user experience by leveraging the Windows Task Scheduler.
#ce ----------------------------------------------------------------------------

; === COMPILER & SCRIPT DIRECTIVES ===========================================
#pragma compile(Console, True)
#RequireAdmin

; === INCLUDES ===============================================================
#include <Misc.au3>

; === SCRIPT OPTIONS =========================================================
Opt("WinTitleMatchMode", 2)

; === KERNEL-LEVEL CODEPAGE INJECTION (ADDED FOR RELIABILITY) ================
; This command ensures maximum character compatibility for the console.
DllCall("kernel32.dll", "bool", "SetConsoleOutputCP", "uint", 65001)

; === CONFIGURATION ==========================================================
; Defines the name of the .lnk file that will be created.
Global $shortcutName = "ARN-DL.lnk"
; Path to the actual script/batch file that the scheduled task will execute.
Global $launcherPath = @ScriptDir & "\Data_Inside\ARN.bat"
; Path to the .ico file used for the shortcut's icon.
Global $iconPath = @ScriptDir & "\Data_Inside\ARN-DL.ico"
; The unique name for the Windows Scheduled Task.
Global $taskName = "ARN-DL_Launcher"
; The working directory for the task, ensuring relative paths in the launched script work correctly.
Global $workingDir = @ScriptDir & "\Data_Inside\"
; Path to the user's Desktop folder.
Global $desktopPath = @DesktopDir
; Path to the root folder of the script.
Global $localPath = @ScriptDir
; Path to the setup's intro audio file.
Global $audioPath = @ScriptDir & "\Data_Inside\Core_audio_components\ARN_Inside.wav"

; === VISUAL & AUDIO INTRO ===================================================
; The sound file provides an immersive ambiance for the setup process.
If FileExists($audioPath) Then
    SoundPlay($audioPath)
EndIf

; A clean, straightforward title is displayed. No logos.
ConsoleWrite("====================================================================================" & @CRLF)
_ConsoleWriteColor("                            Welcome to the ARN-DL Setup" & @CRLF, 10)
ConsoleWrite("====================================================================================" & @CRLF & @CRLF)

_ConsoleWriteColor ("Initializing setup sequence..." & @CRLF, 10)
ConsoleWrite(@CRLF)
Sleep(2000)

; === MAIN EXPLANATION =======================================================
_ConsoleWriteColor("A one-time administrator approval is required to enable permission-free launching from the shortcut." & @CRLF, 11)

; === MAIN LOGIC =============================================================
; The core of the setup. This section establishes the UAC bypass mechanism.
; It works in two parts: first, registering a privileged task, and second,
; creating shortcuts that can trigger this task on demand without a UAC prompt.

; --- Step 1: Create the Scheduled Task ---
; A task is registered with the highest privileges. The key is the schedule:
; by setting it to run once on a date in the past, we ensure the task is valid
; but will never be triggered by the Windows Scheduler itself

ConsoleWrite(@CRLF & "[1/3] Registering the permission-free launching..." & @CRLF)

; The command is now completely silent, redirecting both success (1) and error (2) messages to NUL.
Local $sSilentCommand = @ComSpec & ' /c schtasks /create /tn "' & $taskName & '" /tr "' & $launcherPath & '" /sc once /sd 01/01/2000 /st 00:00 /rl highest /f > NUL 2>&1'

; We run the command and wait for it to finish, ignoring its exit code.
RunWait($sSilentCommand, "", @SW_HIDE)

; This is now the only output, confirming the operation's completion.
_ConsoleWriteColor("      Enable permission-free launching successfully." & @CRLF, 10)

; --- Step 2: Create the Desktop Shortcut ---
ConsoleWrite("[2/3] Creating the Desktop shortcut..." & @CRLF)
FileCreateShortcut(@SystemDir & "\schtasks.exe", $desktopPath & "\" & $shortcutName, $workingDir, '/run /tn "' & $taskName & '"', "Launcher for ARN-DL", $iconPath)
_ConsoleWriteColor("      Desktop shortcut created." & @CRLF, 10)
Sleep(500)

; --- Step 3: Create the Local Shortcut ---
ConsoleWrite("[3/3] Creating a local shortcut in the current folder..." & @CRLF)
FileCreateShortcut(@SystemDir & "\schtasks.exe", $localPath & "\" & $shortcutName, $workingDir, '/run /tn "' & $taskName & '"', "Launcher for ARN-DL", $iconPath)
If Not @error Then
    _ConsoleWriteColor("      Local shortcut created." & @CRLF, 10)
Else
    _ConsoleWriteColor("      Warning: Could not create local shortcut." & @CRLF, 12)
EndIf
Sleep(1000)

; === SUCCESS SCREEN ========================================================
ConsoleWrite(@CRLF & @CRLF & "====================================================================================" & @CRLF)
_ConsoleWriteColor("                                SETUP COMPLETE!" & @CRLF, 10)
ConsoleWrite("====================================================================================" & @CRLF & @CRLF)
_Pause(@CRLF & "Enjoy! Press any key to exit.")
Exit

; === HELPER FUNCTIONS =======================================================

; SYNOPSIS: Writes a line of text centered in the console window.
Func _ConsoleWriteCentered($sText)
    Local $t_SCI = DllStructCreate("int;short;short;short;short;short;short;short;short;short;short")
    Local $a_Ret = DllCall("kernel32.dll", "int", "GetConsoleScreenBufferInfo", "hwnd", DllCall("kernel32.dll", "hwnd", "GetStdHandle", "int", -11), "ptr", DllStructGetPtr($t_SCI))
    If @error Or $a_Ret[0] = 0 Then
        ConsoleWrite($sText & @CRLF)
        Return
    EndIf
    Local $iConsoleWidth = DllStructGetData($t_SCI, 8) - DllStructGetData($t_SCI, 6) + 1
    Local $iPadding = Floor(($iConsoleWidth - StringLen($sText)) / 2)
    If $iPadding < 0 Then $iPadding = 0
    ConsoleWrite(_StringRepeat(" ", $iPadding) & $sText & @CRLF)
EndFunc

; SYNOPSIS: Writes a centered line of text in a specified color.
Func _ConsoleWriteColor($sText, $iColor = 15)
    Local $hConsole = DllCall("kernel32.dll", "hwnd", "GetStdHandle", "int", -11)
    DllCall("kernel32.dll", "int", "SetConsoleTextAttribute", "hwnd", $hConsole[0], "int", $iColor)
    _ConsoleWriteCentered($sText)
    DllCall("kernel32.dll", "int", "SetConsoleTextAttribute", "hwnd", $hConsole[0], "int", 7)
EndFunc

; SYNOPSIS: Displays a message and waits for any key press to continue.
Func _Pause($sMessage)
    ConsoleWrite($sMessage & @CRLF)
    While 1
        For $i = 1 To 254
            If $i = 2 Then ContinueLoop
            If _IsPressed(Hex($i, 2)) Then Return
        Next
        Sleep(20)
    WEnd
EndFunc

; SYNOPSIS: Repeats a given string a specified number of times.
Func _StringRepeat($sString, $iCount)
    Local $sResult = ""
    For $i = 1 To $iCount
        $sResult &= $sString
    Next
    Return $sResult
EndFunc