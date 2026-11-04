"""Convierte un video a un MP4 ligero que la TV reproduce fluido.

Las versiones convertidas se guardan en cache/<id>.mp4 para no repetir el trabajo.
"""
import json
import math
import os
import re
import shutil
import subprocess
from fractions import Fraction

from lumbra import loopmp4

FLAGS = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0


def herramienta(nombre):
    ruta = shutil.which(nombre)
    if not ruta:
        raise RuntimeError(f"Falta {nombre}. Instala FFmpeg (https://ffmpeg.org/download.html) y vuelve a abrir Lumbra")
    return ruta


def duracion(video):
    out = subprocess.run(
        [herramienta("ffprobe"), "-v", "error", "-show_entries", "format=duration",
         "-of", "json", video],
        capture_output=True, text=True, encoding="utf-8", errors="replace", creationflags=FLAGS)
    try:
        return float(json.loads(out.stdout)["format"]["duration"])
    except (ValueError, KeyError):
        return 0.0


def tiene_audio(video, segundos):
    """True si el video trae audio que se oye (algunos traen una pista en silencio)."""
    out = subprocess.run(
        [herramienta("ffmpeg"), "-hide_banner", "-t", str(segundos), "-i", video,
         "-map", "0:a:0?", "-af", "volumedetect", "-f", "null", "-"],
        capture_output=True, text=True, encoding="utf-8", errors="replace", creationflags=FLAGS)
    m = re.search(r"max_volume: (-?[\d.]+) dB", out.stderr)
    return bool(m) and float(m.group(1)) > -60


def periodo(fps):
    """Duración mínima que es múltiplo exacto de un cuadro y de un frame AAC (1024 a 48 kHz).

    Así el audio y el video del bucle duran lo mismo y no se desfasan al repetirse.
    """
    a, b = Fraction(1, fps), Fraction(1024, 48000)
    return Fraction(math.lcm(a.numerator, b.numerator), math.gcd(a.denominator, b.denominator))


def ruta_bucle(cache_dir, item_id):
    """Un solo bucle: el launcher lo repite sin cortes."""
    return os.path.join(cache_dir, f"{item_id}_bucle.mp4")


def imagen(origen, destino, cfg):
    """Deja una imagen al tamaño de la pantalla, sin deformarla, para que ocupe poca memoria."""
    w, h = cfg["resolucion"].split("x")
    return _recortar(origen, destino, int(w) * 3 // 2, int(h) * 3 // 2)


def foto_hd(origen, destino):
    """Las fotos del salvapantallas van siempre a 1080p, sea cual sea la calidad elegida para los videos."""
    return _recortar(origen, destino, 1920, 1080)


def es_menor_que_hd(ruta):
    """Una foto pequeña se agranda para llenar la pantalla: se avisa porque no se verá tan nítida."""
    r = subprocess.run(
        [herramienta("ffprobe"), "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height",
         "-of", "csv=p=0", ruta], capture_output=True, text=True, encoding="utf-8", errors="replace", creationflags=FLAGS)
    try:
        w, h = (int(v) for v in r.stdout.strip().split(",")[:2])
    except ValueError:
        return False
    return max(w, h) < 1920 or min(w, h) < 1080


def _recortar(origen, destino, w, h):
    tmp = destino + ".part.jpg"
    r = subprocess.run(
        [herramienta("ffmpeg"), "-y", "-v", "error", "-i", origen, "-frames:v", "1", "-vf",
         f"scale={w}:{h}:force_original_aspect_ratio=increase:flags=lanczos,crop={w}:{h}", "-q:v", "2", tmp],
        capture_output=True, text=True, encoding="utf-8", errors="replace", creationflags=FLAGS)
    if r.returncode != 0:
        if os.path.exists(tmp):
            os.remove(tmp)
        raise RuntimeError(f"ffmpeg falló: {r.stderr.strip()[-300:]}")
    os.replace(tmp, destino)
    return destino


def convertir(video, destino, cfg, progreso=lambda p: None):
    """Escala, ajusta brillo y funde el final con el inicio para que el bucle no salte.

    Sin B-frames y con el audio del bucle codificado tres veces: loopmp4.repetir()
    usa la copia del medio para que la unión del audio tampoco se note.
    """
    w, h = cfg["resolucion"].split("x")
    fps = cfg["fps"]
    disponible = min(duracion(video) or cfg["max_segundos"], cfg["max_segundos"])
    fundido = min(cfg.get("fundido_segundos", 1.0), disponible / 4)
    p = periodo(fps)
    bucle = (Fraction(disponible - fundido) // p) * p  # duración final, múltiplo exacto
    largo = float(bucle) + fundido
    audio = tiene_audio(video, largo)
    base = (f"scale={w}:{h}:force_original_aspect_ratio=increase:flags=lanczos,"
            f"crop={w}:{h},fps={fps},setsar=1,"
            f"eq=brightness={cfg['brillo']}:saturation={cfg['saturacion']},format=yuv420p")
    # cuerpo = [fundido, largo]; su final se funde con [0, fundido], que es lo que
    # precede al primer cuadro del cuerpo: al repetirse, la unión no se nota
    fc = (f"[0:v]{base},trim=0:{largo},setpts=PTS-STARTPTS,split[a][b];"
          f"[a]trim={fundido}:{largo},setpts=PTS-STARTPTS[cuerpo];"
          f"[b]trim=0:{fundido},setpts=PTS-STARTPTS[cabeza];"
          f"[cuerpo][cabeza]xfade=transition=fade:duration={fundido}:"
          f"offset={largo - 2 * fundido:.6f},format=yuv420p[v]")
    mapas = ["-map", "[v]"]
    if audio:
        # mismo fundido para el audio; luego tres copias seguidas (ver loopmp4)
        fc += (f";[0:a]aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo,"
               f"apad=whole_dur={largo},atrim=0:{largo},asetpts=PTS-STARTPTS,asplit[c][d];"
               f"[c]atrim={fundido}:{largo},asetpts=PTS-STARTPTS[ac];"
               f"[d]atrim=0:{fundido},asetpts=PTS-STARTPTS[ah];"
               f"[ac][ah]acrossfade=d={fundido}:c1=qsin:c2=qsin,asplit=3[a1][a2][a3];"
               f"[a1][a2][a3]concat=n=3:v=0:a=1[au]")
        mapas += ["-map", "[au]", "-c:a", "aac", "-b:a", cfg.get("bitrate_audio", "160k")]
    total = float(bucle)
    tmp = destino + ".part.mp4"
    cmd = [herramienta("ffmpeg"), "-y", "-v", "error", "-i", video,
           "-filter_complex", fc, *mapas,
           "-c:v", "libx264", "-preset", "slow", "-crf", str(cfg.get("crf", 18)),
           "-maxrate", cfg.get("bitrate_max", "10M"), "-bufsize", "20M",
           "-profile:v", "high", "-level", "4.2", "-bf", "0",
           "-g", str(fps), "-x264-params", "open-gop=0",
           "-progress", "pipe:1", "-nostats", tmp]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, encoding="utf-8", errors="replace", creationflags=FLAGS)
    for linea in proc.stdout:
        if linea.startswith("out_time_us=") and total:
            try:
                # con audio, ffmpeg avanza hasta 3 veces el bucle
                progreso(min(99, int(int(linea.split("=")[1]) / 1e6 / (total * (3 if audio else 1)) * 100)))
            except ValueError:
                pass
    err = proc.stderr.read()
    if proc.wait() != 0:
        if os.path.exists(tmp):
            os.remove(tmp)
        raise RuntimeError(f"ffmpeg falló: {err.strip()[-300:]}")
    try:
        # deja una sola vuelta de audio, ya preparada para repetirse
        loopmp4.repetir(tmp, destino, 1, audio_triple=True)
    finally:
        os.remove(tmp)
    progreso(100)
    return destino
