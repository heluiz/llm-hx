# Teste real dos workflows HX via API local do ComfyUI (somente biblioteca padrao + Pillow do ComfyUI)
import json, urllib.request, urllib.error, time, subprocess, os, threading, sys
BASE = "http://127.0.0.1:8188"
D = r"C:\LLM\Imagem\Ferramentas_HX\teste"
OUTS = [r"C:\LLM\Imagem\Resultados", r"C:\LLM\Imagem\ComfyUI_windows_portable\ComfyUI\output"]
WF = sys.argv[1:] or ([l.strip() for l in open(os.path.join(D, "fila.txt")) if l.strip()] if os.path.exists(os.path.join(D, "fila.txt")) else ["Z-Image-Transformar-Foto", "Z-Image-Inspiracao-Imagem"])
def get(p, t=10): return json.load(urllib.request.urlopen(BASE + p, timeout=t))
def post(p, data):
    req = urllib.request.Request(BASE + p, data=json.dumps(data).encode(), headers={"Content-Type": "application/json"})
    try: return json.load(urllib.request.urlopen(req, timeout=60))
    except urllib.error.HTTPError as e: return {"http_error": e.code, "body": e.read().decode("utf-8", "replace")}
def vram():
    try: return int(subprocess.run(["nvidia-smi", "--query-gpu=memory.used", "--format=csv,noheader,nounits"], capture_output=True, text=True, timeout=5).stdout.strip().splitlines()[0])
    except Exception: return -1
rep = {"inicio": time.strftime("%Y-%m-%d %H:%M:%S")}
for i in range(180):
    try: st = get("/system_stats"); break
    except Exception: time.sleep(1)
else:
    rep["erro"] = "servidor nao respondeu em 180 s"; json.dump(rep, open(os.path.join(D, "resultado_" + ("fila" if (not sys.argv[1:] and os.path.exists(os.path.join(D, "fila.txt"))) else "teste") + ".json"), "w"), indent=1); sys.exit(1)
rep["argv"] = st["system"]["argv"]; rep["vram_antes_MiB"] = vram(); rep["testes"] = []
for wf in WF:
    prompt = json.load(open(os.path.join(D, wf + ".api.json"), encoding="utf-8"))["prompt"]
    peak = [0]; stop = [False]
    def sampler():
        while not stop[0]:
            v = vram(); peak[0] = max(peak[0], v); time.sleep(0.5)
    th = threading.Thread(target=sampler, daemon=True); th.start()
    t0 = time.time(); r = post("/prompt", {"prompt": prompt, "client_id": "hx-teste"})
    item = {"workflow": wf, "resposta_post": r}
    pid = r.get("prompt_id")
    if pid:
        while time.time() - t0 < 900:
            h = get("/history/" + pid)
            if pid in h and h[pid].get("status", {}).get("completed") is not None or (pid in h and h[pid].get("status", {}).get("status_str") in ("success", "error")):
                hh = h[pid]; item["status"] = hh.get("status"); item["outputs"] = hh.get("outputs"); break
            time.sleep(1)
        else: item["status"] = "TIMEOUT"
    stop[0] = True; th.join(2)
    item["tempo_s"] = round(time.time() - t0, 1); item["pico_vram_MiB"] = peak[0]
    files = []
    for nid, o in (item.get("outputs") or {}).items():
        for im in o.get("images", []):
            if im.get("type") != "output": continue
            for base in OUTS:
                p = os.path.join(base, im.get("subfolder", ""), im["filename"])
                if os.path.exists(p):
                    info = {"arquivo": p, "bytes": os.path.getsize(p)}
                    try:
                        from PIL import Image
                        with Image.open(p) as I: info["tamanho"] = I.size; I.load(); info["abre_ok"] = True
                    except Exception as e: info["abre_ok"] = False; info["erro_abrir"] = repr(e)
                    files.append(info); break
    item["arquivos"] = files
    rep["testes"].append(item)
rep["vram_depois_MiB"] = vram()
try:
    logs = get("/internal/logs")
    rep["log_final"] = logs[-6000:] if isinstance(logs, str) else str(logs)[-6000:]
except Exception as e: rep["log_final"] = repr(e)
rep["fim"] = time.strftime("%Y-%m-%d %H:%M:%S")
json.dump(rep, open(os.path.join(D, "resultado_" + ("fila" if (not sys.argv[1:] and os.path.exists(os.path.join(D, "fila.txt"))) else "teste") + ".json"), "w", encoding="utf-8"), indent=1, ensure_ascii=False)
print("OK")
