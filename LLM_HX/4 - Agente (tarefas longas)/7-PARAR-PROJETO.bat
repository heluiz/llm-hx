@echo off
title Agente HX - Parar projeto
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\9 - Sistema (nao mexer)\agente\agente-projeto.ps1" -Acao parar
pause
