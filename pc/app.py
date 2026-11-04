"""Lumbra para PC: galería local de fondos para el launcher de la TV.

Abre http://localhost:8770 , elige un video o una imagen y mándalo a la TV. Es opcional: el
launcher funciona solo, con los archivos de la TV. Las conversiones se guardan en datos/cache/.
"""
import glob
import json
import mimetypes
import os
import queue
import shutil
import subprocess
import sys
import threading
import time
import webbrowser
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from lumbra import convert, fuentes
from lumbra.tv import TV

BASE = os.path.dirname(os.path.abspath(__file__))
DATOS = os.environ.get("LUMBRA_DATOS") or os.path.join(BASE, "datos")
CACHE = os.path.join(DATOS, "cache")
ESTADO_PATH = os.path.join(DATOS, "estado.json")
CONFIG_PATH = os.path.join(DATOS, "config.json")
os.makedirs(CACHE, exist_ok=True)

PREDETERMINADO = {
    "carpetas": [],
    "usar_wallpaper_engine": True,
    "wallpaper_engine_dir": None,
    "tv_address": None,
    "port": 8770,
    "resolucion": "auto",
    "brillo": 0.0,
    "saturacion": 1.0,
    "max_segundos": 60,
    "fundido_segundos": 1.0,
    "fps": 30,
    "crf": 20,
    "bitrate_max": "10M",
    "revisar_cada_segundos": 30,
}


def cargar_config():
    """Lo único que se configura es lo que no se puede averiguar solo."""
    try:
        with open(CONFIG_PATH, encoding="utf-8") as f:
            guardado = json.load(f)
    except (OSError, ValueError):
        guardado = {}
    # configuraciones anteriores del proyecto
    if "workshop_dir" in guardado:
        guardado.setdefault("wallpaper_engine_dir", guardado.pop("workshop_dir"))
    cfg = {**PREDETERMINADO, **guardado}
    if not (cfg["wallpaper_engine_dir"] and os.path.isdir(cfg["wallpaper_engine_dir"])):
        cfg["wallpaper_engine_dir"] = fuentes.detectar_wallpaper_engine()
    return cfg


CFG = cargar_config()


def guardar_config():
    with open(CONFIG_PATH, "w", encoding="utf-8") as f:
        json.dump(CFG, f, indent=2, ensure_ascii=False)


def recordar_tv(direccion):
    """Guarda la dirección que funcionó para usarla al volver a abrir el programa."""
    CFG["tv_address"] = direccion
    guardar_config()


def cargar_estado():
    try:
        with open(ESTADO_PATH, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {"vistos": None, "actual": None, "automatico": False}


ESTADO = cargar_estado()
LOCK = threading.Lock()
TRABAJOS = queue.Queue()
ACTIVIDAD = {"mensaje": "Listo", "id": None, "progreso": None, "error": None,
             "ocupado": False, "n": 0}
tv = TV(CFG)


def guardar_estado():
    with LOCK:
        with open(ESTADO_PATH, "w", encoding="utf-8") as f:
            json.dump(ESTADO, f, indent=2)


def avisar(mensaje, item_id=None, progreso=None, error=None):
    ACTIVIDAD.update(mensaje=mensaje, id=item_id, progreso=progreso, error=error,
                     n=ACTIVIDAD["n"] + 1)


def items_por_id():
    return {i["id"]: i for i in fuentes.escanear(CFG)}


def ajustes_conversion():
    """La resolución «auto» se decide según la TV conectada."""
    if CFG["resolucion"] != "auto":
        return CFG
    return {**CFG, "resolucion": tv.resolucion_recomendada() if tv.conectada() else "1280x720"}


def preparar(item):
    """Devuelve la versión para TV, convirtiéndola solo si no está en caché."""
    if item["tipo"] == "imagen":
        destino = os.path.join(CACHE, f"{item['id']}.jpg")
        if not os.path.isfile(destino):
            avisar(f"Preparando «{item['titulo']}»", item["id"])
            convert.imagen(item["ruta"], destino, ajustes_conversion())
        return destino
    bucle = convert.ruta_bucle(CACHE, item["id"])
    if not os.path.isfile(bucle):
        convert.convertir(item["ruta"], bucle, ajustes_conversion(),
                          lambda p: avisar(f"Convirtiendo «{item['titulo']}»", item["id"], p))
    return bucle


def foto_salvapantallas(ruta, item_id):
    destino = os.path.join(CACHE, f"{item_id}_hd.jpg")
    if not os.path.isfile(destino):
        convert.foto_hd(ruta, destino)
    return destino


def subir_fotos(rutas):
    """Manda varias fotos al salvapantallas en HD. Una foto dañada no detiene las demás."""
    asegurar_tv()
    subidas, pequenas, fallidas = 0, 0, 0
    for n, ruta in enumerate(rutas, 1):
        avisar(f"Subiendo foto {n} de {len(rutas)} al salvapantallas…")
        item_id = str(zlib.crc32(os.path.abspath(ruta).encode("utf-8")))
        try:
            pequenas += convert.es_menor_que_hd(ruta)
            tv.enviar_a_salvapantallas(foto_salvapantallas(ruta, item_id), item_id, lambda m: None)
            subidas += 1
        except (RuntimeError, OSError):
            fallidas += 1
    mensaje = f"{subidas} fotos en HD añadidas al salvapantallas"
    if pequenas:
        mensaje += f". {pequenas} miden menos de 1080p y no se verán tan nítidas"
    if fallidas:
        mensaje += f". {fallidas} no se pudieron subir"
    avisar(mensaje)


def en_cache(item):
    if item["tipo"] == "imagen":
        return os.path.isfile(os.path.join(CACHE, f"{item['id']}.jpg"))
    return os.path.isfile(convert.ruta_bucle(CACHE, item["id"]))


def asegurar_tv():
    if tv.conectada():
        return
    avisar("Buscando la TV…")
    if not tv.conectar():
        raise RuntimeError("No encuentro la TV. Conéctala arriba con la IP y el puerto de "
                           "«Depuración inalámbrica».")
    recordar_tv(tv.serial)


def apk_incluido():
    """El APK que venga junto al programa (descargado o recién compilado)."""
    raiz = os.path.dirname(BASE)
    for patron in (os.path.join(raiz, "lumbra*.apk"), os.path.join(BASE, "lumbra*.apk"),
                   os.path.join(raiz, "tv", "build", "app", "outputs", "flutter-apk", "app-release.apk")):
        hallados = sorted(glob.glob(patron), key=os.path.getmtime, reverse=True)
        if hallados:
            return hallados[0]
    return None


def trabajador():
    while True:
        accion, item_id = TRABAJOS.get()
        ACTIVIDAD["ocupado"] = True
        try:
            if accion == "cerrar":
                asegurar_tv()
                tv.cerrar_vista()
                avisar("Vista previa cerrada")
                continue
            if accion == "instalar":
                asegurar_tv()
                tv.preparar_lumbra(apk_incluido(), avisar)
                avisar("Lumbra quedó listo en la TV")
                continue
            if accion == "subir_fotos":
                subir_fotos(item_id)
                continue
            if accion == "volumen":
                asegurar_tv()
                tv._avisar("VOLUMEN", f"--ei volumen {item_id} --ez silencio {'true' if item_id == 0 else 'false'}")
                ESTADO["volumen"] = item_id
                guardar_estado()
                avisar(f"Volumen del fondo en {item_id} %")
                continue
            item = items_por_id().get(item_id)
            if not item:
                raise RuntimeError("Ese archivo ya no está en tus carpetas")
            if accion == "salva" and item["tipo"] != "imagen":
                raise RuntimeError("El salvapantallas solo usa fotos")
            local = foto_salvapantallas(item["ruta"], item_id) if accion == "salva" else preparar(item)
            asegurar_tv()
            mb = max(1, round(os.path.getsize(local) / 1e6))
            paso = lambda m: avisar(m.format(t=item["titulo"], mb=mb), item_id)
            if accion == "fondo":
                tv.poner_fondo(local, item_id, paso)
                ESTADO["actual"] = item_id
                guardar_estado()
                avisar(f"«{item['titulo']}» es tu fondo ahora", item_id)
            elif accion == "salva":
                tv.enviar_a_salvapantallas(local, item_id, paso)
                avisar(f"«{item['titulo']}» se añadió al salvapantallas", item_id)
            elif accion == "ver":
                if item["tipo"] != "video":
                    raise RuntimeError("La vista previa es solo para videos")
                tv.ver(local, paso)
                avisar(f"Reproduciendo «{item['titulo']}» en la TV", item_id)
        except Exception as e:  # el error se muestra en la página
            avisar("Error", item_id, error=str(e))
        finally:
            ACTIVIDAD["ocupado"] = not TRABAJOS.empty()
            TRABAJOS.task_done()


def vigilante():
    """Modo automático: pone de fondo cada video nuevo cuando termina de descargarse."""
    tamanos = {}
    while True:
        try:
            actuales = items_por_id()
            if ESTADO["vistos"] is None:  # primera vez: lo que ya existe no cuenta como nuevo
                ESTADO["vistos"] = list(actuales)
                guardar_estado()
            for item_id, item in actuales.items():
                if item_id in ESTADO["vistos"]:
                    continue
                # espera a que el tamaño no cambie entre dos revisiones (descarga completa)
                if tamanos.get(item_id) != item["tamano"]:
                    tamanos[item_id] = item["tamano"]
                    continue
                ESTADO["vistos"].append(item_id)
                guardar_estado()
                if ESTADO["automatico"]:
                    TRABAJOS.put(("fondo", item_id))
        except Exception as e:
            avisar("Error revisando tus carpetas", error=str(e))
        time.sleep(CFG["revisar_cada_segundos"])


_tv_vista = {"hora": 0.0, "conectada": False}


def tv_conectada():
    """La página pregunta cada poco: a ADB solo se le consulta cada 10 segundos."""
    if time.monotonic() - _tv_vista["hora"] > 10:
        _tv_vista.update(hora=time.monotonic(), conectada=tv.conectada())
    return _tv_vista["conectada"]


def elegir_carpeta():
    return _selector("print(d.askdirectory(title='Carpeta con videos o fotos'))")


def elegir_fotos():
    tipos = "[('Fotos','*.jpg *.jpeg *.png *.webp *.bmp')]"
    return (_selector(f"print(chr(10).join(d.askopenfilenames(title='Fotos para el salvapantallas',filetypes={tipos})))") or "").splitlines()


def _selector(orden):
    """Abre el selector de archivos del sistema, en otro proceso para no trabar el servidor."""
    codigo = f"import tkinter as t, tkinter.filedialog as d;r=t.Tk();r.withdraw();r.attributes('-topmost',True);{orden}"
    try:
        r = subprocess.run([sys.executable, "-c", codigo], capture_output=True, text=True, timeout=600,
                           encoding="utf-8", errors="replace")
    except (OSError, subprocess.TimeoutExpired):
        return None
    return r.stdout.strip() or None


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _json(self, data, code=200):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _archivo(self, ruta, tipo=None):
        if not ruta or not os.path.isfile(ruta):
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", tipo or mimetypes.guess_type(ruta)[0] or "application/octet-stream")
        self.send_header("Content-Length", str(os.path.getsize(ruta)))
        self.send_header("Cache-Control", "no-cache" if ruta.endswith(".html") else "max-age=3600")
        self.end_headers()
        with open(ruta, "rb") as f:
            while chunk := f.read(1 << 16):
                self.wfile.write(chunk)

    def do_GET(self):
        partes = self.path.split("?")[0].strip("/").split("/")
        if partes == [""]:
            self._archivo(os.path.join(BASE, "web", "index.html"), "text/html; charset=utf-8")
        elif partes == ["api", "items"]:
            lista = []
            ocultos = ESTADO.setdefault("ocultos", [])
            for i in fuentes.escanear(CFG):
                if i["id"] in ocultos:
                    continue
                lista.append({"id": i["id"], "titulo": i["titulo"], "tipo": i["tipo"],
                              "origen": i["origen"],
                              "mb": round(i["tamano"] / 1e6),
                              "preview": bool(i["preview"]),
                              "cache": en_cache(i),
                              "actual": i["id"] == ESTADO["actual"]})
            self._json(lista)
        elif partes == ["api", "estado"]:
            presentes = items_por_id()
            self._json({**ACTIVIDAD, "automatico": ESTADO["automatico"],
                        "ocultos": sum(1 for i in ESTADO.get("ocultos", []) if i in presentes),
                        "volumen": ESTADO.get("volumen", 0),
                        "tv": tv.serial if tv_conectada() else None, "pendientes": TRABAJOS.qsize(),
                        "adb": bool(tv.adb), "ffmpeg": bool(shutil.which("ffmpeg")),
                        "apk": bool(apk_incluido())})
        elif partes == ["api", "fuentes"]:
            self._json({"carpetas": CFG["carpetas"], "wallpaper_engine_dir": CFG["wallpaper_engine_dir"],
                        "usar_wallpaper_engine": CFG["usar_wallpaper_engine"], "resolucion": CFG["resolucion"]})
        elif len(partes) == 2 and partes[0] == "preview" and partes[1].isdigit():
            item = items_por_id().get(partes[1])
            self._archivo(item and item["preview"])
        else:
            self.send_error(404)

    def do_POST(self):
        largo = int(self.headers.get("Content-Length") or 0)
        datos = json.loads(self.rfile.read(largo) or b"{}")
        partes = self.path.strip("/").split("/")
        if len(partes) == 3 and partes[0] == "api" and partes[1] in ("fondo", "ver", "salva") and partes[2].isdigit():
            TRABAJOS.put((partes[1], partes[2]))
            self._json({"ok": True})
        elif len(partes) == 3 and partes[:2] == ["api", "eliminar"] and partes[2].isdigit():
            # se quita de la galería y se borra su conversión; el original no se toca
            ocultos = ESTADO.setdefault("ocultos", [])
            if partes[2] not in ocultos:
                ocultos.append(partes[2])
            bucle = convert.ruta_bucle(CACHE, partes[2])
            if os.path.isfile(bucle):
                os.remove(bucle)
            mensaje = "Quitado de la galería"
            item = items_por_id().get(partes[2])
            if datos.get("borrar_pc") and item and item["origen"] == "wallpaper_engine":
                # Steam no siempre borra la carpeta al desuscribirse; aquí se borra a mano
                carpeta = os.path.join(CFG["wallpaper_engine_dir"], partes[2])
                if os.path.isdir(carpeta):
                    shutil.rmtree(carpeta, ignore_errors=True)
                ocultos.remove(partes[2])
                mensaje = "Wallpaper borrado de la PC"
            guardar_estado()
            avisar(mensaje)
            self._json({"ok": True})
        elif partes == ["api", "restaurar"]:
            ESTADO["ocultos"] = []
            guardar_estado()
            avisar("Se restauró todo lo que habías quitado")
            self._json({"ok": True})
        elif partes == ["api", "cerrar"]:
            TRABAJOS.put(("cerrar", None))
            self._json({"ok": True})
        elif partes == ["api", "instalar"]:
            TRABAJOS.put(("instalar", None))
            self._json({"ok": True})
        elif partes == ["api", "volumen"]:
            valor = max(0, min(100, round(int(datos.get("valor", 0)) / 5) * 5))
            TRABAJOS.put(("volumen", valor))
            self._json({"ok": True})
        elif partes == ["api", "automatico"]:
            ESTADO["automatico"] = bool(datos.get("activo"))
            guardar_estado()
            self._json({"ok": True})
        elif partes == ["api", "salva", "subir"]:
            rutas = [r for r in (datos.get("rutas") or elegir_fotos()) if os.path.isfile(r)]
            if rutas:
                TRABAJOS.put(("subir_fotos", rutas))
            self._json({"ok": bool(rutas), "fotos": len(rutas)})
        elif partes == ["api", "carpeta", "agregar"]:
            carpeta = (datos.get("ruta") or "").strip() or elegir_carpeta()
            if carpeta and os.path.isdir(carpeta) and carpeta not in CFG["carpetas"]:
                CFG["carpetas"].append(carpeta)
                guardar_config()
            self._json({"ok": bool(carpeta) and os.path.isdir(carpeta or ""), "carpetas": CFG["carpetas"]})
        elif partes == ["api", "carpeta", "quitar"]:
            if datos.get("ruta") in CFG["carpetas"]:
                CFG["carpetas"].remove(datos["ruta"])
                guardar_config()
            self._json({"ok": True, "carpetas": CFG["carpetas"]})
        elif partes == ["api", "opciones"]:
            if "usar_wallpaper_engine" in datos:
                CFG["usar_wallpaper_engine"] = bool(datos["usar_wallpaper_engine"])
            if datos.get("resolucion") in ("auto", "1280x720", "1920x1080"):
                CFG["resolucion"] = datos["resolucion"]
            guardar_config()
            self._json({"ok": True})
        elif partes == ["api", "emparejar"]:
            ok, salida = tv.emparejar((datos.get("direccion") or "").strip(), (datos.get("codigo") or "").strip())
            self._json({"ok": ok, "mensaje": salida})
        elif partes == ["api", "conectar"]:
            direccion = (datos.get("direccion") or "").strip()
            if direccion and ":" not in direccion:
                direccion += ":5555"
            d = tv.conectar(direccion or None)
            if d:
                recordar_tv(d)
            self._json({"ok": bool(d), "tv": d})
        elif partes == ["api", "fijar-puerto"]:
            d = tv.fijar_puerto() if tv.conectada() else None
            if d:
                recordar_tv(d)
            self._json({"ok": bool(d), "tv": d})
        else:
            self.send_error(404)


def main():
    url = f"http://localhost:{CFG['port']}"
    # en Windows, reuse_address deja que dos copias usen el mismo puerto y respondan al azar
    ThreadingHTTPServer.allow_reuse_address = os.name != "nt"
    try:
        servidor = ThreadingHTTPServer(("127.0.0.1", CFG["port"]), Handler)
    except OSError:
        print(f"Lumbra ya está abierto en otra ventana: {url}")
        webbrowser.open(url)
        return
    threading.Thread(target=trabajador, daemon=True).start()
    threading.Thread(target=vigilante, daemon=True).start()
    print(f"Lumbra listo en {url}  (cierra esta ventana para detenerlo)")
    if os.environ.get("LUMBRA_NO_BROWSER") != "1":
        webbrowser.open(url)
    servidor.serve_forever()


if __name__ == "__main__":
    main()
