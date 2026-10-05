package com.example.coaching

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.SystemClock
import androidx.exifinterface.media.ExifInterface
import androidx.annotation.Keep
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.FloatBuffer
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** No networking: all assets are installed in the APK and all inference runs on one background thread. */
class LocalInferenceChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "iqtadi/local_inference")
    private val executor = Executors.newSingleThreadExecutor()
    private val busy = AtomicBoolean(false)
    private var closed = false
    @Keep private var detector: PoseLandmarker? = null
    private val sessions = mutableListOf<OrtSession>()
    private var mean = floatArrayOf()
    private var std = floatArrayOf()
    private var modelVersion = ""
    private val assetRoot = "iqtadi/models/"
    private data class PendingPreview(val token: Long, val image: LocalInferenceImage.Rgb, val points: List<LocalInferenceMath.Landmark>)
    private var pendingPreview: PendingPreview? = null
    private var previewSequence = 0L
    private data class PendingExport(val json: String, val result: MethodChannel.Result)
    private var pendingExport: PendingExport? = null

    init { channel.setMethodCallHandler(::handle) }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize", "analyze", "preview" -> {
                if (closed) { result.error("LOCAL_ENGINE_CLOSED", "المحلل المحلي مغلق", null); return }
                if (!busy.compareAndSet(false, true)) { result.error("LOCAL_INFERENCE_BUSY", "تحليل الإطار السابق قيد التنفيذ", null); return }
                val jpeg = call.argument<ByteArray>("jpeg")
                val diagnostic = call.argument<Boolean>("diagnostic") == true
                val deferred = call.argument<Boolean>("defer_preview") == true
                val previewToken = call.argument<Number>("token")?.toLong()
                executor.execute {
                    try {
                        val answer = if (call.method == "initialize") initialize() else if (call.method == "preview") {
                            renderPreview(previewToken)
                        } else {
                            require(jpeg != null && jpeg.isNotEmpty() && jpeg.size <= 50 * 1024 * 1024) { "Invalid local image bytes" }
                            if (deferred) analyzeDeferred(jpeg, diagnostic) else analyze(jpeg, diagnostic)
                        }
                        activity.runOnUiThread {
                            // Dart can request a preview as soon as this reply arrives.
                            busy.set(false)
                            result.success(answer)
                        }
                    } catch (failure: Exception) {
                        // Initialization failure releases partial native resources; never falls back to an API.
                        if (call.method == "initialize") releaseEngine()
                        activity.runOnUiThread {
                            busy.set(false)
                            result.error(if (call.method == "initialize") "LOCAL_ENGINE_INIT_FAILED" else "LOCAL_INFERENCE_FAILED",
                                failure.message ?: "تعذر التحليل على الجهاز", null)
                        }
                    }
                }
            }
            "close" -> executor.execute {
                releaseEngine()
                activity.runOnUiThread { result.success(null) }
            }
            "export" -> {
                val name = call.argument<String>("name")
                val json = call.argument<String>("json")
                if (pendingExport != null) { result.error("EXPORT_BUSY", "اختيار مكان حفظ التقرير قيد التنفيذ", null); return }
                if (name == null || !name.matches(Regex("[A-Za-z0-9_-]{1,100}\\.json")) || json == null || json.length > 128_000_000) {
                    result.error("INVALID_EXPORT", "بيانات التقرير المحلي غير صالحة", null); return
                }
                pendingExport = PendingExport(json, result)
                try {
                    @Suppress("DEPRECATION")
                    activity.startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE); type = "application/json"
                        putExtra(Intent.EXTRA_TITLE, name)
                    }, EXPORT_REQUEST)
                } catch (failure: Exception) {
                    pendingExport = null
                    result.error("LOCAL_EXPORT_FAILED", failure.message ?: "تعذر فتح حفظ التقرير المحلي", null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun verifiedAsset(name: String, manifest: JSONObject): ByteArray {
        val bytes = activity.assets.open(assetRoot + name).use { it.readBytes() }
        val actual = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it.toInt() and 255) }
        require(actual == manifest.getJSONObject("assets").getString(name)) { "Local model asset integrity failed: $name" }
        return bytes
    }

    @Keep private fun initialize(): Map<String, Any> {
        if (detector == null) {
            val manifest = JSONObject(activity.assets.open(assetRoot + "manifest.json").bufferedReader().use { it.readText() })
            require(manifest.getString("schema_version") == LocalInferenceMath.SCHEMA_VERSION) { "Unsupported local prediction schema" }
            val classNames = manifest.getJSONArray("classes")
            require(classNames.length() == 8 && (0 until 8).all { classNames.getString(it) == LocalInferenceMath.classes[it] }) { "Local model class order mismatch" }
            modelVersion = manifest.getString("model_version")
            val preprocessing = JSONObject(String(verifiedAsset("preprocessing.json", manifest), Charsets.UTF_8))
            val means = preprocessing.getJSONArray("mean"); val stds = preprocessing.getJSONArray("std")
            require(means.length() == 165 && stds.length() == 165)
            mean = FloatArray(165) { means.getDouble(it).toFloat() }; std = FloatArray(165) { stds.getDouble(it).toFloat() }
            require(mean.all { it.isFinite() } && std.all { it.isFinite() && it > 0f })
            // Validate the installed task before MediaPipe opens it. Keep the original graph and all weights unchanged.
            verifiedAsset("pose_landmarker_heavy.task", manifest)
            detector = PoseLandmarker.createFromOptions(activity, PoseLandmarker.PoseLandmarkerOptions.builder()
                .setBaseOptions(BaseOptions.builder().setModelAssetPath(assetRoot + "pose_landmarker_heavy.task").setDelegate(Delegate.CPU).build())
                .setRunningMode(RunningMode.IMAGE).setNumPoses(1)
                .setMinPoseDetectionConfidence(.2f).setMinPosePresenceConfidence(.2f).setMinTrackingConfidence(.2f)
                .setOutputSegmentationMasks(false).build())
            val environment = OrtEnvironment.getEnvironment()
            for (seed in LocalInferenceMath.seeds) {
                OrtSession.SessionOptions().use { options ->
                    options.setIntraOpNumThreads(1); options.setInterOpNumThreads(1)
                    // No NNAPI/GPU delegate: small classifiers use the portable CPU execution provider.
                    val session = environment.createSession(verifiedAsset("main_seed_$seed.onnx", manifest), options)
                    try {
                        require(session.inputNames == setOf("features") && session.outputNames == setOf("logits")) { "Invalid local ONNX input/output contract" }
                        sessions.add(session)
                    } catch (failure: Exception) { session.close(); throw failure }
                }
            }
        }
        val storage = File(activity.filesDir, "iqtadi-local")
        check(storage.isDirectory || storage.mkdirs()) { "Unable to create private local report directory" }
        return mapOf("schema_version" to LocalInferenceMath.SCHEMA_VERSION, "model_version" to modelVersion,
            "pipeline_version" to LocalInferenceMath.PIPELINE_VERSION,
            "classes" to LocalInferenceMath.classes, "provider" to "cpu", "storage_path" to storage.absolutePath)
    }

    private fun decode(bytes: ByteArray): LocalInferenceImage.Rgb {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0 && bounds.outWidth.toLong() * bounds.outHeight <= 40_000_000) { "Invalid image dimensions or image exceeds 40 megapixels" }
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply {
            inPreferredConfig = Bitmap.Config.ARGB_8888; inPremultiplied = false; inScaled = false
        }) ?: error("Unable to decode local image")
        val rgb = try {
            val pixels = IntArray(bitmap.width * bitmap.height)
            bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
            val data = ByteArray(pixels.size * 3)
            pixels.forEachIndexed { i, p -> data[i * 3] = (p shr 16).toByte(); data[i * 3 + 1] = (p shr 8).toByte(); data[i * 3 + 2] = p.toByte() }
            LocalInferenceImage.Rgb(bitmap.width, bitmap.height, data)
        } finally { bitmap.recycle() }
        val orientation = ExifInterface(ByteArrayInputStream(bytes)).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
        return LocalInferenceImage.orient(rgb, orientation)
    }

    private fun bitmap(image: LocalInferenceImage.Rgb): Bitmap {
        val colors = IntArray(image.width * image.height) { i ->
            Color.rgb(image.data[i * 3].toInt() and 255, image.data[i * 3 + 1].toInt() and 255, image.data[i * 3 + 2].toInt() and 255)
        }
        return Bitmap.createBitmap(colors, image.width, image.height, Bitmap.Config.ARGB_8888)
    }

    private fun classify(features: FloatArray): List<FloatArray> {
        require(features.size == 166 && features.all(Float::isFinite) && features[165] == 1f && sessions.size == 3)
        val environment = OrtEnvironment.getEnvironment()
        return OnnxTensor.createTensor(environment, FloatBuffer.wrap(features), longArrayOf(1, 166)).use { input ->
            sessions.map { session ->
                session.run(mapOf("features" to input)).use { output ->
                    @Suppress("UNCHECKED_CAST")
                    val values = output.get("logits").orElseThrow { IllegalStateException("Missing local logits") }.value as Array<FloatArray>
                    require(values.size == 1 && values[0].size == 8)
                    values[0].copyOf()
                }
            }
        }
    }

    private fun evidence(image: LocalInferenceImage.Rgb, points: List<LocalInferenceMath.Landmark>): ByteArray {
        val source = bitmap(image)
        val preview = try { source.copy(Bitmap.Config.ARGB_8888, true) } finally { source.recycle() }
        try {
            val canvas = Canvas(preview)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(24, 190, 120); strokeWidth = 2.5f; style = Paint.Style.STROKE }
            val connections = listOf(11 to 12, 11 to 13, 13 to 15, 12 to 14, 14 to 16, 11 to 23, 12 to 24,
                23 to 24, 23 to 25, 25 to 27, 24 to 26, 26 to 28, 27 to 29, 29 to 31, 28 to 30, 30 to 32)
            for ((a, b) in connections) if (points[a].visibility >= .2f && points[b].visibility >= .2f) {
                canvas.drawLine(points[a].x * 384, points[a].y * 512, points[b].x * 384, points[b].y * 512, paint)
            }
            paint.style = Paint.Style.FILL
            for (point in points) if (point.visibility >= .2f) canvas.drawCircle(point.x * 384, point.y * 512, 3f, paint)
            return ByteArrayOutputStream().use { output -> check(preview.compress(Bitmap.CompressFormat.JPEG, 90, output)); output.toByteArray() }
        } finally { preview.recycle() }
    }

    // Keep private names for local device instrumentation, including release APKs.
    @Keep private fun analyze(bytes: ByteArray, diagnostic: Boolean): Map<String, Any?> = analyzeInternal(bytes, diagnostic, false)
    @Keep private fun analyzeDeferred(bytes: ByteArray, diagnostic: Boolean): Map<String, Any?> = analyzeInternal(bytes, diagnostic, true)
    @Keep private fun renderPreview(token: Long?): ByteArray {
        val pending = checkNotNull(pendingPreview) { "Local evidence frame is no longer available" }
        check(pending.token == token) { "Local evidence token does not match its frame" }
        val bytes = evidence(pending.image, pending.points)
        pendingPreview = null
        return bytes
    }
    private fun analyzeInternal(bytes: ByteArray, diagnostic: Boolean, deferred: Boolean): Map<String, Any?> {
        check(detector != null && sessions.size == 3) { "Initialize local inference before analyzing an image" }
        val started = SystemClock.elapsedRealtimeNanos()
        pendingPreview = null
        val prepared = LocalInferenceImage.letterbox(decode(bytes))
        for (index in LocalInferenceMath.recovery.indices) {
            val candidate = LocalInferenceImage.recovery(prepared, index)
            val frame = bitmap(candidate)
            val points = try {
                val image = BitmapImageBuilder(frame).build()
                try {
                    detector!!.detect(image).landmarks().firstOrNull()?.map { p -> LocalInferenceMath.Landmark(
                        p.x(), p.y(), p.z(), p.visibility().orElse(0f), p.presence().orElse(0f)) } ?: emptyList()
                } finally { image.close() }
            } finally { frame.recycle() }
            val features = LocalInferenceMath.features(points, mean, std) ?: continue
            val logits = classify(features)
            val result = LocalInferenceMath.ensemble(logits, modelVersion, LocalInferenceMath.recovery[index],
                points.sumOf { it.visibility.toDouble() } / 33, (SystemClock.elapsedRealtimeNanos() - started) / 1_000_000.0)
            return linkedMapOf<String, Any?>("result" to result, "landmarks" to points.map { it.asMap() }).apply {
                if (deferred) {
                    val token = ++previewSequence
                    pendingPreview = PendingPreview(token, candidate, points)
                    put("preview_token", token)
                } else put("preview_jpeg", evidence(candidate, points))
                if (diagnostic) put("features", features.map { it.toDouble() })
            }
        }
        return mapOf("result" to LocalInferenceMath.failed(modelVersion, (SystemClock.elapsedRealtimeNanos() - started) / 1_000_000.0), "landmarks" to emptyList<Any>())
    }

    private fun releaseEngine() {
        pendingPreview = null
        detector?.close(); detector = null
        sessions.forEach { it.close() }; sessions.clear()
        mean = floatArrayOf(); std = floatArrayOf(); modelVersion = ""
    }

    fun close() {
        channel.setMethodCallHandler(null)
        closed = true
        pendingExport?.result?.error("LOCAL_ENGINE_CLOSED", "تم إغلاق حفظ التقرير", null); pendingExport = null
        executor.execute { releaseEngine() }
        executor.shutdown()
    }

    fun activityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != EXPORT_REQUEST) return false
        val pending = pendingExport ?: return true
        pendingExport = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { pending.result.success(false); return true }
        executor.execute {
            try {
                // Stream UTF-8 encoding to avoid allocating another complete
                // byte[] for a large locally retained evidence report.
                activity.contentResolver.openOutputStream(uri, "wt")?.bufferedWriter(Charsets.UTF_8)?.use { it.write(pending.json) }
                    ?: error("Unable to open selected local report document")
                activity.runOnUiThread { pending.result.success(true) }
            } catch (failure: Exception) {
                activity.runOnUiThread { pending.result.error("LOCAL_EXPORT_FAILED", failure.message ?: "تعذر حفظ التقرير المحلي", null) }
            }
        }
        return true
    }

    companion object { private const val EXPORT_REQUEST = 7211 }
}
