@echo off
REM Coleta somente leitura da API local do ComfyUI (criado pelo Claude)
set D=C:\LLM\Imagem\Ferramentas_HX\api
if not exist "%D%" mkdir "%D%"
for %%N in (LoadImage ImageScaleToTotalPixels ImageScaleToMaxDimension Canny CLIPLoader UNETLoader VAELoader ModelPatchLoader QwenImageDiffsynthControlnet ZImageFunControlnet ModelSamplingAuraFlow KSampler CLIPTextEncode ConditioningZeroOut VAEEncode VAEDecode SaveImage PreviewImage GetImageSize EmptySD3LatentImage) do curl -s -m 10 http://127.0.0.1:8188/object_info/%%N -o "%D%\%%N.json"
curl -s -m 10 http://127.0.0.1:8188/queue -o "%D%\queue.json"
curl -s -m 10 http://127.0.0.1:8188/internal/logs -o "%D%\logs.json"
curl -s -m 10 http://127.0.0.1:8188/system_stats -o "%D%\system_stats.json"
curl -s -m 10 "http://127.0.0.1:8188/history?max_items=10" -o "%D%\history.json"
echo ok > "%D%\_fim.txt"
