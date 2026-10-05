package com.example.coaching

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import android.graphics.SurfaceTexture
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.view.Surface
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs

/** Confined to the bridge executor. Holds at most two decoded frames, never the video. */
internal class SequentialVideoDecoder(
    context: Context, uri: Uri, width: Int, height: Int,
    dimension: Int, private val rotation: Int,
) : AutoCloseable {
    private val extractor = MediaExtractor()
    private var codec: MediaCodec? = null
    private var renderer: FrameRenderer? = null
    private var inputEnded = false
    private var outputEnded = false
    private data class Frame(val index: Int, val timeUs: Long)
    private var previous: Frame? = null
    private var following: Frame? = null
    private var lastRequestUs = -1L
    private var cachedBitmap: Bitmap? = null
    private var cachedTimeUs = -1L
    internal var decodedFrames = 0
        private set
    internal var sampledTimeUs = -1L
        private set

    init {
        try {
            extractor.setDataSource(context, uri, null)
            val track = (0 until extractor.trackCount).first {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true
            }
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            // The legacy retriever owns HDR tone mapping. Keep that compatibility path
            // rather than silently reducing HDR through an ordinary 8-bit EGL surface.
            if (format.containsKey(MediaFormat.KEY_COLOR_TRANSFER)) {
                val transfer = format.getInteger(MediaFormat.KEY_COLOR_TRANSFER)
                check(transfer != MediaFormat.COLOR_TRANSFER_ST2084 && transfer != MediaFormat.COLOR_TRANSFER_HLG) {
                    "HDR requires the retriever tone-mapping path"
                }
            }
            // Rotation is applied once after GPU scaling, independently of codec/vendor behavior.
            format.setInteger(MediaFormat.KEY_ROTATION, 0)
            val scale = minOf(1.0, dimension.toDouble() / maxOf(width, height))
            val target = FrameRenderer(maxOf(1, (width * scale).toInt()), maxOf(1, (height * scale).toInt()))
            renderer = target
            val decoder = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
            codec = decoder
            decoder.configure(format, target.surface, null, 0)
            decoder.start()
        } catch (failure: Exception) {
            close()
            throw failure
        }
    }

    fun frame(timestampMs: Long): Bitmap {
        val requested = timestampMs * 1000
        require(requested >= lastRequestUs) { "Restart decoder for a backward request" }
        lastRequestUs = requested
        val decoder = checkNotNull(codec)
        if (following == null && !outputEnded) following = nextFrame()
        while (following != null && following!!.timeUs < requested) {
            previous?.let { decoder.releaseOutputBuffer(it.index, false) }
            previous = following
            following = nextFrame()
        }
        val before = previous
        val after = following
        val selected = listOfNotNull(before, after).minWithOrNull(
            // Android's closest-frame search chooses the later frame on an exact tie.
            compareBy<Frame> { abs(requested - it.timeUs) }.thenByDescending { it.timeUs })
        val cached = cachedBitmap
        if (cached != null && (selected == null ||
                abs(requested - cachedTimeUs) < abs(requested - selected.timeUs) ||
                (abs(requested - cachedTimeUs) == abs(requested - selected.timeUs) && cachedTimeUs >= selected.timeUs))) {
            sampledTimeUs = cachedTimeUs
            return checkNotNull(cached.copy(Bitmap.Config.ARGB_8888, false))
        }
        checkNotNull(selected) { "Video contains no decoded frames" }
        val target = checkNotNull(renderer)
        // A rendered buffer cannot be rendered again. Keep its scaled bitmap for repeated
        // timestamps/low-frame-rate clips; unsampled frames never reach the GPU readback.
        val bitmap = target.bitmap(rotation) {
            decoder.releaseOutputBuffer(selected.index, true)
            if (previous === selected) previous = null
            if (following === selected) {
                following = null
                // nextFrame() can be deferred until the next request, including upload pauses.
            }
        }
        cachedBitmap?.recycle()
        cachedBitmap = bitmap
        cachedTimeUs = selected.timeUs
        sampledTimeUs = selected.timeUs
        return checkNotNull(bitmap.copy(Bitmap.Config.ARGB_8888, false))
    }

    private fun nextFrame(): Frame? {
        val decoder = checkNotNull(codec)
        val info = MediaCodec.BufferInfo()
        var lastProgress = SystemClock.elapsedRealtime()
        while (!outputEnded) {
            if (!inputEnded) {
                val input = decoder.dequeueInputBuffer(0)
                if (input >= 0) {
                    val buffer = checkNotNull(decoder.getInputBuffer(input))
                    val size = extractor.readSampleData(buffer, 0)
                    if (size < 0) {
                        decoder.queueInputBuffer(input, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputEnded = true
                    } else {
                        decoder.queueInputBuffer(input, 0, size, extractor.sampleTime, 0)
                        extractor.advance()
                    }
                    lastProgress = SystemClock.elapsedRealtime()
                }
            }
            val index = decoder.dequeueOutputBuffer(info, 10_000)
            if (index >= 0) {
                outputEnded = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                if (info.size > 0 && info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) {
                    decodedFrames++
                    return Frame(index, info.presentationTimeUs)
                }
                decoder.releaseOutputBuffer(index, false)
                lastProgress = SystemClock.elapsedRealtime()
            } else if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                lastProgress = SystemClock.elapsedRealtime()
            }
            check(SystemClock.elapsedRealtime() - lastProgress < 10_000) { "Video decoder stalled" }
        }
        return null
    }

    override fun close() {
        previous = null
        following = null
        cachedBitmap?.recycle()
        cachedBitmap = null
        val decoder = codec
        codec = null
        try {
            decoder?.release()
        } finally {
            try { extractor.release() } finally {
                renderer?.close()
                renderer = null
            }
        }
    }
}

/** Decoder surface -> scaled GPU framebuffer -> bitmap, only for selected samples. */
private class FrameRenderer(private val width: Int, private val height: Int) : AutoCloseable {
    private val display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
    private var eglContext = EGL14.EGL_NO_CONTEXT
    private var eglSurface = EGL14.EGL_NO_SURFACE
    private var texture = 0
    private var program = 0
    private var surfaceTexture: SurfaceTexture? = null
    private val callbacks = HandlerThread("iqtadi-video-frames")
    private val signal = Object()
    private var available = false
    lateinit var surface: Surface
        private set
    private val rgba = ByteBuffer.allocateDirect(width * height * 4).order(ByteOrder.nativeOrder())
    private val vertices = ByteBuffer.allocateDirect(16 * 4).order(ByteOrder.nativeOrder())
        .asFloatBuffer().apply {
            put(floatArrayOf(-1f, -1f, 0f, 0f, 1f, -1f, 1f, 0f,
                -1f, 1f, 0f, 1f, 1f, 1f, 1f, 1f)); position(0)
        }

    init {
        try {
            check(EGL14.eglInitialize(display, IntArray(2), 0, IntArray(2), 1))
            val configs = arrayOfNulls<EGLConfig>(1)
            val count = IntArray(1)
            check(EGL14.eglChooseConfig(display, intArrayOf(
                EGL14.EGL_RED_SIZE, 8, EGL14.EGL_GREEN_SIZE, 8, EGL14.EGL_BLUE_SIZE, 8,
                EGL14.EGL_ALPHA_SIZE, 8, EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
                EGL14.EGL_SURFACE_TYPE, EGL14.EGL_PBUFFER_BIT, EGL14.EGL_NONE),
                0, configs, 0, 1, count, 0) && count[0] > 0)
            eglContext = EGL14.eglCreateContext(display, configs[0], EGL14.EGL_NO_CONTEXT,
                intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE), 0)
            eglSurface = EGL14.eglCreatePbufferSurface(display, configs[0],
                intArrayOf(EGL14.EGL_WIDTH, width, EGL14.EGL_HEIGHT, height, EGL14.EGL_NONE), 0)
            check(EGL14.eglMakeCurrent(display, eglSurface, eglSurface, eglContext))
            val textures = IntArray(1)
            GLES20.glGenTextures(1, textures, 0)
            texture = textures[0]
            GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, texture)
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
            surfaceTexture = SurfaceTexture(texture)
            callbacks.start()
            surfaceTexture!!.setOnFrameAvailableListener({
                synchronized(signal) { available = true; signal.notifyAll() }
            }, Handler(callbacks.looper))
            surface = Surface(surfaceTexture)
            program = GLES20.glCreateProgram()
            val vertex = shader(GLES20.GL_VERTEX_SHADER,
                "attribute vec2 position; attribute vec2 uv; uniform mat4 transform; varying vec2 tex; " +
                "void main(){gl_Position=vec4(position,0.,1.);tex=(transform*vec4(uv,0.,1.)).xy;}")
            val fragment = shader(GLES20.GL_FRAGMENT_SHADER,
                "#extension GL_OES_EGL_image_external : require\nprecision mediump float; " +
                "uniform samplerExternalOES image; varying vec2 tex; void main(){gl_FragColor=texture2D(image,tex);}")
            GLES20.glAttachShader(program, vertex)
            GLES20.glAttachShader(program, fragment)
            GLES20.glLinkProgram(program)
            GLES20.glDeleteShader(vertex)
            GLES20.glDeleteShader(fragment)
            val linked = IntArray(1)
            GLES20.glGetProgramiv(program, GLES20.GL_LINK_STATUS, linked, 0)
            check(linked[0] != 0) { GLES20.glGetProgramInfoLog(program) }
        } catch (failure: Exception) {
            close()
            throw failure
        }
    }

    fun bitmap(rotation: Int, render: () -> Unit): Bitmap {
        synchronized(signal) { available = false }
        render()
        val deadline = SystemClock.elapsedRealtime() + 5_000
        synchronized(signal) {
            while (!available) {
                val remaining = deadline - SystemClock.elapsedRealtime()
                check(remaining > 0) { "Decoder surface timed out" }
                signal.wait(remaining)
            }
        }
        val source = checkNotNull(surfaceTexture)
        source.updateTexImage()
        val transform = FloatArray(16)
        source.getTransformMatrix(transform)
        GLES20.glViewport(0, 0, width, height)
        GLES20.glUseProgram(program)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, texture)
        GLES20.glUniform1i(GLES20.glGetUniformLocation(program, "image"), 0)
        GLES20.glUniformMatrix4fv(GLES20.glGetUniformLocation(program, "transform"), 1, false, transform, 0)
        val position = GLES20.glGetAttribLocation(program, "position")
        val uv = GLES20.glGetAttribLocation(program, "uv")
        vertices.position(0)
        GLES20.glVertexAttribPointer(position, 2, GLES20.GL_FLOAT, false, 16, vertices)
        vertices.position(2)
        GLES20.glVertexAttribPointer(uv, 2, GLES20.GL_FLOAT, false, 16, vertices)
        GLES20.glEnableVertexAttribArray(position)
        GLES20.glEnableVertexAttribArray(uv)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        rgba.position(0)
        GLES20.glReadPixels(0, 0, width, height, GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, rgba)
        check(GLES20.glGetError() == GLES20.GL_NO_ERROR) { "GPU frame readback failed" }
        val raw = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        rgba.position(0)
        raw.copyPixelsFromBuffer(rgba)
        val matrix = Matrix().apply { postScale(1f, -1f); postRotate(rotation.toFloat()) }
        return try { Bitmap.createBitmap(raw, 0, 0, width, height, matrix, true) }
        finally { raw.recycle() }
    }

    private fun shader(type: Int, code: String): Int {
        val shader = GLES20.glCreateShader(type)
        GLES20.glShaderSource(shader, code)
        GLES20.glCompileShader(shader)
        val compiled = IntArray(1)
        GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, compiled, 0)
        if (compiled[0] == 0) {
            val log = GLES20.glGetShaderInfoLog(shader)
            GLES20.glDeleteShader(shader)
            error(log)
        }
        return shader
    }

    override fun close() {
        if (::surface.isInitialized) surface.release()
        surfaceTexture?.release()
        surfaceTexture = null
        callbacks.quitSafely()
        if (eglContext != EGL14.EGL_NO_CONTEXT) {
            GLES20.glDeleteProgram(program)
            GLES20.glDeleteTextures(1, intArrayOf(texture), 0)
            EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
            EGL14.eglDestroySurface(display, eglSurface)
            EGL14.eglDestroyContext(display, eglContext)
            eglContext = EGL14.EGL_NO_CONTEXT
        }
        EGL14.eglTerminate(display)
    }
}
