@echo off
title Qwen3-Coder-30B-A3B (destravado)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\9 - Sistema (nao mexer)\run-model.ps1" -Dir qwen3-coder-30b-a3b-heretic -Preset coder -Ctx 32768
pause
