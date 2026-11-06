@echo off
REM Encerra SOMENTE o processo que escuta 127.0.0.1:8188 (ComfyUI) e reabre com o lancador HX.
for /f "tokens=5" %%P in ('netstat -ano ^| findstr "127.0.0.1:8188" ^| findstr "LISTENING"') do (
  echo Encerrando ComfyUI PID %%P
  taskkill /PID %%P /F
)
timeout /t 4 /nobreak >nul
start "ComfyUI HX" /D "C:\LLM\Imagem\ComfyUI_windows_portable" cmd /k run_nvidia_gpu_HX.bat
