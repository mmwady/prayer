package com.example.coaching

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.round
import kotlin.math.sin

/** RGB-only Pillow-compatible transforms; do not replace with Android bilinear scaling. */
internal object LocalInferenceImage {
    data class Rgb(val width: Int, val height: Int, val data: ByteArray) {
        init { require(width > 0 && height > 0 && data.size == width * height * 3) }
    }
    private fun u(value: Byte) = value.toInt() and 255
    private fun clip(value: Double) = value.toInt().coerceIn(0, 255).toByte()
    fun thumbnailSize(w: Int, h: Int): Pair<Int, Int> {
        if (w <= 384 && h <= 512) return w to h
        val aspect = w.toDouble() / h
        fun best(value: Double, error: (Int) -> Double): Int {
            val low = floor(value).toInt(); val high = ceil(value).toInt()
            return (if (error(low) <= error(high)) low else high).coerceAtLeast(1)
        }
        return if (384.0 / 512 >= aspect) best(512 * aspect) { abs(aspect - it / 512.0) } to 512
        else 384 to best(384 / aspect) { if (it == 0) 0.0 else abs(aspect - 384.0 / it) }
    }
    private fun sinc(x: Double) = if (x == 0.0) 1.0 else sin(x * PI) / (x * PI)
    private fun lanczos(x: Double) = if (x >= -3 && x < 3) sinc(x) * sinc(x / 3) else 0.0
    private data class Coefficient(val start: Int, val weights: IntArray)
    private data class ResizeKey(val input: Int, val extent: Double, val output: Int)
    private val coefficientCache = linkedMapOf<ResizeKey, List<Coefficient>>()
    @Synchronized
    private fun coefficients(input: Int, extent: Double, output: Int): List<Coefficient> {
        val key = ResizeKey(input, extent, output)
        coefficientCache[key]?.let { return it }
        val scale = extent.toFloat().toDouble() / output; val filterScale = maxOf(1.0, scale); val support = 3 * filterScale
        val rows = List(output) { i ->
            val center = (i + .5) * scale
            val start = maxOf(0, (center - support + .5).toInt())
            val end = minOf(input, (center + support + .5).toInt())
            val weights = DoubleArray(end - start) { j -> lanczos((j + start - center + .5) / filterScale) }
            val sum = weights.sum()
            Coefficient(start, IntArray(weights.size) { j ->
                val value = if (sum != 0.0) weights[j] / sum else weights[j]
                (value * 4194304 + if (value < 0) -.5 else .5).toInt()
            })
        }
        if (coefficientCache.size >= 12) coefficientCache.remove(coefficientCache.keys.first())
        coefficientCache[key] = rows
        return rows
    }
    private fun resizeAxis(image: Rgb, output: Int, horizontal: Boolean, extent: Double): Rgb {
        val input = if (horizontal) image.width else image.height
        if (input == output && extent == input.toDouble()) return image
        val coeff = coefficients(input, extent, output)
        val w = if (horizontal) output else image.width; val h = if (horizontal) image.height else output
        val data = ByteArray(w * h * 3)
        for (y in 0 until h) for (x in 0 until w) {
            val row = coeff[if (horizontal) x else y]
            for (c in 0..2) {
                var sum = 2097152L
                for (j in row.weights.indices) {
                    val index = if (horizontal) (y * image.width + row.start + j) * 3 + c else ((row.start + j) * image.width + x) * 3 + c
                    sum += u(image.data[index]).toLong() * row.weights[j]
                }
                data[(y * w + x) * 3 + c] = clip(floor(sum.toDouble() / 4194304))
            }
        }
        return Rgb(w, h, data)
    }
    private fun reduce(image: Rgb, fx: Int, fy: Int): Rgb {
        if (fx == 1 && fy == 1) return image
        val w = (image.width + fx - 1) / fx; val h = (image.height + fy - 1) / fy; val data = ByteArray(w * h * 3)
        for (y in 0 until h) for (x in 0 until w) {
            val nx = minOf(fx, image.width - x * fx); val ny = minOf(fy, image.height - y * fy); val count = nx * ny
            val multiplier = 16777216L / count
            for (c in 0..2) {
                var sum = (count / 2).toLong()
                for (j in 0 until ny) for (i in 0 until nx) sum += u(image.data[((y * fy + j) * image.width + x * fx + i) * 3 + c])
                data[(y * w + x) * 3 + c] = (sum * multiplier / 16777216).toByte()
            }
        }
        return Rgb(w, h, data)
    }
    fun letterbox(image: Rgb): Rgb {
        val (w, h) = thumbnailSize(image.width, image.height)
        val fx = maxOf(1, (image.width.toDouble() / w / 2).toInt()); val fy = maxOf(1, (image.height.toDouble() / h / 2).toInt())
        var resized = reduce(image, fx, fy)
        resized = resizeAxis(resized, w, true, image.width.toDouble() / fx)
        resized = resizeAxis(resized, h, false, image.height.toDouble() / fy)
        val data = ByteArray(384 * 512 * 3); val left = (384 - w) / 2; val top = (512 - h) / 2
        for (y in 0 until h) resized.data.copyInto(data, ((top + y) * 384 + left) * 3, y * w * 3, (y + 1) * w * 3)
        return Rgb(384, 512, data)
    }
    fun autocontrast(image: Rgb): Rgb {
        val data = ByteArray(image.data.size); val count = image.width * image.height
        for (c in 0..2) {
            val hist = IntArray(256)
            for (i in c until data.size step 3) hist[u(image.data[i])]++
            var cut = count / 100
            for (i in 0..255) { val n = minOf(hist[i], cut); hist[i] -= n; cut -= n }
            cut = count / 100
            for (i in 255 downTo 0) { val n = minOf(hist[i], cut); hist[i] -= n; cut -= n }
            var low = 0; var high = 255
            while (low < 255 && hist[low] == 0) low++
            while (high > 0 && hist[high] == 0) high--
            val scale = 255.0 / (high - low); val offset = -low * scale
            for (i in c until data.size step 3) data[i] = if (high <= low) image.data[i] else clip(u(image.data[i]) * scale + offset)
        }
        return Rgb(image.width, image.height, data)
    }
    fun contrast(image: Rgb): Rgb {
        var sum = 0L
        for (i in image.data.indices step 3) sum += (19595L * u(image.data[i]) + 38470L * u(image.data[i + 1]) + 7471L * u(image.data[i + 2]) + 32768) / 65536
        val mean = floor(sum.toDouble() / (image.width * image.height) + .5).toInt()
        val data = ByteArray(image.data.size) { clip((mean + 1.15f * (u(image.data[it]) - mean)).toDouble()) }
        return Rgb(image.width, image.height, data)
    }
    private fun cubic(v1: Double, v2: Double, v3: Double, v4: Double, d: Double) =
        v2 + d * (-v1 + v3 + d * (2 * (v1 - v2) + v3 - v4 + d * (-v1 + v2 - v3 + v4)))
    fun rotate(image: Rgb, degrees: Int): Rgb {
        val w = image.width; val h = image.height; val data = ByteArray(image.data.size)
        val angle = -((degrees % 360 + 360) % 360) * PI / 180
        val a = round(cos(angle) * 1e15) / 1e15; val b = round(sin(angle) * 1e15) / 1e15; val d = -b; val e = a
        val tx = a * (-w / 2.0) + b * (-h / 2.0) + w / 2.0; val ty = d * (-w / 2.0) + e * (-h / 2.0) + h / 2.0
        for (y in 0 until h) for (x in 0 until w) {
            val sx = a * (x + .5) + b * (y + .5) + tx; val sy = d * (x + .5) + e * (y + .5) + ty
            if (sx < 0 || sy < 0 || sx >= w || sy >= h) continue
            val ix = floor(sx - .5).toInt(); val iy = floor(sy - .5).toInt(); val dx = sx - .5 - ix; val dy = sy - .5 - iy
            for (c in 0..2) {
                val rows = DoubleArray(4)
                for (k in 0..3) {
                    val yy = iy - 1 + k
                    if (k > 0 && (yy < 0 || yy >= h)) { rows[k] = rows[k - 1]; continue }
                    val row = DoubleArray(4) { j -> u(image.data[(yy.coerceIn(0, h - 1) * w + (ix - 1 + j).coerceIn(0, w - 1)) * 3 + c]).toDouble() }
                    rows[k] = cubic(row[0], row[1], row[2], row[3], dx)
                }
                data[(y * w + x) * 3 + c] = clip(cubic(rows[0], rows[1], rows[2], rows[3], dy))
            }
        }
        return Rgb(w, h, data)
    }
    fun recovery(image: Rgb, index: Int): Rgb = when (index) {
        0 -> image; 1 -> autocontrast(image); 2 -> contrast(image); 3 -> rotate(image, -5); 4 -> rotate(image, 5)
        else -> error("Invalid recovery candidate")
    }
    /** Apply EXIF transpose without introducing any interpolation or mirroring elsewhere. */
    fun orient(image: Rgb, orientation: Int): Rgb {
        if (orientation !in 2..8) return image
        val transposed = orientation in 5..8; val w = if (transposed) image.height else image.width; val h = if (transposed) image.width else image.height
        val data = ByteArray(image.data.size)
        for (y in 0 until image.height) for (x in 0 until image.width) {
            val (dx, dy) = when (orientation) {
                2 -> image.width - 1 - x to y
                3 -> image.width - 1 - x to image.height - 1 - y
                4 -> x to image.height - 1 - y
                5 -> y to x
                6 -> image.height - 1 - y to x
                7 -> image.height - 1 - y to image.width - 1 - x
                else -> y to image.width - 1 - x
            }
            image.data.copyInto(data, (dy * w + dx) * 3, (y * image.width + x) * 3, (y * image.width + x) * 3 + 3)
        }
        return Rgb(w, h, data)
    }
}
