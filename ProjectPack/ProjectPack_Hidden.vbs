Option Explicit

Dim shell, cmd, i, dir

Set shell = CreateObject("WScript.Shell")
dir = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))

cmd = Chr(34) & dir & "ProjectPack.bat" & Chr(34)

For i = 0 To WScript.Arguments.Count - 1
    cmd = cmd & " " & Chr(34) & WScript.Arguments(i) & Chr(34)
Next

' 0 = ventana oculta, False = no esperar a que termine
shell.Run cmd, 0, False