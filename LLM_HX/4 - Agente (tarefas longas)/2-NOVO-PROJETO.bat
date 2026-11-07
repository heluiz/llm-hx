@echo off
title Agente HX - Novo projeto
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\9 - Sistema (nao mexer)\agente\agente-projeto.ps1" -Acao novo
pause
