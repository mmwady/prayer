package com.example.coaching

import android.app.Activity
import android.app.Instrumentation
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Bundle
import android.os.SystemClock
import android.util.Log
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.math.abs

/** Dependency-free, real-codec checks. No backend, user videos or network access. */
class ExtractionInstrumentation : Instrumentation() {
    private var onlyClip: String? = null
    override fun onCreate(arguments: Bundle?) {
        super.onCreate(arguments)
        onlyClip = arguments?.getString("clip")
        start()
    }

    override fun onStart() {
        val result = Bundle()
        var activeStatus = Bundle()
        try {
            val lines = mutableListOf<String>()
            val clips = onlyClip?.let { listOf(it) } ?: listOf("landscape.mp4", "portrait90.mp4", "portrait270.mp4",
                    "rotated180.mp4", "lowfps.mp4", "variablefps.mp4", "bframes.mp4")
            for ((index, name) in clips.withIndex()) {
                val status = Bundle().apply {
                    putString("id", "InstrumentationTestRunner")
                    putString("class", "com.example.coaching.ExtractionInstrumentation")
                    putString("test", name)
                    putInt("current", index + 1)
                    putInt("numtests", clips.size + 2)
                }
                activeStatus = status
                sendStatus(1, status)
                val line = checkClip(name)
                Log.i("IqtadiExtractionTest", line)
                lines.add(line)
                status.putString("stream", "$line\n")
                sendStatus(0, status)
            }
            for ((offset, check) in listOf(
                    "retryResize" to ::checkRetryAndResize,
                    "bridgeLifecycle" to ::checkBridgeLifecycle).withIndex()) {
                val status = Bundle().apply {
                    putString("id", "InstrumentationTestRunner")
                    putString("class", "com.example.coaching.ExtractionInstrumentation")
                    putString("test", check.first)
                    putInt("current", clips.size + offset + 1)
                    putInt("numtests", clips.size + 2)
                }
                activeStatus = status
                sendStatus(1, status)
                val line = check.second()
                lines.add(line)
                status.putString("stream", "$line\n")
                sendStatus(0, status)
            }
            result.putString("stream", "\nPASS: real Android extraction checks\n" + lines.joinToString("\n") + "\n")
            finish(Activity.RESULT_OK, result)
        } catch (failure: Throwable) {
            Log.e("IqtadiExtractionTest", "Extraction check failed", failure)
            activeStatus.putString("stack", failure.stackTraceToString())
            sendStatus(-2, activeStatus)
            result.putString("stream", "\nFAIL: ${failure.stackTraceToString()}\n")
            finish(Activity.RESULT_CANCELED, result)
        }
    }

    private fun checkBridgeLifecycle(): String {
        if (targetContext.packageName != "com.example.coaching") {
            return "bridge checks require the app-targeted instrumentation APK"
        }
        val file = fixture("landscape.mp4")
        val activity = startActivitySync(Intent().setClassName(targetContext, "com.example.coaching.MainActivity")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        val clazz = activity.javaClass
        fun set(name: String, value: Any?) {
            clazz.getDeclaredField(name).apply { isAccessible = true }.set(activity, value)
        }
        fun get(name: String): Any? = clazz.getDeclaredField(name).apply { isAccessible = true }.get(activity)
        val extract = clazz.getDeclaredMethod("extractFrame", Long::class.javaPrimitiveType, Int::class.javaPrimitiveType)
            .apply { isAccessible = true }
        val release = clazz.getDeclaredMethod("releaseSequential").apply { isAccessible = true }
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(file.absolutePath)
            set("retriever", retriever)
            set("videoUri", Uri.fromFile(file))
            set("videoWidth", 1920)
            set("videoHeight", 1080)
            set("videoRotation", 0)
            var previousDecoder: Any? = null
            for ((time, size) in listOf(0L to 960, 250L to 960, 500L to 960,
                    0L to 960, 250L to 640)) {
                val frame = extract.invoke(activity, time, size) as Bitmap
                try { check(maxOf(frame.width, frame.height) == size) } finally { frame.recycle() }
                check(get("sequentialDisabled") == false)
                val currentDecoder = checkNotNull(get("sequential"))
                if (time == 0L && previousDecoder != null || size == 640) check(currentDecoder !== previousDecoder)
                if (time > 0 && size == 960) check(currentDecoder === previousDecoder)
                previousDecoder = currentDecoder
                SystemClock.sleep(50) // decoder survives the same pauses as upload batches
            }
            release.invoke(activity)
            set("videoUri", null) // deterministic startup failure: verify compatibility path
            repeat(2) { index ->
                val frame = extract.invoke(activity, index * 250L, 960) as Bitmap
                try { check(maxOf(frame.width, frame.height) == 960) } finally { frame.recycle() }
                check(get("sequentialDisabled") == true && get("sequential") == null)
            }
            return "actual bridge: forward/retry/resize/sticky-retriever-fallback PASS"
        } finally {
            release.invoke(activity)
            set("retriever", null)
            set("videoUri", null)
            retriever.release()
            file.delete()
            runOnMainSync { activity.finish() }
        }
    }

    private fun fixture(name: String): File {
        val file = File(targetContext.cacheDir, "extraction-check-$name")
        context.assets.open(name).use { input -> file.outputStream().use { input.copyTo(it) } }
        return file
    }

    private fun checkClip(name: String): String {
        val file = fixture(name)
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(file.absolutePath)
            val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)!!.toInt()
            val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)!!.toInt()
            val rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)!!.toInt()
            val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)!!.toLong()
            val scale = minOf(1.0, 960.0 / maxOf(width, height))
            val w = maxOf(1, (width * scale).toInt())
            val h = maxOf(1, (height * scale).toInt())
            val times = (0L until duration step 250).toMutableList()
            times.add(0, 0) // repeated timestamp
            times.add(duration - 1) // EOS: nearest last frame
            var worstDifference = 0.0
            var sequentialMs = 0L
            var baselineMs = 0L
            val started = SystemClock.elapsedRealtime()
            val decoder = SequentialVideoDecoder(targetContext, Uri.fromFile(file), width, height, 960, rotation)
            sequentialMs += SystemClock.elapsedRealtime() - started
            decoder.use {
                for (time in times) {
                    val start = SystemClock.elapsedRealtime()
                    val actual = decoder.frame(time)
                    sequentialMs += SystemClock.elapsedRealtime() - start
                    val oldStart = SystemClock.elapsedRealtime()
                    val expected = checkNotNull(retriever.getScaledFrameAtTime(time * 1000,
                        MediaMetadataRetriever.OPTION_CLOSEST, w, h))
                    baselineMs += SystemClock.elapsedRealtime() - oldStart
                    try {
                        check(actual.width == expected.width && actual.height == expected.height) {
                            "$name@$time dimensions ${actual.width}x${actual.height} != ${expected.width}x${expected.height}"
                        }
                        val difference = meanDifference(actual, expected)
                        worstDifference = maxOf(worstDifference, difference)
                        // GPU vs retriever scaling/color conversion need not be byte-identical.
                        // Moving test patterns expose wrong frame, rotation, mirroring and channel order.
                        check(difference < 15.0) { "$name@$time selected_us=${decoder.sampledTimeUs} pixel difference=$difference" }
                        val output = ByteArrayOutputStream()
                        check(actual.compress(Bitmap.CompressFormat.JPEG, 80, output))
                        val bytes = output.toByteArray()
                        check(bytes.size <= 200_000) { "$name JPEG exceeds transport bound" }
                        val jpeg = checkNotNull(BitmapFactory.decodeByteArray(bytes, 0, bytes.size))
                        check(jpeg.width == actual.width && jpeg.height == actual.height)
                        jpeg.recycle()
                    } finally { actual.recycle(); expected.recycle() }
                }
                return "$name samples=${times.size} decoded=${decoder.decodedFrames} " +
                    "sequential_ms=$sequentialMs retriever_ms=$baselineMs max_mean_rgb_difference=$worstDifference"
            }
        } finally { retriever.release(); file.delete() }
    }

    private fun checkRetryAndResize(): String {
        val file = fixture("landscape.mp4")
        try {
            repeat(3) { attempt ->
                val dimension = if (attempt == 1) 640 else 960
                SequentialVideoDecoder(targetContext, Uri.fromFile(file), 1920, 1080, dimension, 0).use { decoder ->
                    for (time in listOf(0L, 250L, 500L)) {
                        val frame = decoder.frame(time)
                        check(maxOf(frame.width, frame.height) == dimension)
                        frame.recycle()
                    }
                } // early close, fresh retry and size change, without decoding remainder
            }
            return "early-close/retry/resize PASS"
        } finally { file.delete() }
    }

    private fun meanDifference(actual: Bitmap, expected: Bitmap): Double {
        var sum = 0L
        var samples = 0
        for (y in 0 until actual.height step 7) {
            for (x in 0 until actual.width step 7) {
                val a = actual.getPixel(x, y)
                val b = expected.getPixel(x, y)
                sum += abs(Color.red(a) - Color.red(b)) + abs(Color.green(a) - Color.green(b)) +
                    abs(Color.blue(a) - Color.blue(b))
                samples++
            }
        }
        return sum.toDouble() / (samples * 3)
    }
}
