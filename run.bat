@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -Verb RunAs -WorkingDirectory '%~dp0' -ArgumentList'-NoProfile -ExecutionPolicy Bypass -File ""%~dp0BackupBench.ps1""'"
