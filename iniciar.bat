@echo off
cd /d "%~dp0"
rem Monitor de salud en segundo plano (sigue funcionando aunque la web este cerrada)
start "" /min powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0monitor.ps1"
rem Servidor web + abrir el navegador tras 2 segundos
start "" /min powershell -NoProfile -WindowStyle Hidden -Command "Start-Sleep -Seconds 5; $p = if (Test-Path '%~dp0puerto.txt') { (Get-Content '%~dp0puerto.txt' -Raw).Trim() } else { '8080' }; Start-Process ('http://localhost:' + $p + '/')"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1"
pause
