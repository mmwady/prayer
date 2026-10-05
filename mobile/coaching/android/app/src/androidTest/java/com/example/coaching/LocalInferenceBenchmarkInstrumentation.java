package com.example.coaching;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.Intent;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.WindowManager;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.*;
import java.lang.reflect.Method;
import java.security.MessageDigest;
import java.util.*;

/** Java-only runner also works against an R8 release without relying on renamed Kotlin runtime classes. */
public final class LocalInferenceBenchmarkInstrumentation extends Instrumentation {
    private String label = "baseline";
    @Override public void onCreate(Bundle arguments) {
        super.onCreate(arguments);
        if (arguments != null) label = arguments.getString("label", label);
        if (!label.matches("[a-zA-Z0-9_-]+") || label.contains("gpu")) throw new IllegalArgumentException("Use the separate GPU runner");
        start();
    }
    @Override public void onStart() {
        Activity activity = null;
        try {
            activity = startActivitySync(new Intent().setClassName(getTargetContext(), "com.example.coaching.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            final Activity active = activity;
            runOnMainSync(() -> active.getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON));
            java.lang.reflect.Field field = activity.getClass().getDeclaredField("localInference");
            field.setAccessible(true);
            Object engine = field.get(activity);
            Method initialize = engine.getClass().getDeclaredMethod("initialize"); initialize.setAccessible(true);
            boolean deferred = label.contains("deferred");
            Method analyze = engine.getClass().getDeclaredMethod(deferred ? "analyzeDeferred" : "analyze", byte[].class, boolean.class); analyze.setAccessible(true);
            Method render = deferred ? engine.getClass().getDeclaredMethod("renderPreview", Long.class) : null;
            if (render != null) render.setAccessible(true);
            long began = SystemClock.elapsedRealtimeNanos();
            Map<?,?> info = (Map<?,?>) initialize.invoke(engine);
            double initializationMs = (SystemClock.elapsedRealtimeNanos() - began)/1e6;
            ArrayList<String> names = new ArrayList<>();
            for (String name : getContext().getAssets().list("inference")) if (name.endsWith(".jpg")) names.add(name);
            Collections.sort(names);
            if (names.size() < 100) throw new IllegalStateException("Expected at least 100 real local frames");
            File folder = getTargetContext().getExternalFilesDir(null);
            if (folder == null) folder = getTargetContext().getCacheDir();
            File output = new File(folder, "inference-" + label + ".json");
            write(output, "{\"status\":\"running\"}");
            byte[] warm = fixture(names.get(0));
            for (int i=0;i<3;i++) analyze.invoke(engine, warm, false);
            JSONArray cases = new JSONArray();
            for (int i=0;i<names.size();i++) {
                byte[] bytes = fixture(names.get(i));
                long start = SystemClock.elapsedRealtimeNanos();
                Map<?,?> answer = (Map<?,?>) analyze.invoke(engine, bytes, true);
                double totalMs = (SystemClock.elapsedRealtimeNanos()-start)/1e6;
                Map<?,?> prediction = (Map<?,?>) answer.get("result");
                JSONObject decision = new JSONObject(prediction); decision.remove("inference_ms");
                long previewStart = SystemClock.elapsedRealtimeNanos();
                byte[] preview = deferred && answer.get("preview_token") != null
                    ? (byte[]) render.invoke(engine, answer.get("preview_token")) : (byte[]) answer.get("preview_jpeg");
                double previewMs = deferred ? (SystemClock.elapsedRealtimeNanos()-previewStart)/1e6 : 0;
                JSONObject entry = new JSONObject().put("name", names.get(i)).put("total_ms", totalMs).put("preview_ms", previewMs)
                    .put("inference_ms", prediction.get("inference_ms")).put("prediction", decision)
                    .put("features", answer.get("features") == null ? JSONObject.NULL : new JSONArray((Collection<?>) answer.get("features")))
                    .put("preview_sha256", preview == null ? JSONObject.NULL : sha(preview)).put("preview_bytes", preview == null ? 0 : preview.length);
                cases.put(entry);
                if ((i+1)%10 == 0) { Bundle status = new Bundle(); status.putString("stream", label + ": " + (i+1) + "/" + names.size() + "\n"); sendStatus(0, status); }
            }
            JSONObject report = new JSONObject().put("label", label).put("provider", "cpu").put("device", android.os.Build.MODEL)
                .put("android", android.os.Build.VERSION.RELEASE).put("model_version", info.get("model_version"))
                .put("initialization_ms", initializationMs).put("cases", cases);
            write(output, report.toString());
            Bundle result = new Bundle(); result.putString("stream", "PASS: " + names.size() + " physical-device frames; report=" + output + "\n");
            finish(Activity.RESULT_OK, result);
        } catch (Throwable failure) {
            StringWriter trace = new StringWriter(); failure.printStackTrace(new PrintWriter(trace));
            Bundle result = new Bundle(); result.putString("stream", "FAIL: " + trace + "\n"); finish(Activity.RESULT_CANCELED, result);
        } finally {
            if (activity != null) { final Activity active = activity; runOnMainSync(active::finish); }
        }
    }
    private byte[] fixture(String name) throws IOException {
        try (InputStream input = getContext().getAssets().open("inference/" + name); ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[65536]; int count;
            while ((count=input.read(buffer)) != -1) output.write(buffer,0,count);
            return output.toByteArray();
        }
    }
    private static void write(File file, String text) throws IOException {
        try (Writer writer = new OutputStreamWriter(new FileOutputStream(file), "UTF-8")) { writer.write(text); }
    }
    private static String sha(byte[] bytes) throws Exception {
        byte[] digest = MessageDigest.getInstance("SHA-256").digest(bytes);
        StringBuilder result = new StringBuilder(); for (byte b : digest) result.append(String.format(Locale.ROOT, "%02x", b & 255));
        return result.toString();
    }
}
