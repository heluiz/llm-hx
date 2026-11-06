@echo off
REM Descarrega da placa de video os modelos do Voicebox (nao apaga nada do disco). Use antes de rodar o ComfyUI.
for %%M in (qwen-tts-1.7B qwen-tts-0.6B qwen-custom-voice-1.7B qwen-custom-voice-0.6B whisper-turbo whisper-medium qwen3-0.6b) do curl -s -m 20 -X POST http://127.0.0.1:17493/models/%%M/unload >nul 2>&1
echo Modelos do Voicebox descarregados da VRAM.
timeout /t 3 >nul
