@echo off
title Gemma-4-12B Heretic
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\9 - Sistema (nao mexer)\run-model.ps1" -Dir gemma4-12b-heretic -Preset gemma -Ctx 16384 -Vision
pause
