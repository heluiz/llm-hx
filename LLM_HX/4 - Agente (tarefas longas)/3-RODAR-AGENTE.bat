@echo off
title Agente HX - Rodando
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\9 - Sistema (nao mexer)\agente\agente-projeto.ps1" -Acao rodar
pause
