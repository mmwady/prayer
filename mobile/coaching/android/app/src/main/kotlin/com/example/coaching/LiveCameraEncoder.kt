package com.example.coaching

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.YuvImage
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/** Converts sampled YUV planes off the UI thread; no media is saved to disk. */
class LiveCameraEncoder(private val activity: Activity, messenger: BinaryMessenger) {
    private val executor = Executors.newSingleThreadExecutor()
    private val channel = MethodChannel(messenger, "iqtadi/live_camera")

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "awake" -> {
                    if (call.arguments == true) activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    else activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    result.success(true)
                }
                "encode" -> executor.execute {
                    try {
                        val bytes = encode(call.arguments as Map<*, *>)
                        activity.runOnUiThread { result.success(bytes) }
                    } catch (_: Exception) {
                        activity.runOnUiThread { result.error("CAMERA_ENCODING_FAILED", "تعذر تحويل صورة الكاميرا", null) }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    companion object {
        fun encode(args: Map<*, *>): ByteArray {
            val width = (args["width"] as Number).toInt()
            val height = (args["height"] as Number).toInt()
            val dimension = (args["max_dimension"] as Number).toInt()
            val rotation = (args["rotation"] as Number).toInt()
            require(width in 2..1920 && height in 2..1920 && width % 2 == 0 && height % 2 == 0)
            require(dimension in 1..1920 && rotation in listOf(0, 90, 180, 270))
            val planes = args["planes"] as List<*>
            val nv21 = ByteArray(width * height * 3 / 2)
            if ((args["format"] as Number).toInt() == ImageFormat.NV21 && planes.size == 1) {
                val bytes = (planes[0] as Map<*, *>)["bytes"] as ByteArray
                require(bytes.size >= nv21.size)
                bytes.copyInto(nv21, endIndex = nv21.size)
            } else {
                require(planes.size == 3)
                fun pixel(plane: Map<*, *>, row: Int, col: Int): Byte {
                    val stride = (plane["row_stride"] as Number).toInt()
                    val step = (plane["pixel_stride"] as Number).toInt()
                    return (plane["bytes"] as ByteArray)[row * stride + col * step]
                }
                val y = planes[0] as Map<*, *>
                val u = planes[1] as Map<*, *>
                val v = planes[2] as Map<*, *>
                for (row in 0 until height) for (col in 0 until width) nv21[row * width + col] = pixel(y, row, col)
                var at = width * height
                for (row in 0 until height / 2) for (col in 0 until width / 2) {
                    nv21[at++] = pixel(v, row, col)
                    nv21[at++] = pixel(u, row, col)
                }
            }
            val raw = ByteArrayOutputStream()
            check(YuvImage(nv21, ImageFormat.NV21, width, height, null)
                .compressToJpeg(Rect(0, 0, width, height), 95, raw))
            val source = checkNotNull(BitmapFactory.decodeByteArray(raw.toByteArray(), 0, raw.size()))
            val scale = minOf(1f, dimension.toFloat() / maxOf(width, height))
            val matrix = Matrix().apply { postRotate(rotation.toFloat()); postScale(scale, scale) }
            val normalized = Bitmap.createBitmap(source, 0, 0, width, height, matrix, true)
            return try {
                val output = ByteArrayOutputStream()
                check(normalized.compress(Bitmap.CompressFormat.JPEG, 80, output))
                output.toByteArray()
            } finally {
                if (normalized !== source) normalized.recycle()
                source.recycle()
            }
        }
    }

    fun close() {
        channel.setMethodCallHandler(null)
        activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        executor.shutdown()
    }
}
