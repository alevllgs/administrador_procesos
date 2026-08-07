' =============================================================================
' start_admin_hidden.vbs - Lanza el Administrador de Procesos SIN ventana
' de consola, para que nadie pueda cerrarla accidentalmente.
' Uso: doble clic, o como comando de la tarea de autoarranque.
' =============================================================================
Option Explicit

Dim fso, wsh, appDir, comando
Set fso = CreateObject("Scripting.FileSystemObject")
Set wsh = CreateObject("WScript.Shell")

' Carpeta donde esta este .vbs (C:\administrador_procesos)
appDir = fso.GetParentFolderName(WScript.ScriptFullName)

' Ejecuta el lanzador silencioso con la ventana OCLTADA (estilo 0)
comando = "cmd.exe /c """ & appDir & "\run_admin_silent.bat"""
wsh.Run comando, 0, False
