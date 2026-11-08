Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
base = fso.GetParentFolderName(WScript.ScriptFullName)
sh.Run "powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & base & "\tun-agent.ps1""", 0, False
