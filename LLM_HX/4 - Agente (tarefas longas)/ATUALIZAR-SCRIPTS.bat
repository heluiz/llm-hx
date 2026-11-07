@echo off
title Agente HX - Atualizar scripts
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\9 - Sistema (nao mexer)\agente\agente-instalar.ps1" -SoScripts
pause
