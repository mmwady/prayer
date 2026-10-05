package com.example.coaching

import kotlin.math.exp
import kotlin.math.sqrt

/** Float32 reference contract shared with imcspd_inference.py and browser/core.mjs. */
internal object LocalInferenceMath {
    const val SCHEMA_VERSION = "2.0.0"
    const val PIPELINE_VERSION = "android-local-1"
    val seeds = listOf("2026", "3407", "8111")
    val classes = listOf("1_Qiyam", "2_Takbir", "3_Qiyam_Recitation", "4_Ruku",
        "5_Sujud", "6_Jalsa", "7_Salam_Right", "8_Salam_Left")
    val recovery = listOf("standard", "autocontrast", "contrast_1.15", "rotate_minus_5", "rotate_plus_5")
    data class Landmark(val x: Float, val y: Float, val z: Float, val visibility: Float, val presence: Float) {
        fun asMap() = mapOf("x" to x.toDouble(), "y" to y.toDouble(), "z" to z.toDouble(),
            "visibility" to visibility.toDouble(), "presence" to presence.toDouble())
    }

    fun features(points: List<Landmark>, mean: FloatArray, std: FloatArray): FloatArray? {
        require(mean.size == 165 && std.size == 165 && mean.all { it.isFinite() } && std.all { it.isFinite() && it > 0f })
        if (points.size != 33 || points.any { !it.x.isFinite() || !it.y.isFinite() || !it.z.isFinite() }) return null
        val hip = floatArrayOf((points[23].x + points[24].x) * .5f,
            (points[23].y + points[24].y) * .5f, (points[23].z + points[24].z) * .5f)
        fun norm(x: Float, y: Float): Float = sqrt((x * x + y * y).toDouble()).toFloat()
        val torso = norm((points[11].x + points[12].x) * .5f - hip[0],
            (points[11].y + points[12].y) * .5f - hip[1])
        val shoulders = norm(points[11].x - points[12].x, points[11].y - points[12].y)
        val scale = maxOf(torso, shoulders)
        if (!scale.isFinite() || scale <= 1e-4f) return null
        val values = FloatArray(166)
        points.forEachIndexed { i, p ->
            values[i * 3] = (p.x - hip[0]) / scale
            values[i * 3 + 1] = (p.y - hip[1]) / scale
            values[i * 3 + 2] = (p.z - hip[2]) / scale
            values[99 + i] = p.visibility
            values[132 + i] = p.presence
        }
        for (i in 0 until 165) values[i] = (values[i] - mean[i]) / std[i]
        values[165] = 1f
        return values.takeIf { it.all(Float::isFinite) }
    }

    fun softmax(logits: FloatArray): DoubleArray {
        require(logits.size == 8 && logits.all(Float::isFinite))
        val max = logits.max().toDouble()
        val values = DoubleArray(8) { exp(logits[it].toDouble() - max) }
        val sum = values.sum()
        return DoubleArray(8) { values[it] / sum }
    }

    fun average(probabilities: List<DoubleArray>): DoubleArray {
        require(probabilities.size == 3 && probabilities.all { it.size == 8 && it.all { n -> n.isFinite() && n >= 0 } })
        return DoubleArray(8) { (probabilities[0][it] + probabilities[1][it] + probabilities[2][it]) / 3.0 }
    }

    fun decision(probabilities: DoubleArray): Map<String, Any> {
        require(probabilities.size == 8)
        val ordered = probabilities.indices.sortedWith(compareByDescending<Int> { probabilities[it] }.thenByDescending { it })
        val winner = ordered[0]
        return linkedMapOf("predicted_action" to classes[winner], "class_index" to winner,
            "confidence" to probabilities[winner], "probabilities" to classes.indices.associate { classes[it] to probabilities[it] },
            "top3" to ordered.take(3).map { mapOf("action" to classes[it], "probability" to probabilities[it]) })
    }

    fun ensemble(logits: List<FloatArray>, version: String, method: String, visibility: Double, milliseconds: Double): Map<String, Any?> {
        require(logits.size == 3)
        val probabilities = logits.map(::softmax)
        val individual = probabilities.mapIndexed { i, p -> linkedMapOf<String, Any>("seed" to seeds[i]).apply { putAll(decision(p)) } }
        val aggregate = decision(average(probabilities))
        return linkedMapOf<String, Any?>().apply {
            putAll(aggregate)
            put("individual_models", individual)
            put("pose_detected", true); put("normalization_valid", true)
            put("schema_version", SCHEMA_VERSION); put("model_version", version)
            put("pipeline_version", PIPELINE_VERSION)
            put("recovery_method", method); put("mean_visibility", visibility); put("inference_ms", milliseconds)
            put("model_type", "exp1_full_head_attention")
            put("classifier_disagreement", individual.any { it["class_index"] != aggregate["class_index"] })
            put("warning", null)
        }
    }

    fun failed(version: String, milliseconds: Double): Map<String, Any?> {
        val empty = mapOf<String, Any?>("predicted_action" to null, "class_index" to null, "confidence" to 0.0,
            "probabilities" to emptyMap<String, Double>(), "top3" to emptyList<Any>())
        return linkedMapOf<String, Any?>().apply {
            putAll(empty)
            put("individual_models", seeds.map { empty + mapOf("seed" to it, "available" to false) })
            put("pose_detected", false); put("normalization_valid", false)
            put("schema_version", SCHEMA_VERSION); put("model_version", version)
            put("pipeline_version", PIPELINE_VERSION)
            put("recovery_method", "failed"); put("mean_visibility", null); put("inference_ms", milliseconds)
            put("warning", "Pose detection and recovery failed; individual classifiers were not run.")
        }
    }
}
