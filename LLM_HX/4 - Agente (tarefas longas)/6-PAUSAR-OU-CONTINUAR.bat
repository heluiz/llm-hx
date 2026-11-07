@echo off
title Agente HX - Pausar ou continuar
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\9 - Sistema (nao mexer)\agente\agente-projeto.ps1" -Acao pausa
pause
