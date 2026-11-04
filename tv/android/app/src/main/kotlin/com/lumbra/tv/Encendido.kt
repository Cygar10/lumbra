/*
 * Lumbra — launcher para Android TV basado en FLauncher (GPL-3.0).
 */
package com.lumbra.tv

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.SystemClock
import android.util.Log

/**
 * Hace que la TV siempre encienda en el launcher. Muchas TV abren su app de entradas al arrancar
 * (de ahí el «sin señal»), aunque Lumbra sea la pantalla de inicio.
 */
object Encendido {
    private const val TAG = "Lumbra"

    // esas apps pueden terminar de abrirse después que nosotros: durante este rato se recupera el frente
    private const val VIGILANCIA_MS = 30_000L

    private var vigilarHasta = 0L
    private var receptor: BroadcastReceiver? = null

    fun alArrancar(c: Context) {
        if (!Ajustes.logico(c, "abrir_al_encender")) return
        vigilarHasta = SystemClock.elapsedRealtime() + VIGILANCIA_MS
        abrirInicio(c, "arranque")
    }

    fun abrirInicio(c: Context, motivo: String) {
        Log.i(TAG, "Abriendo el inicio: $motivo")
        try {
            c.startActivity(Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
                setPackage(c.packageName)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
            })
        } catch (e: Exception) {
            Log.w(TAG, "No se pudo abrir el inicio", e)
        }
    }

    /** Otra pantalla nos tapó justo tras arrancar y nadie pulsó nada. */
    fun debeRecuperarFrente() = SystemClock.elapsedRealtime() < vigilarHasta

    /** El usuario ya está usando la TV: lo que abra desde ahora es decisión suya. */
    fun dejarDeVigilar() {
        vigilarHasta = 0
    }

    /** Al salir de reposo no hay arranque: la TV vuelve a lo último que tenía abierto. */
    fun escucharPantalla(c: Context) {
        if (receptor != null) return
        val app = c.applicationContext
        receptor = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (Ajustes.logico(app, "abrir_al_encender")) abrirInicio(app, "salió de reposo")
            }
        }
        app.registerReceiver(receptor, IntentFilter(Intent.ACTION_SCREEN_ON))
    }
}

class ArranqueReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) Encendido.alArrancar(context)
    }
}
