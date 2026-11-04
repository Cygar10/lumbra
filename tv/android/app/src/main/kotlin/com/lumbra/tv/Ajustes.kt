/*
 * Lumbra — launcher para Android TV basado en FLauncher (GPL-3.0).
 */
package com.lumbra.tv

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import java.io.File

/**
 * Todos los ajustes del launcher. Viven aquí y no en Flutter porque también los leen el
 * reproductor del fondo, el salvapantallas y las órdenes que llegan desde la PC.
 */
object Ajustes {
    private val VIDEO = setOf("mp4", "mkv", "webm", "mov", "m4v", "avi", "ts")
    private val IMAGEN = setOf("jpg", "jpeg", "png", "webp", "gif", "bmp")

    val PREDETERMINADOS: Map<String, Any> = mapOf(
        "fondo_tipo" to "archivo", // archivo (video o imagen), color o ninguno
        "fondo_ruta" to "",
        "fondo_color" to 0xFF12080A.toInt(),
        "fondo_pausado" to false,
        "fondo_oscurecer" to 0,
        "volumen" to 35,
        "silencio" to false,
        "acento" to 0xFFE50914.toInt(),
        "tarjeta_tam" to "M",
        "tarjeta_forma" to "redondeada",
        "tarjeta_nombres" to "nunca",
        "fila_posicion" to "abajo",
        "enfoque_escala" to true,
        "enfoque_brillo" to true,
        "reloj_visible" to true,
        "reloj_formato" to "12",
        "reloj_fecha" to false,
        "musica_visible" to true,
        "mostrar_ocultas" to false,
        "modo_ligero" to false,
        "abrir_al_encender" to true,
        "salva_motor" to "sistema", // sistema (el de la TV) o lumbra
        "salva_carpeta" to "",
        "salva_segundos" to 15,
        "salva_zoom" to "normal", // no, lento, normal o rapido
        "salva_orden" to "azar", // azar o nombre
        "salva_reloj" to true,
        "salva_minutos" to 15,
    )

    private val LISTAS = setOf("fila", "ocultas")

    var alCambiar: ((String?) -> Unit)? = null

    fun prefs(c: Context): SharedPreferences = c.getSharedPreferences("lumbra", Context.MODE_PRIVATE)

    fun todos(c: Context): Map<String, Any?> {
        val p = prefs(c)
        val datos = HashMap<String, Any?>(PREDETERMINADOS)
        for ((clave, valor) in p.all) datos[clave] = if (valor is Set<*>) null else valor
        // las listas conservan su orden: van separadas por saltos de línea
        for (clave in LISTAS) datos[clave] = p.getString(clave, null)?.split('\n')?.filter { it.isNotEmpty() }
        datos["carpeta_app"] = c.getExternalFilesDir(null)?.absolutePath
        return datos
    }

    fun texto(c: Context, clave: String) = prefs(c).getString(clave, null) ?: PREDETERMINADOS[clave] as String
    fun entero(c: Context, clave: String) = prefs(c).getInt(clave, PREDETERMINADOS[clave] as Int)
    fun logico(c: Context, clave: String) = prefs(c).getBoolean(clave, PREDETERMINADOS[clave] as Boolean)

    fun guardar(c: Context, clave: String, valor: Any?) {
        prefs(c).edit().apply {
            when {
                valor == null -> remove(clave)
                clave in LISTAS -> putString(clave, (valor as List<*>).joinToString("\n"))
                valor is Boolean -> putBoolean(clave, valor)
                valor is Int -> putInt(clave, valor)
                valor is Long -> putInt(clave, valor.toInt())
                else -> putString(clave, valor.toString())
            }
        }.apply()
    }

    fun restablecer(c: Context) {
        // el archivo de fondo, las apps, el salvapantallas y el arranque no son apariencia: se conservan
        val e = prefs(c).edit()
        for (clave in PREDETERMINADOS.keys) {
            if (clave != "fondo_ruta" && clave != "abrir_al_encender" && !clave.startsWith("salva_")) e.remove(clave)
        }
        e.apply()
    }

    fun extension(ruta: String) = ruta.substringAfterLast('.', "").lowercase()
    fun esVideo(ruta: String) = extension(ruta) in VIDEO
    fun esImagen(ruta: String) = extension(ruta) in IMAGEN

    /** La carpeta de fotos elegida o, si no hay, la que usa la PC para mandarlas. */
    fun carpetaSalva(c: Context): File {
        val elegida = texto(c, "salva_carpeta")
        return if (elegida.isNotEmpty()) File(elegida) else File(c.getExternalFilesDir(null), "salvapantallas")
    }
}

/**
 * Órdenes desde la PC por ADB:
 *   am broadcast -n com.lumbra.tv/.ControlReceiver -a com.lumbra.tv.FONDO --es ruta /ruta/al/archivo
 *   am broadcast -n com.lumbra.tv/.ControlReceiver -a com.lumbra.tv.VOLUMEN --ei volumen 40 --ez silencio false
 *   am broadcast -n com.lumbra.tv/.ControlReceiver -a com.lumbra.tv.FILA --es paquetes a,b,c
 *   am broadcast -n com.lumbra.tv/.ControlReceiver -a com.lumbra.tv.AJUSTE --es clave salva_motor --es valor lumbra
 */
class ControlReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            "com.lumbra.tv.FONDO" -> intent.getStringExtra("ruta")?.let {
                Ajustes.guardar(context, "fondo_ruta", it)
                Ajustes.guardar(context, "fondo_tipo", "archivo")
            }
            "com.lumbra.tv.VOLUMEN" -> {
                Ajustes.guardar(context, "volumen", intent.getIntExtra("volumen", Ajustes.entero(context, "volumen")).coerceIn(0, 100))
                Ajustes.guardar(context, "silencio", intent.getBooleanExtra("silencio", Ajustes.logico(context, "silencio")))
            }
            "com.lumbra.tv.FILA" -> intent.getStringExtra("paquetes")?.let {
                Ajustes.guardar(context, "fila", it.split(',').filter(String::isNotBlank))
            }
            "com.lumbra.tv.AJUSTE" -> {
                val clave = intent.getStringExtra("clave")?.takeIf { it in Ajustes.PREDETERMINADOS } ?: return
                val valor = intent.extras?.get("valor") ?: return
                Ajustes.guardar(context, clave, valor)
            }
            else -> return
        }
        Ajustes.alCambiar?.invoke(null)
    }
}
