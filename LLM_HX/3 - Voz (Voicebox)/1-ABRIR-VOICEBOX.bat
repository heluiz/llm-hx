@echo off
REM Abre o Voicebox garantindo que ele use os modelos de C:\LLM\Voz\models (criado pelo Claude)
set "VOICEBOX_MODELS_DIR=C:\LLM\Voz\models"
start "" "C:\LLM\Voz\models\voicebox.exe"
