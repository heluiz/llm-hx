@echo off
title Qwen3.6-35B-A3B (oficial)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\9 - Sistema (nao mexer)\run-model.ps1" -Dir qwen36-35b-a3b -Preset qwen -Ctx 32768 -Vision
pause
