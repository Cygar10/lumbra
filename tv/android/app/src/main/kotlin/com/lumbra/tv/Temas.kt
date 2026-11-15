/*
 * Lumbra — launcher para Android TV basado en FLauncher (GPL-3.0).
 */
package com.lumbra.tv

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Temas de iconos: se descargan del repositorio de Lumbra (carpeta temas/) y quedan en
 * <archivos de la app>/temas/<id>/, con su tema.json y un PNG por app. Las apps que el tema
 * no trae se ven con su logo automático.
 */
object Temas {
    fun carpeta(c: Context) = File(c.getExternalFilesDir(null), "temas")

    private fun leer(dir: File): JSONObject? = try {
        JSONObject(File(dir, "tema.json").readText())
    } catch (_: Exception) {
        null
    }

    /** El tema en uso, o null si se usan los logos automáticos. */
    fun activo(c: Context): JSONObject? {
        val id = Ajustes.texto(c, "tema_iconos").takeIf { it.isNotEmpty() } ?: return null
        return leer(File(carpeta(c), id))
    }

    fun icono(c: Context, paquete: String): File? {
        val id = Ajustes.texto(c, "tema_iconos").takeIf { it.isNotEmpty() } ?: return null
        return File(carpeta(c), "$id/$paquete.png").takeIf { it.isFile }
    }

    private fun instalados(c: Context) = carpeta(c).listFiles { f -> f.isDirectory }.orEmpty()
        .mapNotNull { dir -> leer(dir)?.let { dir.name to it } }.toMap()

    private fun descargarTexto(url: String): String {
        val conexion = URL(url).openConnection() as HttpURLConnection
        conexion.connectTimeout = 8000
        conexion.readTimeout = 15000
        try {
            if (conexion.responseCode != 200) throw RuntimeException("HTTP ${conexion.responseCode}")
            return conexion.inputStream.bufferedReader().readText()
        } finally {
            conexion.disconnect()
        }
    }

    private fun descargarArchivo(url: String, destino: File) {
        val conexion = URL(url).openConnection() as HttpURLConnection
        conexion.connectTimeout = 8000
        conexion.readTimeout = 15000
        try {
            if (conexion.responseCode != 200) throw RuntimeException("HTTP ${conexion.responseCode}")
            conexion.inputStream.use { entrada -> destino.outputStream().use { entrada.copyTo(it) } }
        } finally {
            conexion.disconnect()
        }
    }

    private fun base(c: Context) = Ajustes.texto(c, "temas_url").trimEnd('/') + "/"

    private fun indice(c: Context): JSONArray = JSONObject(descargarTexto(base(c) + "indice.json")).getJSONArray("temas")

    private fun aMapa(t: JSONObject, instalado: Boolean) = mapOf(
        "id" to t.getString("id"),
        "name" to t.optString("nombre", t.getString("id")),
        "description" to t.optString("descripcion"),
        "apps" to (t.optJSONArray("apps")?.length() ?: 0),
        "installed" to instalado,
    )

    /** Los temas del repositorio y los ya descargados. Sin internet, solo los descargados. */
    fun lista(c: Context): Map<String, Any?> {
        val locales = instalados(c)
        return try {
            val remotos = indice(c)
            val lista = (0 until remotos.length()).map { remotos.getJSONObject(it) }
                .map { aMapa(it, it.getString("id") in locales) }
            val soloLocales = locales.filterKeys { id -> lista.none { it["id"] == id } }.map { aMapa(it.value, true) }
            mapOf("themes" to lista + soloLocales, "online" to true)
        } catch (e: Exception) {
            android.util.Log.w("Lumbra", "temas: sin conexión ($e)")
            mapOf("themes" to locales.values.map { aMapa(it, true) }, "online" to false)
        }
    }

    /** Baja todos los iconos del tema a una carpeta aparte y solo al final la pone en su sitio. */
    fun descargar(c: Context, id: String): Boolean {
        val remotos = indice(c)
        val tema = (0 until remotos.length()).map { remotos.getJSONObject(it) }.firstOrNull { it.getString("id") == id }
            ?: return false
        val temporal = File(carpeta(c), ".$id.part").apply { deleteRecursively(); mkdirs() }
        val apps = tema.optJSONArray("apps") ?: JSONArray()
        var bajadas = 0
        for (i in 0 until apps.length()) {
            val paquete = apps.getString(i)
            try {
                descargarArchivo(base(c) + "${tema.getString("carpeta")}/$paquete.png", File(temporal, "$paquete.png"))
                bajadas++
            } catch (e: Exception) {
                android.util.Log.w("Lumbra", "temas: no se bajó $paquete ($e)")
            }
        }
        if (bajadas == 0) {
            temporal.deleteRecursively()
            return false
        }
        File(temporal, "tema.json").writeText(tema.toString())
        val final = File(carpeta(c), id)
        final.deleteRecursively()
        return temporal.renameTo(final)
    }

    fun quitar(c: Context, id: String) {
        File(carpeta(c), id).deleteRecursively()
        if (Ajustes.texto(c, "tema_iconos") == id) Ajustes.guardar(c, "tema_iconos", "")
    }
}
