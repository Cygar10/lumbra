"""Encuentra ADB y FFmpeg en el equipo y, en Windows, los descarga si faltan.

Así quien baja Lumbra no tiene que instalar nada a mano: se guardan en la carpeta de datos del
programa, sin tocar el resto del sistema.
"""
import glob
import os
import shutil
import urllib.request
import zipfile

# de dónde se bajan (sitios oficiales) y qué archivos del zip hacen falta
DESCARGAS = {
    "adb": ("https://dl.google.com/android/repository/platform-tools-latest-windows.zip",
            {"adb.exe", "adbwinapi.dll", "adbwinusbapi.dll"}),
    "ffmpeg": ("https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip",
               {"ffmpeg.exe", "ffprobe.exe"}),
}
NOMBRES = {"adb": "ADB", "ffmpeg": "FFmpeg"}

CARPETA = None  # la fija app.py: <datos>/herramientas
_halladas = {}


def _candidatas(nombre):
    exe = nombre + (".exe" if os.name == "nt" else "")
    if CARPETA:
        yield os.path.join(CARPETA, exe)
    inicio = os.path.expanduser("~")
    local = os.environ.get("LOCALAPPDATA", "")
    if nombre == "adb":
        for base in (os.environ.get("ANDROID_HOME"), os.environ.get("ANDROID_SDK_ROOT"),
                     os.path.join(local, "Android", "Sdk"), r"C:\Android\Sdk",
                     os.path.join(inicio, "Android", "Sdk"), os.path.join(inicio, "Library", "Android", "sdk")):
            if base:
                yield os.path.join(base, "platform-tools", exe)
    # instalados con winget: el PATH de un programa ya abierto no se entera hasta reiniciar la sesión
    if local:
        winget = os.path.join(local, "Microsoft", "WinGet")
        yield os.path.join(winget, "Links", exe)
        yield from glob.glob(os.path.join(winget, "Packages", "*", "*", "bin", exe))


def buscar(nombre):
    """Ruta del programa (adb, ffmpeg o ffprobe) o None si no está en el equipo."""
    ruta = _halladas.get(nombre)
    if ruta and os.path.isfile(ruta):
        return ruta
    ruta = shutil.which(nombre) or next((c for c in _candidatas(nombre) if os.path.isfile(c)), None)
    if ruta:
        _halladas[nombre] = ruta
    return ruta


def faltan():
    return [n for n in ("adb", "ffmpeg") if not buscar(n)]


def se_pueden_descargar():
    return os.name == "nt"


def descargar(nombre, progreso=lambda p: None):
    """Baja el zip oficial y saca solo los ejecutables que se usan."""
    if not se_pueden_descargar():
        raise RuntimeError(f"Instala {NOMBRES[nombre]} con el gestor de paquetes de tu sistema")
    url, necesarios = DESCARGAS[nombre]
    os.makedirs(CARPETA, exist_ok=True)
    zip_tmp = os.path.join(CARPETA, nombre + ".zip.part")
    try:
        pedido = urllib.request.Request(url, headers={"User-Agent": "Lumbra"})
        with urllib.request.urlopen(pedido, timeout=30) as r, open(zip_tmp, "wb") as f:
            total = int(r.headers.get("Content-Length") or 0)
            hecho = 0
            while trozo := r.read(1 << 18):
                f.write(trozo)
                hecho += len(trozo)
                if total:
                    progreso(min(99, hecho * 100 // total))
        with zipfile.ZipFile(zip_tmp) as z:
            for info in z.infolist():
                base = os.path.basename(info.filename)
                if base.lower() in necesarios:
                    with z.open(info) as origen, open(os.path.join(CARPETA, base), "wb") as destino:
                        shutil.copyfileobj(origen, destino)
    except OSError as e:
        raise RuntimeError(f"No se pudo descargar {NOMBRES[nombre]}: {e}") from e
    finally:
        if os.path.exists(zip_tmp):
            os.remove(zip_tmp)
    _halladas.pop(nombre, None)
    if not buscar(nombre):
        raise RuntimeError(f"La descarga de {NOMBRES[nombre]} no traía lo esperado")
