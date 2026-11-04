"""Control de la TV por ADB: instalar Lumbra, poner fondos y mandar fotos."""
import os
import re
import shutil
import subprocess
import time

FLAGS = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
LUMBRA = "com.lumbra.tv"
CARPETA_APP = f"/sdcard/Android/data/{LUMBRA}/files"
CARPETA_VISTA = "/sdcard/Movies/Lumbra"


def encontrar_adb():
    """Lo busca en el PATH y en los sitios donde lo dejan el SDK de Android y los instaladores."""
    ruta = shutil.which("adb")
    if ruta:
        return ruta
    exe = "adb.exe" if os.name == "nt" else "adb"
    inicio = os.path.expanduser("~")
    posibles = [os.environ.get("ANDROID_HOME"), os.environ.get("ANDROID_SDK_ROOT"),
                os.path.join(os.environ.get("LOCALAPPDATA", ""), "Android", "Sdk"),
                r"C:\Android\Sdk", os.path.join(inicio, "Android", "Sdk"),
                os.path.join(inicio, "Library", "Android", "sdk")]
    for base in posibles:
        if base and os.path.isfile(os.path.join(base, "platform-tools", exe)):
            return os.path.join(base, "platform-tools", exe)
    return None


class TV:
    def __init__(self, cfg):
        self.cfg = cfg
        self.serial = cfg.get("tv_address") or None
        self.adb = encontrar_adb()

    def _run(self, *args, timeout=60, serial=True):
        if not self.adb:
            raise RuntimeError("Falta ADB (Android platform-tools). Instálalo y vuelve a abrir Lumbra: "
                               "https://developer.android.com/tools/releases/platform-tools")
        cmd = [self.adb] + (["-s", self.serial] if serial and self.serial else []) + list(args)
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout,
                           encoding="utf-8", errors="replace", creationflags=FLAGS)
        return r.returncode, (r.stdout + r.stderr).strip()

    def shell(self, comando, timeout=60):
        code, out = self._run("shell", comando, timeout=timeout)
        if code != 0:
            raise RuntimeError(out or f"falló: {comando}")
        return out

    def conectada(self):
        if not self.serial:
            return False
        try:
            code, out = self._run("get-state", timeout=10)
        except (subprocess.TimeoutExpired, RuntimeError):
            return False
        return code == 0 and out.strip() == "device"

    def conectar(self, direccion=None):
        """Prueba la dirección dada, la guardada y las TV que se anuncian en la red."""
        candidatas = [d for d in (direccion, self.serial) if d]
        ip = (direccion or self.serial or "").split(":")[0]
        if ip:
            candidatas.append(f"{ip}:5555")
        _, mdns = self._run("mdns", "services", serial=False, timeout=10)
        candidatas += re.findall(r"_adb-tls-connect\S*\s+(\d+\.\d+\.\d+\.\d+:\d+)", mdns)
        for d in dict.fromkeys(candidatas):
            self._run("connect", d, serial=False, timeout=10)
            self.serial = d
            if self.conectada():
                return d
        self.serial = None
        return None

    def emparejar(self, direccion, codigo):
        """La primera vez, Android TV pide autorizar la PC con un código de 6 dígitos."""
        _, out = self._run("pair", direccion, codigo, serial=False, timeout=30)
        return "Successfully paired" in out, out

    def fijar_puerto(self):
        """Deja ADB escuchando en 5555 hasta que la TV se reinicie."""
        self._run("tcpip", "5555", timeout=15)
        time.sleep(3)
        return self.conectar(f"{self.serial.split(':')[0]}:5555")

    def hay_lumbra(self):
        code, out = self._run("shell", f"pm path {LUMBRA}", timeout=15)
        return code == 0 and "package:" in out

    def preparar_lumbra(self, apk=None, paso=lambda m: None):
        """Instala el launcher si hace falta y le da lo que la TV no deja dar desde sus menús."""
        if apk:
            paso("Instalando Lumbra en la TV…")
            code, out = self._run("install", "-r", apk, timeout=300)
            if code != 0:
                raise RuntimeError(out)
        if not self.hay_lumbra():
            raise RuntimeError("Lumbra no está instalado en la TV")
        paso("Dándole los permisos a Lumbra…")
        for orden in (f"cmd notification allow_listener {LUMBRA}/.MediaListener",
                      f"pm grant {LUMBRA} android.permission.WRITE_SECURE_SETTINGS",
                      f"pm grant {LUMBRA} android.permission.READ_MEDIA_IMAGES",
                      f"pm grant {LUMBRA} android.permission.READ_MEDIA_VIDEO",
                      f"cmd package set-home-activity {LUMBRA}/.MainActivity"):
            # alguna TV rechaza una de estas órdenes: no impide usar el launcher
            self._run("shell", orden, timeout=20)

    def _avisar(self, accion, extras):
        self.shell(f"am broadcast -n {LUMBRA}/.ControlReceiver -a {LUMBRA}.{accion} {extras}")

    def _subir(self, local, destino, paso):
        paso("Mandando «{t}» a la TV ({mb} MB)…")
        self.shell(f"mkdir -p '{os.path.dirname(destino).replace(os.sep, '/')}'")
        code, out = self._run("push", local, destino, timeout=900)
        if code != 0:
            raise RuntimeError(out)

    def poner_fondo(self, local, item_id, paso):
        if not self.hay_lumbra():
            raise RuntimeError("Lumbra no está instalado en la TV. Usa «Instalar en la TV».")
        ext = os.path.splitext(local)[1].lower()
        nombre = f"fondo_{item_id}{ext}"
        destino = f"{CARPETA_APP}/{nombre}"
        self._subir(local, destino, paso)
        paso("Poniendo «{t}» de fondo…")
        self._avisar("FONDO", f"--es ruta {destino}")
        for f in self.shell(f"ls {CARPETA_APP}").split():
            if f.startswith("fondo_") and f != nombre:
                self.shell(f"rm -f '{CARPETA_APP}/{f}'")

    def enviar_a_salvapantallas(self, local, item_id, paso):
        if not self.hay_lumbra():
            raise RuntimeError("Lumbra no está instalado en la TV. Usa «Instalar en la TV».")
        self._subir(local, f"{CARPETA_APP}/salvapantallas/{item_id}{os.path.splitext(local)[1].lower()}", paso)

    def ver(self, local, paso):
        destino = f"{CARPETA_VISTA}/vista_previa.mp4"
        self._subir(local, destino, paso)
        paso("Abriendo «{t}» en la TV…")
        self.shell(f"am start -a android.intent.action.VIEW -d file://{destino} -t video/mp4")

    def cerrar_vista(self):
        self.shell("input keyevent KEYCODE_HOME")
        time.sleep(1)
        self.shell(f"rm -f {CARPETA_VISTA}/vista_previa.mp4")

    def resolucion_recomendada(self):
        """1080p si la TV da para ello; en las de poca memoria, 720p para que vaya fluido."""
        try:
            pantalla = re.search(r"Physical size: (\d+)x(\d+)", self.shell("wm size"))
            memoria = int(re.search(r"MemTotal:\s+(\d+)", self.shell("cat /proc/meminfo")).group(1))
        except (RuntimeError, AttributeError):
            return "1280x720"
        ancho = int(pantalla.group(1)) if pantalla else 1920
        return "1280x720" if memoria < 1_500_000 or ancho < 1920 else "1920x1080"
