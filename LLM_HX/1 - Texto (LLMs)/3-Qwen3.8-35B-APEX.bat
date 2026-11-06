@echo off
title Qwen3.8-35B-A3B APEX
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\9 - Sistema (nao mexer)\run-model.ps1" -Dir qwen38-35b-a3b-apex -Preset qwen -Ctx 32768 -Vision
pause
