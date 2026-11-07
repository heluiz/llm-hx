@echo off
title Agente HX - Diagnostico
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\9 - Sistema (nao mexer)\agente\agente-verificar.ps1"
pause
