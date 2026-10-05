package com.example.coaching

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.provider.OpenableColumns
import android.util.Log
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var mosqueLocation: MosqueLocation? = null
    private var liveCamera: LiveCameraEncoder? = null
    @androidx.annotation.Keep private var localInference: LocalInferenceChannel? = null
    private val executor = Executors.newSingleThreadExecutor()
    private var retriever: MediaMetadataRetriever? = null
    private var pendingPick: MethodChannel.Result? = null
    private var videoWidth = 0
    private var videoHeight = 0
    private var sourceId = 0
    private var videoUri: Uri? = null
    private var videoRotation = 0
    private var sequential: SequentialVideoDecoder? = null
    private var sequentialDisabled = false
    private var sequentialDimension = 0
    private var lastTimestamp = -1L
    private var sampledFrames = 0
    private var extractionMs = 0L
    private var compressionMs = 0L

    private fun releaseSequential() {
        val decoder = sequential
        sequential = null
        decoder?.close()
        lastTimestamp = -1L
    }

    private fun extractFrame(timestamp: Long, dimension: Int): Bitmap {
        val source = retriever ?: error("NO_LOCAL_VIDEO")
        if (!sequentialDisabled) {
            try {
                if (sequential != null && (timestamp < lastTimestamp || dimension != sequentialDimension)) {
                    releaseSequential()
                }
                if (sequential == null) {
                    sequential = SequentialVideoDecoder(this, checkNotNull(videoUri),
                        videoWidth, videoHeight, dimension, videoRotation)
                    sequentialDimension = dimension
                }
                val frame = sequential!!.frame(timestamp)
                lastTimestamp = timestamp
                return frame
            } catch (failure: Exception) {
                // Preserve support for vendor codecs/files that reject the surface decoder.
                // Stay on the retriever for this selection instead of retrying every sample.
                sequentialDisabled = true
                releaseSequential()
                Log.w("IqtadiVideo", "Sequential decoder unavailable; using retriever (${failure.javaClass.simpleName})")
            }
        }
        val scale = minOf(1.0, dimension.toDouble() / maxOf(videoWidth, videoHeight))
        return source.getScaledFrameAtTime(timestamp * 1000,
            MediaMetadataRetriever.OPTION_CLOSEST,
            maxOf(1, (videoWidth * scale).toInt()),
            maxOf(1, (videoHeight * scale).toInt())) ?: error("FRAME_DECODE_FAILED")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        mosqueLocation = MosqueLocation(this, flutterEngine.dartExecutor.binaryMessenger)
        liveCamera = LiveCameraEncoder(this, flutterEngine.dartExecutor.binaryMessenger)
        localInference = LocalInferenceChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "iqtadi/recorded_video")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pick" -> {
                        if (Build.VERSION.SDK_INT < 27) {
                            result.error("PLATFORM_UNSUPPORTED", "يتطلب استخراج الفيديو Android 8.1 أو أحدث", null)
                        } else if (pendingPick != null) {
                            result.error("PICKER_BUSY", "اختيار الفيديو قيد التنفيذ", null)
                        } else {
                            pendingPick = result
                            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                type = "video/*"
                                addCategory(Intent.CATEGORY_OPENABLE)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }, 7201)
                        }
                    }
                    "frame" -> {
                        val timestamp = call.argument<Number>("timestamp_ms")?.toLong() ?: -1
                        val dimension = call.argument<Int>("max_dimension") ?: 960
                        val id = call.argument<Int>("source_id")
                        executor.execute {
                            try {
                                require(timestamp >= 0 && dimension in 1..1920)
                                require(id == sourceId)
                                val started = SystemClock.elapsedRealtime()
                                val frame = extractFrame(timestamp, dimension)
                                val extracted = SystemClock.elapsedRealtime()
                                val output = ByteArrayOutputStream()
                                try { check(frame.compress(Bitmap.CompressFormat.JPEG, 80, output)) }
                                finally { frame.recycle() }
                                val bytes = output.toByteArray()
                                sampledFrames++
                                extractionMs += extracted - started
                                compressionMs += SystemClock.elapsedRealtime() - extracted
                                if (sampledFrames == 1 || sampledFrames % 40 == 0) {
                                    Log.d("IqtadiVideo", "samples=$sampledFrames mode=${if (sequentialDisabled) "retriever" else "sequential"} extraction_ms=$extractionMs jpeg_ms=$compressionMs")
                                }
                                runOnUiThread { result.success(bytes) }
                            } catch (_: Exception) {
                                runOnUiThread { result.error("FRAME_DECODE_FAILED", "تعذر استخراج إطار الفيديو", null) }
                            }
                        }
                    }
                    "close" -> executor.execute {
                        if (call.argument<Int>("source_id") == sourceId) {
                            releaseSequential()
                            retriever?.release(); retriever = null
                            videoUri = null
                        }
                        runOnUiThread { result.success(null) }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Activity result bridge for Flutter method channel")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (localInference?.activityResult(requestCode, resultCode, data) == true) return
        if (requestCode != 7201) return
        val result = pendingPick ?: return
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { result.success(null); return }
        executor.execute {
            var source: MediaMetadataRetriever? = null
            try {
                releaseSequential()
                retriever?.release(); retriever = null
                videoUri = null
                source = MediaMetadataRetriever()
                source.setDataSource(this, uri)
                val duration = source.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLong() ?: 0
                videoWidth = source.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toInt() ?: 0
                videoHeight = source.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toInt() ?: 0
                require(duration > 0 && videoWidth > 0 && videoHeight > 0)
                var name = "فيديو محلي"
                contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                    if (it.moveToFirst()) name = it.getString(0)
                }
                retriever = source
                videoUri = uri
                videoRotation = source.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toInt() ?: 0
                sequentialDisabled = false
                sampledFrames = 0
                extractionMs = 0
                compressionMs = 0
                sourceId++
                val selectedId = sourceId
                runOnUiThread { result.success(mapOf("name" to name, "duration_ms" to duration, "source_id" to selectedId)) }
            } catch (_: Exception) {
                source?.release()
                runOnUiThread { result.error("VIDEO_OPEN_FAILED", "تعذر فتح الفيديو المحلي", null) }
            }
        }
    }

    override fun onDestroy() {
        mosqueLocation?.close()
        liveCamera?.close()
        localInference?.close()
        executor.execute {
            releaseSequential()
            retriever?.release(); retriever = null
            videoUri = null
        }
        executor.shutdown()
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (mosqueLocation?.permissionResult(requestCode) == true) return
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }
}
