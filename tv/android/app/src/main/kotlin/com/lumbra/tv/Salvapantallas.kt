/*
 * Lumbra — launcher para Android TV basado en FLauncher (GPL-3.0).
 */
package com.lumbra.tv

import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Typeface
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.service.dreams.DreamService
import android.util.TypedValue
import android.view.Choreographer
import android.view.Gravity
import android.view.KeyEvent
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextClock
import java.io.File
import java.util.concurrent.Executors

/**
 * Pasa las fotos de una carpeta con fundidos y un zoom lento.
 *
 * Se dibuja en un SurfaceView propio a la resolución real del panel: muchas TV de poca memoria
 * dibujan su interfaz a 720p aunque el panel sea 1080p, y las fotos se verían blandas. El zoom va
 * con coordenadas decimales y la foto ya viene a ese tamaño, así que no hay saltos de píxel.
 * Solo hay dos fotos en memoria (unos 16 MB a 1080p).
 */
class VistaSalvapantallas(context: Context) : FrameLayout(context), SurfaceHolder.Callback, Choreographer.FrameCallback {
    private class Foto(val imagen: Bitmap, val inicio: Long, val duracion: Long, val desde: Float, val hasta: Float, val lado: Float)

    private val main = Handler(Looper.getMainLooper())
    private val hilo = Executors.newSingleThreadExecutor()
    private val lienzo = SurfaceView(context)
    private val tamano = tamanoReal()
    private val matriz = Matrix()
    private val pincel = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)
    private var entra: Foto? = null
    private var sale: Foto? = null
    private var inicioFundido = 0L
    private var fotos = listOf<File>()
    private var indice = 0
    private var serie = 0
    private var activa = false
    private var hayLienzo = false
    private var enCola = false
    private var fallos = 0

    private val segundos = Ajustes.entero(context, "salva_segundos").coerceIn(5, 3600)
    private val velocidad = when (Ajustes.texto(context, "salva_zoom")) {
        "no" -> 0f
        "lento" -> ZOOM_NORMAL * .6f
        "rapido" -> ZOOM_NORMAL * 1.4f
        else -> ZOOM_NORMAL
    }

    init {
        setBackgroundColor(Color.BLACK)
        lienzo.holder.setFixedSize(tamano.first, tamano.second)
        lienzo.holder.addCallback(this)
        addView(lienzo, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        if (Ajustes.logico(context, "salva_reloj")) addView(reloj(), LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
            gravity = Gravity.BOTTOM or Gravity.END
            val margen = (resources.displayMetrics.density * 36).toInt()
            setMargins(margen, margen, margen, margen)
        })
    }

    /** El tamaño del panel, no el de la interfaz. Hasta 1080p: más gastaría memoria sin que se note. */
    @Suppress("DEPRECATION")
    private fun tamanoReal(): Pair<Int, Int> {
        val modo = (context.getSystemService(Context.WINDOW_SERVICE) as WindowManager).defaultDisplay.mode
        val w = modo.physicalWidth
        val h = modo.physicalHeight
        return if (w > 1920) Pair(1920, h * 1920 / w) else Pair(w, h)
    }

    private fun reloj() = TextClock(context).apply {
        val formato = if (Ajustes.texto(context, "reloj_formato") == "24") "H:mm" else "h:mm a"
        format12Hour = formato
        format24Hour = formato
        setTextColor(Color.WHITE)
        setTextSize(TypedValue.COMPLEX_UNIT_PX, resources.displayMetrics.heightPixels * .06f)
        typeface = Typeface.create("sans-serif-light", Typeface.NORMAL)
        setShadowLayer(14f, 0f, 2f, 0xCC000000.toInt())
    }

    fun iniciar() {
        activa = true
        hilo.execute {
            val carpeta = Ajustes.carpetaSalva(context)
            val halladas = carpeta.listFiles { f -> f.isFile && Ajustes.esImagen(f.name) }?.toList().orEmpty()
            // sin fotos todavía: se usa la imagen de fondo, si la hay; si no, queda la hora sobre negro
            val fondo = File(Ajustes.texto(context, "fondo_ruta")).takeIf { it.isFile && Ajustes.esImagen(it.name) }
            val orden = when {
                halladas.isEmpty() -> listOfNotNull(fondo)
                Ajustes.texto(context, "salva_orden") == "nombre" -> halladas.sortedBy { it.name }
                else -> halladas.shuffled()
            }
            main.post {
                fotos = orden
                siguiente()
            }
        }
    }

    fun detener() {
        activa = false
        serie++
        main.removeCallbacksAndMessages(null)
        Choreographer.getInstance().removeFrameCallback(this)
        enCola = false
        hilo.shutdownNow()
        entra = null
        sale = null
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        hayLienzo = true
        pedirCuadro()
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) = pedirCuadro()

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        hayLienzo = false
    }

    private fun siguiente() {
        if (!activa || fotos.isEmpty()) return
        val foto = fotos[indice % fotos.size]
        val numero = indice++
        val mia = ++serie
        hilo.execute {
            val imagen = try {
                Imagenes.leer(foto.path, tamano.first, tamano.second)
            } catch (e: Exception) {
                android.util.Log.w("Lumbra", "salvapantallas: no se pudo leer $foto: $e")
                null
            } catch (e: OutOfMemoryError) {
                null
            }
            main.post {
                if (!activa || mia != serie) return@post
                if (imagen == null) {
                    // una foto dañada no detiene la presentación; si ninguna sirve, se queda la hora
                    if (++fallos < fotos.size) main.post { siguiente() }
                    return@post
                }
                fallos = 0
                mostrar(imagen, numero)
            }
        }
    }

    /** Alterna acercar y alejar, con un desplazamiento lateral muy suave en algunas fotos. */
    private fun mostrar(imagen: Bitmap, numero: Int) {
        val total = segundos * 1000L + FUNDIDO_MS * 2
        val cambio = velocidad * total / 1000f
        val acercar = numero % 2 == 0
        val lado = when (numero % 3) {
            1 -> 1f
            2 -> -1f
            else -> 0f
        }
        // la foto que se va sigue moviéndose durante el fundido
        val ahora = SystemClock.uptimeMillis()
        sale = entra
        entra = Foto(imagen, ahora, total, if (acercar) 1f else 1f + cambio, if (acercar) 1f + cambio else 1f, lado)
        inicioFundido = ahora
        pedirCuadro()
        main.postDelayed({ siguiente() }, segundos * 1000L)
    }

    private fun pedirCuadro() {
        if (enCola || !activa) return
        enCola = true
        Choreographer.getInstance().postFrameCallback(this)
    }

    override fun doFrame(frameTimeNanos: Long) {
        enCola = false
        if (!activa || !hayLienzo) return
        val ahora = SystemClock.uptimeMillis()
        val avance = ((ahora - inicioFundido).toFloat() / FUNDIDO_MS).coerceIn(0f, 1f)
        if (avance >= 1f) sale = null
        val superficie = lienzo.holder.surface
        val canvas = try {
            superficie.lockHardwareCanvas()
        } catch (e: RuntimeException) {
            pedirCuadro()
            return
        }
        canvas.drawColor(Color.BLACK)
        sale?.let { dibujar(canvas, it, ahora, 255) }
        entra?.let { dibujar(canvas, it, ahora, (avance * 255).toInt()) }
        superficie.unlockCanvasAndPost(canvas)
        // sin zoom y sin fundido no cambia nada: no hace falta gastar GPU
        if (velocidad != 0f || sale != null) pedirCuadro()
    }

    private fun dibujar(canvas: Canvas, foto: Foto, ahora: Long, alfa: Int) {
        val t = ((ahora - foto.inicio).toFloat() / foto.duracion).coerceIn(0f, 1f)
        val escala = foto.desde + (foto.hasta - foto.desde) * t
        val ancho = tamano.first.toFloat()
        matriz.setScale(escala, escala, ancho / 2, tamano.second / 2f)
        // nunca se sale del borde de la foto: se mueve solo lo que sobra por el zoom
        matriz.postTranslate(foto.lado * (escala - 1f) * ancho * .5f, 0f)
        pincel.alpha = alfa
        canvas.drawBitmap(foto.imagen, matriz, pincel)
    }

    private companion object {
        // 0.25 % por segundo: con 15 s por foto no llega al 5 %, y la foto se sigue viendo entera
        const val ZOOM_NORMAL = .0025f
        const val FUNDIDO_MS = 2000L
    }
}

/** El salvapantallas de Lumbra tal como lo ve Android: se elige en los ajustes de la TV. */
class SalvaService : DreamService() {
    private var vista: VistaSalvapantallas? = null

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        isFullscreen = true
        isInteractive = false
        vista = VistaSalvapantallas(this).also { setContentView(it) }
    }

    override fun onDreamingStarted() {
        super.onDreamingStarted()
        vista?.iniciar()
    }

    override fun onDreamingStopped() {
        vista?.detener()
        super.onDreamingStopped()
    }
}

/** El mismo salvapantallas para las TV que no dejan elegir uno, y para el botón «Probar». */
class SalvaActivity : Activity() {
    private lateinit var vista: VistaSalvapantallas

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        vista = VistaSalvapantallas(this)
        setContentView(vista)
    }

    override fun onStart() {
        super.onStart()
        vista.iniciar()
    }

    override fun onStop() {
        vista.detener()
        super.onStop()
        finish()
    }

    // cualquier botón cierra, sin hacer además lo que ese botón hace en el launcher
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_UP) finish()
        return true
    }
}
