plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.coaching"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    testBuildType = providers.gradleProperty("iqtadiTestBuildType").orElse("debug").get()

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.coaching"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        testInstrumentationRunner = providers.gradleProperty("iqtadiTestRunner")
            .orElse("com.example.coaching.ExtractionInstrumentation").get()
    }

    sourceSets.getByName("androidTest").assets.srcDir("../../build/extraction-fixtures")
    sourceSets.getByName("androidTest").assets.srcDir("../../build/inference-fixtures")
    // One authoritative asset set shared with the browser export; APK builds copy
    // only static models/normalization data, never acceptance photos or videos.
    sourceSets.getByName("main").assets.srcDir(layout.buildDirectory.dir("generated/local-inference-assets"))
    androidResources { noCompress += listOf("onnx", "task") }

    buildTypes {
        release {
            proguardFiles("proguard-rules.pro")
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.google.mediapipe:tasks-vision:0.10.32")
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.23.2")
    implementation("androidx.exifinterface:exifinterface:1.4.1")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}

val prepareLocalInferenceAssets by tasks.registering(Copy::class) {
    from(file("../../browser/assets")) {
        include("manifest.json", "preprocessing.json", "model_metadata.json",
            "pose_landmarker_heavy.task", "main_seed_2026.onnx", "main_seed_3407.onnx", "main_seed_8111.onnx")
    }
    into(layout.buildDirectory.dir("generated/local-inference-assets/iqtadi/models"))
    doFirst {
        for (name in listOf("manifest.json", "preprocessing.json", "model_metadata.json", "pose_landmarker_heavy.task",
                "main_seed_2026.onnx", "main_seed_3407.onnx", "main_seed_8111.onnx")) {
            require(file("../../browser/assets/$name").isFile) {
                "Missing local asset $name. Run browser/tools/export_models.py before building native local inference."
            }
        }
    }
}
tasks.configureEach {
    if (name.startsWith("merge") && name.endsWith("Assets")) dependsOn(prepareLocalInferenceAssets)
}

tasks.withType<Test>().configureEach {
    systemProperty("iqtadi.browser", file("../../browser").absolutePath)
}
