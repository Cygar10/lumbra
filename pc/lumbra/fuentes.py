"""Busca fondos en las carpetas del usuario y, si existe, en Wallpaper Engine."""
import json
import os
import re
import zlib

VIDEOS = {".mp4", ".mkv", ".webm", ".mov", ".m4v", ".avi"}
IMAGENES = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}
WALLPAPER_ENGINE = "431960"  # número de la app en Steam


def _bibliotecas_steam():
    """Carpetas de Steam de este equipo, leyendo dónde lo instaló el usuario."""
    raices = []
    if os.name == "nt":
        try:
            import winreg
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Valve\Steam") as k:
                raices.append(winreg.QueryValueEx(k, "SteamPath")[0])
        except OSError:
            pass
        raices.append(os.path.join(os.environ.get("PROGRAMFILES(X86)", r"C:\Program Files (x86)"), "Steam"))
    else:
        inicio = os.path.expanduser("~")
        raices += [os.path.join(inicio, ".steam", "steam"), os.path.join(inicio, ".local", "share", "Steam"),
                   os.path.join(inicio, "Library", "Application Support", "Steam")]
    bibliotecas = []
    for raiz in raices:
        if not os.path.isdir(raiz):
            continue
        bibliotecas.append(raiz)
        try:
            with open(os.path.join(raiz, "steamapps", "libraryfolders.vdf"), encoding="utf-8", errors="replace") as f:
                bibliotecas += [p.replace("\\\\", "\\") for p in re.findall(r'"path"\s+"([^"]+)"', f.read())]
        except OSError:
            pass
    return list(dict.fromkeys(os.path.normpath(b) for b in bibliotecas))


def detectar_wallpaper_engine():
    """La carpeta de descargas de Wallpaper Engine, o None si no está instalado."""
    for biblioteca in _bibliotecas_steam():
        carpeta = os.path.join(biblioteca, "steamapps", "workshop", "content", WALLPAPER_ENGINE)
        if os.path.isdir(carpeta):
            return carpeta
    return None


def _leer_proyecto(carpeta):
    ruta = os.path.join(carpeta, "project.json")
    if not os.path.isfile(ruta):
        return None
    try:
        with open(ruta, encoding="utf-8-sig") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def _wallpaper_engine(carpeta_raiz):
    if not carpeta_raiz or not os.path.isdir(carpeta_raiz):
        return
    for nombre in os.listdir(carpeta_raiz):
        carpeta = os.path.join(carpeta_raiz, nombre)
        if not nombre.isdigit() or not os.path.isdir(carpeta):
            continue
        p = _leer_proyecto(carpeta)
        if not p or str(p.get("type", "")).lower() != "video":
            continue
        video = os.path.join(carpeta, p.get("file") or "")
        if not os.path.isfile(video):
            continue
        preview = p.get("preview")
        preview = os.path.join(carpeta, preview) if preview else None
        if preview and not os.path.isfile(preview):
            preview = None
        yield {
            "id": nombre,
            "titulo": p.get("title") or nombre,
            "ruta": video,
            "tipo": "video",
            "preview": preview,
            "tamano": os.path.getsize(video),
            "fecha": os.path.getmtime(carpeta),
            "origen": "wallpaper_engine",
        }


def _carpeta_propia(carpeta):
    if not os.path.isdir(carpeta):
        return
    for raiz, _, archivos in os.walk(carpeta):
        for nombre in archivos:
            ext = os.path.splitext(nombre)[1].lower()
            if ext not in VIDEOS and ext not in IMAGENES:
                continue
            ruta = os.path.join(raiz, nombre)
            try:
                info = os.stat(ruta)
            except OSError:
                continue
            es_imagen = ext in IMAGENES
            yield {
                # solo dígitos: el identificador va en las direcciones de la página
                "id": str(zlib.crc32(os.path.normcase(ruta).encode("utf-8"))),
                "titulo": os.path.splitext(nombre)[0],
                "ruta": ruta,
                "tipo": "imagen" if es_imagen else "video",
                "preview": ruta if es_imagen else None,
                "tamano": info.st_size,
                "fecha": info.st_mtime,
                "origen": "carpeta",
            }


def escanear(cfg):
    """Devuelve videos e imágenes de todas las fuentes, del más reciente al más antiguo."""
    items = {}
    if cfg.get("usar_wallpaper_engine", True):
        for i in _wallpaper_engine(cfg.get("wallpaper_engine_dir")):
            items[i["id"]] = i
    for carpeta in cfg.get("carpetas", []):
        for i in _carpeta_propia(carpeta):
            items.setdefault(i["id"], i)
    return sorted(items.values(), key=lambda i: i["fecha"], reverse=True)
