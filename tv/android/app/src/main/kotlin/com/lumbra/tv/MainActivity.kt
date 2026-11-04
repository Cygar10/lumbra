/*
 * Lumbra — launcher para Android TV basado en FLauncher (GPL-3.0).
 * La parte de listar y abrir apps viene de FLauncher, Copyright (C) 2021 Étienne Fesser.
 */
package com.lumbra.tv

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.Intent.*
import android.content.pm.ActivityInfo
import android.content.pm.LauncherApps
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.AdaptiveIconDrawable
import android.graphics.drawable.Drawable
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.UserHandle
import android.os.storage.StorageManager
import android.provider.Settings
import android.util.DisplayMetrics
import android.view.SurfaceView
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

private const val METODOS = "lumbra/method"
private const val EVENTOS_APPS = "lumbra/apps"
private const val EVENTOS_ESTADO = "lumbra/state"
private const val PEDIR_MEDIOS = 7

class MainActivity : FlutterActivity() {
    private lateinit var video: WallpaperPlayer
    private lateinit var fondo: Fondo
    private lateinit var musica: MediaWatcher
    private val main = Handler(Looper.getMainLooper())
    private var estado: EventChannel.EventSink? = null
    private var ultimaMusica: Map<String, Any?>? = null
    private var appsCallback: LauncherApps.Callback? = null
    private var redCallback: ConnectivityManager.NetworkCallback? = null

    // Flutter se dibuja transparente encima del video (que va en un SurfaceView debajo)
    // (con fondo transparente Flutter usa un TextureView; probado: un SurfaceView propio es peor
    // en esta TV, porque con tres capas el hardware ya no las combina y lo hace la GPU)
    override fun getBackgroundMode() = BackgroundMode.transparent

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Encendido.escucharPantalla(this)
        val contenido = findViewById<ViewGroup>(android.R.id.content)
        val surface = SurfaceView(this).apply {
            layoutParams = FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            setZOrderOnTop(false)
        }
        // imagen de fondo o cuadro fijo del video: va entre el video y la interfaz
        val cuadro = ImageView(this).apply {
            layoutParams = FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            scaleType = ImageView.ScaleType.CENTER_CROP
        }
        contenido.addView(surface, 0)
        contenido.addView(cuadro, 1)
        window.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(android.graphics.Color.BLACK))
        video = WallpaperPlayer(this, surface)
        fondo = Fondo(this, cuadro, video)
        musica = MediaWatcher(this) { datos ->
            ultimaMusica = datos
            video.otraMusicaSonando(musica.hayMusica())
            enviar(mapOf("type" to "media", "media" to datos))
        }
        Ajustes.alCambiar = {
            main.post {
                if (enFrente) fondo.mostrar()
                aplicarMotorSalva()
                enviarAjustes()
            }
        }
    }

    private var enFrente = false

    override fun onResume() {
        super.onResume()
        enFrente = true
        fondo.mostrar()
        musica.iniciar()
        vigilarRed()
        reiniciarEspera()
    }

    override fun onPause() {
        // antes que nada: la app que se abre no debe oír el fondo ni un momento
        enFrente = false
        fondo.silenciar()
        main.removeCallbacks(abrirSalva)
        musica.detener()
        redCallback?.let { (getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager).unregisterNetworkCallback(it) }
        redCallback = null
        super.onPause()
    }

    override fun onStop() {
        fondo.soltar()
        if (Encendido.debeRecuperarFrente()) main.postDelayed({ Encendido.abrirInicio(this, "otra app nos tapó al arrancar") }, 300)
        super.onStop()
    }

    override fun onDestroy() {
        Ajustes.alCambiar = null
        fondo.cerrar()
        appsCallback?.let { (getSystemService(LAUNCHER_APPS_SERVICE) as LauncherApps).unregisterCallback(it) }
        super.onDestroy()
    }

    // ---- salvapantallas ----

    private val componenteSalva get() = ComponentName(this, SalvaService::class.java).flattenToString()

    private fun puedeElegirSalva() =
        checkSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS) == PackageManager.PERMISSION_GRANTED

    private fun salvaActivoEnSistema() =
        Settings.Secure.getString(contentResolver, "screensaver_components") == componenteSalva

    /** Deja a Android usando el salvapantallas elegido, si la PC nos dio ese permiso. */
    private fun aplicarMotorSalva() {
        if (!puedeElegirSalva()) return
        val p = Ajustes.prefs(this)
        val actual = Settings.Secure.getString(contentResolver, "screensaver_components")
        if (Ajustes.texto(this, "salva_motor") == "lumbra") {
            if (actual != componenteSalva) {
                p.edit().putString("salva_anterior", actual).apply()
                Settings.Secure.putString(contentResolver, "screensaver_components", componenteSalva)
            }
        } else if (actual == componenteSalva) {
            p.getString("salva_anterior", null)?.let {
                Settings.Secure.putString(contentResolver, "screensaver_components", it)
            }
        }
    }

    // en las TV sin salvapantallas elegible, lo abre el propio launcher tras un rato sin tocar nada
    private val abrirSalva = Runnable { abrir(Intent(this, SalvaActivity::class.java)) }

    private fun reiniciarEspera() {
        main.removeCallbacks(abrirSalva)
        if (!enFrente || Ajustes.texto(this, "salva_motor") != "lumbra" || salvaActivoEnSistema()) return
        main.postDelayed(abrirSalva, Ajustes.entero(this, "salva_minutos") * 60_000L)
    }

    override fun onUserInteraction() {
        super.onUserInteraction()
        Encendido.dejarDeVigilar()
        reiniciarEspera()
    }

    // ---- archivos de la TV ----

    private var pedidoPermiso: MethodChannel.Result? = null

    private val permisosMedios
        get() = if (Build.VERSION.SDK_INT >= 33) {
            arrayOf(Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VIDEO)
        } else {
            arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }

    private fun tienePermisoMedios() = permisosMedios.all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PEDIR_MEDIOS) {
            pedidoPermiso?.success(tienePermisoMedios())
            pedidoPermiso = null
        }
    }

    /** Almacenamiento interno y memorias USB. */
    private fun raices(): List<Map<String, Any?>> {
        val gestor = getSystemService(STORAGE_SERVICE) as StorageManager
        return gestor.storageVolumes.mapNotNull { v ->
            val carpeta = v.directory ?: return@mapNotNull null
            if (v.state != Environment.MEDIA_MOUNTED) return@mapNotNull null
            mapOf("name" to v.getDescription(this), "path" to carpeta.absolutePath)
        }
    }

    private fun listar(ruta: String) = File(ruta).listFiles().orEmpty()
        .filter { !it.name.startsWith(".") && (it.isDirectory || Ajustes.esImagen(it.name) || Ajustes.esVideo(it.name)) }
        .sortedWith(compareBy<File>({ !it.isDirectory }, { it.name.lowercase() }))
        .map {
            mapOf(
                "name" to it.name,
                "path" to it.absolutePath,
                "kind" to if (it.isDirectory) "dir" else if (Ajustes.esVideo(it.name)) "video" else "image",
            )
        }

    // HOME estando ya en el launcher: Flutter vuelve al inicio de la fila
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.hasCategory(CATEGORY_HOME)) enviar(mapOf("type" to "home"))
    }

    private fun enviar(evento: Map<String, Any?>) = main.post { estado?.success(evento) }

    private fun enviarAjustes() = enviar(mapOf("type" to "settings", "settings" to Ajustes.todos(this)))

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val mensajero = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(mensajero, METODOS).setMethodCallHandler { call, result ->
            when (call.method) {
                "getApplications" -> Thread {
                    val apps = getApplications()
                    main.post { result.success(apps) }
                }.start()
                "launchApp" -> result.success(launchApp(call.arguments as String))
                "getSettings" -> result.success(Ajustes.todos(this))
                "setSetting" -> {
                    val clave = call.argument<String>("key")!!
                    Ajustes.guardar(this, clave, call.argument<Any?>("value"))
                    // solo lo que afecta al fondo: cada tecla en los ajustes no debe tocar el reproductor
                    if (enFrente && (clave.startsWith("fondo_") || clave == "modo_ligero")) fondo.mostrar()
                    if (clave == "salva_motor") aplicarMotorSalva()
                    reiniciarEspera()
                    result.success(true)
                }
                "resetSettings" -> {
                    Ajustes.restablecer(this)
                    aplicarMotorSalva()
                    if (enFrente) fondo.mostrar()
                    result.success(Ajustes.todos(this))
                }
                "requestMediaPermission" -> {
                    if (tienePermisoMedios()) {
                        result.success(true)
                    } else {
                        pedidoPermiso?.success(false)
                        pedidoPermiso = result
                        requestPermissions(permisosMedios, PEDIR_MEDIOS)
                    }
                }
                "storageRoots" -> result.success(raices())
                "listDir" -> Thread {
                    val lista = try {
                        listar(call.arguments as String)
                    } catch (e: Exception) {
                        emptyList()
                    }
                    main.post { result.success(lista) }
                }.start()
                "screensaverInfo" -> result.success(mapOf(
                    "canChoose" to puedeElegirSalva(),
                    "activeInSystem" to salvaActivoEnSistema(),
                    "photos" to Ajustes.carpetaSalva(this).listFiles { f -> Ajustes.esImagen(f.name) }.orEmpty().size,
                ))
                "testScreensaver" -> result.success(abrir(Intent(this, SalvaActivity::class.java)))
                "openDreamSettings" -> result.success(
                    abrirFuera(Intent(Settings.ACTION_DREAM_SETTINGS)) || abrirFuera(Intent(Settings.ACTION_SETTINGS)))
                "openSettings" -> result.success(abrirFuera(Intent(Settings.ACTION_SETTINGS)))
                "openWifiSettings" -> result.success(abrir(Intent(Settings.ACTION_WIFI_SETTINGS)) || abrir(Intent(Settings.ACTION_SETTINGS)))
                "openAppInfo" -> result.success(abrir(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    .setData(Uri.fromParts("package", call.arguments as String, null))))
                "openMedia" -> {
                    musica.abrir(call.arguments as String)
                    result.success(true)
                }
                "mediaControl" -> {
                    musica.control(call.argument<String>("package")!!, call.argument<String>("action")!!)
                    result.success(true)
                }
                "setVolume" -> {
                    val volumen = call.argument<Int>("volume")!!
                    val silencio = call.argument<Boolean>("muted")!!
                    Ajustes.guardar(this, "volumen", volumen.coerceIn(0, 100))
                    Ajustes.guardar(this, "silencio", silencio)
                    video.ponerVolumen(volumen / 100f, silencio)
                    result.success(true)
                }
                "getMedia" -> result.success(ultimaMusica)
                "isDefaultLauncher" -> result.success(
                    packageManager.resolveActivity(Intent(ACTION_MAIN).addCategory(CATEGORY_HOME), 0)
                        ?.activityInfo?.packageName == packageName)
                else -> result.notImplemented()
            }
        }

        EventChannel(mensajero, EVENTOS_ESTADO).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                estado = events
                enviarAjustes()
                enviar(mapOf("type" to "media", "media" to ultimaMusica))
                enviarRed()
            }

            override fun onCancel(arguments: Any?) {
                estado = null
            }
        })

        EventChannel(mensajero, EVENTOS_APPS).setStreamHandler(object : EventChannel.StreamHandler {
            val launcherApps = getSystemService(LAUNCHER_APPS_SERVICE) as LauncherApps
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                val cb = object : LauncherApps.Callback() {
                    fun avisar() = main.post { events.success("changed") }
                    override fun onPackageRemoved(packageName: String, user: UserHandle) = avisar().let { }
                    override fun onPackageAdded(packageName: String, user: UserHandle) = avisar().let { }
                    override fun onPackageChanged(packageName: String, user: UserHandle) = avisar().let { }
                    override fun onPackagesAvailable(p: Array<out String>, user: UserHandle, r: Boolean) = avisar().let { }
                    override fun onPackagesUnavailable(p: Array<out String>, user: UserHandle, r: Boolean) = avisar().let { }
                }
                appsCallback = cb
                launcherApps.registerCallback(cb)
            }

            override fun onCancel(arguments: Any?) {
                appsCallback?.let(launcherApps::unregisterCallback)
                appsCallback = null
            }
        })
    }

    // ---- red (icono de wifi) ----

    private fun vigilarRed() {
        val cm = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = enviarRed()
            override fun onLost(network: Network) = enviarRed()
            override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) = enviarRed()
        }
        try {
            cm.registerDefaultNetworkCallback(cb)
            redCallback = cb
        } catch (_: Exception) {
        }
        enviarRed()
    }

    private fun enviarRed() {
        val cm = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
        val caps = cm.getNetworkCapabilities(cm.activeNetwork)
        val tipo = when {
            caps == null -> "none"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            else -> "other"
        }
        var nivel = 0
        if (tipo == "wifi") {
            @Suppress("DEPRECATION")
            val rssi = (applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager).connectionInfo.rssi
            @Suppress("DEPRECATION")
            nivel = WifiManager.calculateSignalLevel(rssi, 4)
        }
        enviar(mapOf("type" to "network", "kind" to tipo, "level" to nivel))
    }

    // ---- apps (de FLauncher) ----

    private fun getApplications(): List<Map<String, Any?>> {
        val tv = consultar(CATEGORY_LEANBACK_LAUNCHER)
        val otras = consultar(CATEGORY_LAUNCHER).filter { o -> tv.none { it.packageName == o.packageName } }
        return (tv + otras).filter { it.packageName != packageName }.map(::datosApp)
    }

    private fun consultar(categoria: String) = packageManager
        .queryIntentActivities(Intent(ACTION_MAIN, null).addCategory(categoria), 0)
        .map { it.activityInfo }

    private val nombres by lazy { getSharedPreferences("nombres", MODE_PRIVATE) }

    private fun datosApp(info: ActivityInfo): Map<String, Any?> {
        val version = try {
            packageManager.getPackageInfo(info.packageName, 0).lastUpdateTime
        } catch (_: Exception) {
            0L
        }
        // el nombre también se guarda: leerlo obliga a abrir los recursos de cada app (~120 ms cada una)
        // (con el idioma en la clave, por si se cambia el de la TV)
        val clave = "${info.packageName}/${info.name}/${java.util.Locale.getDefault().toLanguageTag()}"
        val nombre = nombres.getString(clave, null)?.takeIf { it.startsWith("$version|") }?.substringAfter('|')
            ?: info.loadLabel(packageManager).toString().also { nombres.edit().putString(clave, "$version|$it").apply() }
        val datos = mutableMapOf<String, Any?>(
            "name" to nombre,
            "packageName" to info.packageName,
        )
        File(getExternalFilesDir("iconos"), "${info.packageName}.png").takeIf { it.isFile }?.let {
            datos["custom"] = it.readBytes()
            return datos
        }
        // el logo ya procesado se guarda: dibujar y comprimir todos los iconos tarda ~20 s en esta TV
        val cache = File(cacheDir, "logos3/${info.packageName}_$version.png")
        if (!cache.isFile) {
            cache.parentFile?.mkdirs()
            cache.parentFile?.listFiles { f -> f.name.startsWith(info.packageName + "_") }?.forEach { it.delete() }
            val logo = iconoGrande(info)?.let(::soloLogo) ?: return datos
            cache.outputStream().use { logo.compress(Bitmap.CompressFormat.PNG, 100, it) }
        }
        datos["logo"] = cache.readBytes()
        return datos
    }

    /**
     * Deja solo el logo, sin el cuadro de color de la app, y del mismo tamaño en todas,
     * para que las tarjetas tengan el mismo fondo del tema.
     */
    private fun soloLogo(icono: Drawable): Bitmap? {
        if (icono is AdaptiveIconDrawable && icono.foreground != null) {
            // la capa frontal ya es solo el logo; algunas traen además un cuadro blanco
            val frente = aBitmap(icono.foreground, 256)
            return quitarFondo(frente, soloBlanco = true) ?: centrar(frente) ?: aBitmap(icono, 256)
        }
        val original = aBitmap(icono, 256)
        val logo = quitarFondo(original)
        // si lo que queda es oscuro (p. ej. barras negras de Spotify) no se vería sobre la tarjeta
        return if (logo != null && luminancia(logo) > 55) logo else centrar(original, 0.62f) ?: original
    }

    /** Borra el color de fondo del icono (rellenando desde los bordes) y centra el logo. */
    private fun quitarFondo(bmp: Bitmap, soloBlanco: Boolean = false): Bitmap? {
        val w = bmp.width
        val h = bmp.height
        val px = IntArray(w * h)
        bmp.getPixels(px, 0, w, 0, 0, w, h)
        // color de fondo: el primero opaco entrando desde la mitad de cada lado
        // (muchos iconos tienen margen transparente y esquinas redondas)
        fun haciaDentro(x0: Int, y0: Int, dx: Int, dy: Int): Int? {
            var x = x0
            var y = y0
            while (x in 0 until w && y in 0 until h && kotlin.math.abs(x - x0) + kotlin.math.abs(y - y0) < w / 3) {
                if ((px[y * w + x] ushr 24) > 220) return y * w + x
                x += dx
                y += dy
            }
            return null
        }
        val puntos = listOf(
            haciaDentro(w / 2, 0, 0, 1), haciaDentro(w / 2, h - 1, 0, -1),
            haciaDentro(0, h / 2, 1, 0), haciaDentro(w - 1, h / 2, -1, 0),
        )
        if (puntos.any { it == null }) return null
        // se mete un poco más para no tomar el borde suavizado
        val muestras = puntos.map { px[it!!] }
        val fondo = muestras[0]
        if (muestras.any { distancia(it, fondo) > 60 }) return null
        if (soloBlanco && distancia(fondo, -1) > 40) return null
        val visto = BooleanArray(w * h)
        val pila = ArrayDeque<Int>()
        for (x in 0 until w) { pila.add(x); pila.add((h - 1) * w + x) }
        for (y in 0 until h) { pila.add(y * w); pila.add(y * w + w - 1) }
        puntos.forEach { pila.add(it!!) }
        while (pila.isNotEmpty()) {
            val i = pila.removeLast()
            if (visto[i]) continue
            visto[i] = true
            val c = px[i]
            if ((c ushr 24) >= 40 && distancia(c, fondo) > 70) continue
            px[i] = 0
            val x = i % w
            val y = i / w
            if (x > 0) pila.add(i - 1)
            if (x < w - 1) pila.add(i + 1)
            if (y > 0) pila.add(i - w)
            if (y < h - 1) pila.add(i + w)
        }
        return centrar(Bitmap.createBitmap(px, w, h, Bitmap.Config.ARGB_8888))
    }

    /** Recorta lo transparente y deja el contenido centrado ocupando `tamano` del lado. */
    private fun centrar(bmp: Bitmap, tamano: Float = 0.56f): Bitmap? {
        val w = bmp.width
        val h = bmp.height
        val px = IntArray(w * h)
        bmp.getPixels(px, 0, w, 0, 0, w, h)
        var x0 = w
        var y0 = h
        var x1 = -1
        var y1 = -1
        for (y in 0 until h) for (x in 0 until w) if ((px[y * w + x] ushr 24) > 30) {
            if (x < x0) x0 = x
            if (x > x1) x1 = x
            if (y < y0) y0 = y
            if (y > y1) y1 = y
        }
        if (x1 < x0 || (x1 - x0) * (y1 - y0) < w * h / 60) return null
        val recorte = Bitmap.createBitmap(bmp, x0, y0, x1 - x0 + 1, y1 - y0 + 1)
        val salida = Bitmap.createBitmap(256, 256, Bitmap.Config.ARGB_8888)
        val escala = 256 * tamano / maxOf(recorte.width, recorte.height)
        val dw = recorte.width * escala
        val dh = recorte.height * escala
        Canvas(salida).drawBitmap(
            recorte, null,
            android.graphics.RectF((256 - dw) / 2, (256 - dh) / 2, (256 + dw) / 2, (256 + dh) / 2),
            android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG or android.graphics.Paint.ANTI_ALIAS_FLAG),
        )
        return salida
    }

    /** Brillo medio de las partes visibles (0–255). */
    private fun luminancia(bmp: Bitmap): Int {
        val px = IntArray(bmp.width * bmp.height)
        bmp.getPixels(px, 0, bmp.width, 0, 0, bmp.width, bmp.height)
        var suma = 0.0
        var peso = 0.0
        for (c in px) {
            val a = (c ushr 24) / 255.0
            if (a < .1) continue
            suma += a * (0.299 * ((c shr 16) and 255) + 0.587 * ((c shr 8) and 255) + 0.114 * (c and 255))
            peso += a
        }
        return if (peso == 0.0) 0 else (suma / peso).toInt()
    }

    private fun distancia(a: Int, b: Int): Int {
        val dr = ((a shr 16) and 255) - ((b shr 16) and 255)
        val dg = ((a shr 8) and 255) - ((b shr 8) and 255)
        val db = (a and 255) - (b and 255)
        return kotlin.math.sqrt((dr * dr + dg * dg + db * db).toDouble()).toInt()
    }

    /** El icono a la máxima resolución disponible: los de densidad normal se ven borrosos en la TV. */
    private fun iconoGrande(info: ActivityInfo): Drawable? {
        val recurso = info.iconResource.takeIf { it != 0 } ?: info.applicationInfo.icon
        if (recurso != 0) {
            try {
                return packageManager.getResourcesForApplication(info.applicationInfo)
                    .getDrawableForDensity(recurso, DisplayMetrics.DENSITY_XXXHIGH, null)
            } catch (_: Exception) {
            }
        }
        return info.loadIcon(packageManager)
    }

    private fun aBitmap(drawable: Drawable, lado: Int): Bitmap {
        val bitmap = Bitmap.createBitmap(lado, lado, Bitmap.Config.ARGB_8888)
        drawable.setBounds(0, 0, lado, lado)
        drawable.draw(Canvas(bitmap))
        return bitmap
    }

    private fun launchApp(paquete: String): Boolean {
        val intent = packageManager.getLeanbackLaunchIntentForPackage(paquete)
            ?: packageManager.getLaunchIntentForPackage(paquete)
        return abrirFuera(intent)
    }

    private fun abrirFuera(intent: Intent?): Boolean {
        // callado desde ya, y el decodificador y la memoria quedan libres para la app que se abre
        fondo.silenciar()
        val abierta = abrir(intent)
        if (abierta) main.post { fondo.soltar() } else fondo.mostrar()
        return abierta
    }

    private fun abrir(intent: Intent?) = try {
        intent?.let { startActivity(it); true } ?: false
    } catch (e: Exception) {
        false
    }
}
