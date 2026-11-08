@echo off
title GPT-OSS-20B (oficial)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\9 - Sistema (nao mexer)\run-model.ps1" -Dir gpt-oss-20b -Preset gptoss -Ctx 32768
pause
