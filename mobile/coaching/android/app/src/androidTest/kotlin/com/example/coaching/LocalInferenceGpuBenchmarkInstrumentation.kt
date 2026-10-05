package com.example.coaching

import android.app.Activity
import android.app.Instrumentation
import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import android.view.WindowManager
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

/** Real device, installed-model benchmark. Fixtures/results remain on device or the local host. */
class LocalInferenceGpuBenchmarkInstrumentation : Instrumentation() {
    private var label = "gpu"
    override fun onCreate(arguments: Bundle?) {
        super.onCreate(arguments)
        label = arguments?.getString("label") ?: label
        require(label.matches(Regex("[a-zA-Z0-9_-]+")))
        start()
    }

    override fun onStart() {
        var activity: Activity? = null
        var gpuDetector: PoseLandmarker? = null
        var detectorOwner: Any? = null
        try {
            activity = startActivitySync(Intent().setClassName(targetContext, "com.example.coaching.MainActivity")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            val active = activity
            runOnMainSync { active.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) }
            val engine = activity.javaClass.getDeclaredField("localInference").apply { isAccessible = true }.get(activity)
            val initialize = engine.javaClass.getDeclaredMethod("initialize").apply { isAccessible = true }
            val deferred = label.contains("deferred")
            val analyze = engine.javaClass.getDeclaredMethod(if (deferred) "analyzeDeferred" else "analyze", ByteArray::class.java, Boolean::class.javaPrimitiveType)
                .apply { isAccessible = true }
            val start = SystemClock.elapsedRealtimeNanos()
            val info = initialize.invoke(engine) as Map<*, *>
            if (label.contains("gpu")) {
                // Benchmark-only override: production remains CPU with its original IMAGE semantics.
                gpuDetector = PoseLandmarker.createFromOptions(activity, PoseLandmarker.PoseLandmarkerOptions.builder()
                    .setBaseOptions(BaseOptions.builder().setModelAssetPath("iqtadi/models/pose_landmarker_heavy.task").setDelegate(Delegate.GPU).build())
                    .setRunningMode(RunningMode.IMAGE).setNumPoses(1)
                    .setMinPoseDetectionConfidence(.2f).setMinPosePresenceConfidence(.2f).setMinTrackingConfidence(.2f)
                    .setOutputSegmentationMasks(false).build())
                val field = engine.javaClass.getDeclaredField("detector").apply { isAccessible = true }
                (field.get(engine) as PoseLandmarker).close()
                field.set(engine, gpuDetector)
                detectorOwner = engine
            }
            val initMs = (SystemClock.elapsedRealtimeNanos() - start) / 1e6
            val names = context.assets.list("inference")!!.filter { it.endsWith(".jpg") }.sorted()
            check(names.size >= 100) { "Expected at least 100 real local frames" }
            val folder = targetContext.getExternalFilesDir(null) ?: targetContext.cacheDir
            val file = File(folder, "inference-$label.json")
            file.writeText("{\"status\":\"running\"}", Charsets.UTF_8)
            val warm = context.assets.open("inference/${names.first()}").use { it.readBytes() }
            repeat(3) { analyze.invoke(engine, warm, false) }
            val cases = JSONArray()
            for ((i, name) in names.withIndex()) {
                val bytes = context.assets.open("inference/$name").use { it.readBytes() }
                val before = SystemClock.elapsedRealtimeNanos()
                val answer = analyze.invoke(engine, bytes, true) as Map<*, *>
                val elapsed = (SystemClock.elapsedRealtimeNanos() - before) / 1e6
                val prediction = JSONObject(answer["result"] as Map<*, *>).apply { remove("inference_ms") }
                val previewStart = SystemClock.elapsedRealtimeNanos()
                val preview = if (deferred && answer["preview_token"] != null) {
                    engine.javaClass.getDeclaredMethod("renderPreview", java.lang.Long::class.java).apply { isAccessible = true }
                        .invoke(engine, answer["preview_token"]) as ByteArray
                } else answer["preview_jpeg"] as ByteArray?
                val previewMs = if (deferred) (SystemClock.elapsedRealtimeNanos() - previewStart) / 1e6 else 0.0
                cases.put(JSONObject().put("name", name).put("total_ms", elapsed).put("preview_ms", previewMs)
                    .put("inference_ms", (answer["result"] as Map<*, *>)["inference_ms"])
                    .put("prediction", prediction).put("features", answer["features"]?.let { JSONArray(it as List<*>) })
                    .put("preview_sha256", preview?.let { sha(it) }).put("preview_bytes", preview?.size ?: 0))
                if ((i + 1) % 10 == 0) sendStatus(0, Bundle().apply { putString("stream", "$label: ${i + 1}/${names.size}\n") })
            }
            val result = JSONObject().put("label", label).put("model_version", info["model_version"])
                .put("provider", if (label.contains("gpu")) "gpu" else "cpu")
                .put("device", android.os.Build.MODEL).put("android", android.os.Build.VERSION.RELEASE)
                .put("initialization_ms", initMs).put("cases", cases)
            file.writeText(result.toString(), Charsets.UTF_8)
            finish(Activity.RESULT_OK, Bundle().apply { putString("stream", "PASS: ${names.size} physical-device frames; report=${file.absolutePath}\n") })
        } catch (failure: Throwable) {
            finish(Activity.RESULT_CANCELED, Bundle().apply { putString("stream", "FAIL: ${failure.stackTraceToString()}\n") })
        } finally {
            gpuDetector?.close()
            detectorOwner?.let { it.javaClass.getDeclaredField("detector").apply { isAccessible = true }.set(it, null) }
            activity?.let { runOnMainSync { it.finish() } }
        }
    }

    private fun sha(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes)
        .joinToString("") { "%02x".format(it.toInt() and 255) }
}
