# Teste real do Voicebox via API local (stdlib). Criado pelo Claude.
import json, urllib.request, urllib.error, time, subprocess, os, threading, uuid
B = "http://127.0.0.1:17493"; D = r"C:\LLM\Imagem\Ferramentas_HX\voz"; OUT = r"C:\LLM\Voz\output"
os.makedirs(OUT, exist_ok=True)
def get(p, t=30): return json.load(urllib.request.urlopen(B + p, timeout=t))
def post(p, data, t=60):
    req = urllib.request.Request(B + p, data=json.dumps(data).encode(), headers={"Content-Type": "application/json"})
    try: return json.load(urllib.request.urlopen(req, timeout=t))
    except urllib.error.HTTPError as e: return {"http_error": e.code, "body": e.read().decode("utf-8", "replace")}
def vram():
    try: return int(subprocess.run(["nvidia-smi", "--query-gpu=memory.used", "--format=csv,noheader,nounits"], capture_output=True, text=True, timeout=5).stdout.split()[0])
    except Exception: return -1
def transcribe(path, model="turbo", lang="pt"):
    bnd = uuid.uuid4().hex; body = b""
    for k, v in (("language", lang), ("model", model)):
        body += f"--{bnd}\r\nContent-Disposition: form-data; name=\"{k}\"\r\n\r\n{v}\r\n".encode()
    body += f"--{bnd}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.wav\"\r\nContent-Type: audio/wav\r\n\r\n".encode() + open(path, "rb").read() + f"\r\n--{bnd}--\r\n".encode()
    req = urllib.request.Request(B + "/transcribe", data=body, headers={"Content-Type": f"multipart/form-data; boundary={bnd}"})
    try: return json.load(urllib.request.urlopen(req, timeout=600))
    except urllib.error.HTTPError as e: return {"http_error": e.code, "body": e.read().decode("utf-8", "replace")}
rep = {"inicio": time.strftime("%H:%M:%S"), "health": get("/health"), "cache": get("/models/cache-dir"), "testes": []}
prof = [p for p in get("/profiles") if p["name"] == "Minha Voz"][0]
TEXTO = "Boa noite. Este é um teste do Voicebox configurado na placa de vídeo. A equipe cinco assume o plantão às dezenove horas."
for size in ("1.7B", "0.6B"):
    peak = [0]; stop = [False]
    def s():
        while not stop[0]: peak[0] = max(peak[0], vram()); time.sleep(0.5)
    th = threading.Thread(target=s, daemon=True); th.start()
    t0 = time.time(); r = post("/generate", {"profile_id": prof["id"], "text": TEXTO, "language": "pt", "model_size": size, "engine": "qwen", "seed": 42})
    item = {"modelo": size, "post": {k: r.get(k) for k in ("id", "status", "http_error", "body") if k in r}}
    gid = r.get("id")
    while gid and time.time() - t0 < 900:
        h = get("/history/" + gid)
        if h.get("status") in ("completed", "failed"): item["status"] = h["status"]; item["erro"] = h.get("error"); item["duracao_audio_s"] = h.get("duration"); break
        time.sleep(1)
    stop[0] = True; th.join(2)
    item["tempo_s"] = round(time.time() - t0, 1); item["pico_vram_MiB"] = peak[0]
    if item.get("status") == "completed":
        dst = os.path.join(OUT, f"teste_voicebox_{size}.wav")
        with urllib.request.urlopen(B + f"/history/{gid}/export-audio", timeout=60) as resp, open(dst, "wb") as f: f.write(resp.read())
        item["arquivo"] = dst; item["bytes"] = os.path.getsize(dst)
        item["transcricao_whisper"] = transcribe(dst)
    rep["testes"].append(item)
rep["vram_final_MiB"] = vram(); rep["fim"] = time.strftime("%H:%M:%S")
json.dump(rep, open(os.path.join(D, "resultado_voz.json"), "w", encoding="utf-8"), indent=1, ensure_ascii=False)
