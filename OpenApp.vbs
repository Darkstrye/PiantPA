Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' Get the directory where this script is located
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)

' Change to that directory and run the batch file
WshShell.CurrentDirectory = scriptDir
WshShell.Run "cmd /k run_app.bat", 1, True

Set WshShell = Nothing
Set fso = Nothing

