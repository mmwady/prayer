package com.example.coaching

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.util.Base64
import kotlin.math.abs

class LocalInferenceParityTest {
    private val browser = File(requireNotNull(System.getProperty("iqtadi.browser")))
    private fun array(name: String) = JSONArray(File(browser, "test/fixtures/$name").readText())
    private fun floats(values: JSONArray) = FloatArray(values.length()) { values.getDouble(it).toFloat() }

    @Test fun identicalPythonLandmarksProduceIdenticalFloat32Features() {
        val p = JSONObject(File(browser, "assets/preprocessing.json").readText())
        val fixtures = array("landmarks.json")
        var maximumError = 0.0
        for (i in 0 until fixtures.length()) {
            val fixture = fixtures.getJSONObject(i); val raw = fixture.getJSONArray("landmarks")
            val points = (0 until raw.length()).map { k -> raw.getJSONObject(k).let {
                LocalInferenceMath.Landmark(it.getDouble("x").toFloat(), it.getDouble("y").toFloat(), it.getDouble("z").toFloat(),
                    it.getDouble("visibility").toFloat(), it.getDouble("presence").toFloat())
            } }
            val actual = LocalInferenceMath.features(points, floats(p.getJSONArray("mean")), floats(p.getJSONArray("std")))!!
            val expected = fixture.getJSONArray("features")
            assertEquals(166, actual.size); assertEquals(1f, actual[165], 0f)
            for (j in actual.indices) {
                val reference = expected.getDouble(j); val error = abs(reference - actual[j].toDouble())
                maximumError = maxOf(maximumError, error)
                assertTrue("fixture=$i feature=$j error=$error", error <= 2e-5 + 2e-6 * abs(reference))
            }
        }
        println("Android float32 preprocessing: ${fixtures.length()} Python fixtures, max_abs_error=$maximumError")
    }

    @Test fun pillowLanczosLetterboxAndAllRecoveryCandidatesArePixelExact() {
        val fixtures = array("pixels.json")
        for (i in 0 until fixtures.length()) {
            val fixture = fixtures.getJSONObject(i)
            val image = LocalInferenceImage.Rgb(fixture.getInt("width"), fixture.getInt("height"), Base64.getDecoder().decode(fixture.getString("rgb")))
            val prepared = LocalInferenceImage.letterbox(image); val candidates = fixture.getJSONArray("candidates")
            for (j in 0 until candidates.length()) {
                assertArrayEquals("Pillow fixture $i recovery $j", Base64.getDecoder().decode(candidates.getString(j)), LocalInferenceImage.recovery(prepared, j).data)
            }
        }
        println("Android Pillow image transforms: ${fixtures.length() * 5} pixel-exact candidates")
    }

    @Test fun preprocessingRejectsInvalidOrNonfinitePoses() {
        val mean = FloatArray(165); val std = FloatArray(165) { 1f }
        val point = LocalInferenceMath.Landmark(0f, 0f, 0f, 1f, 1f)
        assertNull(LocalInferenceMath.features(emptyList(), mean, std))
        assertNull(LocalInferenceMath.features(List(33) { point }, mean, std))
        val valid = List(33) { i -> point.copy(x = i / 33f, y = if (i < 23) .2f else .7f) }
        assertNotNull(LocalInferenceMath.features(valid, mean, std))
        for (bad in listOf(point.copy(x = Float.NaN), point.copy(visibility = Float.NaN), point.copy(presence = Float.POSITIVE_INFINITY))) {
            assertNull(LocalInferenceMath.features(valid.toMutableList().apply { set(0, bad) }, mean, std))
        }
    }

    @Test fun perModelSoftmaxThenArithmeticMeanRetainsDisagreement() {
        val logits = listOf(floatArrayOf(8f, 0f, 0f, 0f, 0f, 0f, 0f, 0f), floatArrayOf(0f, 9f, 0f, 0f, 0f, 0f, 0f, 0f), floatArrayOf(7f, 0f, 0f, 0f, 0f, 0f, 0f, 0f))
        val result = LocalInferenceMath.ensemble(logits, "test", "standard", .9, 10.0)
        assertEquals(0, result["class_index"]); assertEquals(true, result["classifier_disagreement"])
        @Suppress("UNCHECKED_CAST") val models = result["individual_models"] as List<Map<String, Any>>
        assertEquals(LocalInferenceMath.seeds, models.map { it["seed"] }); assertEquals(1, models[1]["class_index"])
        @Suppress("UNCHECKED_CAST") val probabilities = result["probabilities"] as Map<String, Double>
        val individual = logits.map(LocalInferenceMath::softmax)
        LocalInferenceMath.classes.forEachIndexed { i, c -> assertEquals(individual.sumOf { it[i] } / 3, probabilities[c]!!, 0.0) }
        val extreme = LocalInferenceMath.softmax(floatArrayOf(1000f, 999f, -1000f, 0f, 0f, 0f, 0f, 0f))
        assertEquals(1.0, extreme.sum(), 1e-12); assertTrue(extreme[0] > extreme[1])
        assertEquals(7, LocalInferenceMath.decision(DoubleArray(8) { .125 })["class_index"])
    }

    @Test fun failedPoseStillHasThreeExplicitUnavailableModels() {
        val result = LocalInferenceMath.failed("test", 10.0)
        assertEquals("2.0.0", result["schema_version"]); assertEquals(false, result["pose_detected"])
        @Suppress("UNCHECKED_CAST") val models = result["individual_models"] as List<Map<String, Any?>>
        assertEquals(3, models.size); assertTrue(models.all { it["available"] == false && it["predicted_action"] == null })
        assertNotNull(result["warning"])
    }

    @Test fun aspectRatioNeverUpscalesAndExifTransformsAreDiscrete() {
        assertEquals(100 to 80, LocalInferenceImage.thumbnailSize(100, 80))
        assertEquals(384 to 192, LocalInferenceImage.thumbnailSize(800, 400))
        assertEquals(256 to 512, LocalInferenceImage.thumbnailSize(400, 800))
        val image = LocalInferenceImage.Rgb(2, 1, byteArrayOf(1, 2, 3, 4, 5, 6))
        val mirrored = LocalInferenceImage.orient(image, 2)
        assertArrayEquals(byteArrayOf(4, 5, 6, 1, 2, 3), mirrored.data)
        for (orientation in 5..8) { val value = LocalInferenceImage.orient(image, orientation); assertEquals(1, value.width); assertEquals(2, value.height) }
    }
}
