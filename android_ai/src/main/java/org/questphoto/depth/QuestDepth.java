package org.questphoto.depth;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.os.Debug;
import android.os.SystemClock;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;
import org.json.JSONObject;
import ai.onnxruntime.*;
import java.io.*;
import java.nio.*;
import java.nio.file.*;
import java.util.Collections;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;

/** One CPU session and one asynchronous conversion. No network or source writes. */
public final class QuestDepth extends GodotPlugin {
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final AtomicBoolean busy = new AtomicBoolean(false);
    private final AtomicBoolean cancelled = new AtomicBoolean(false);
    private final Object runLock = new Object();
    private volatile String status = "{\"state\":\"idle\"}";
    private volatile boolean destroyed;
    // Only accessed on worker, except runOptions which is protected by runLock.
    private OrtEnvironment environment;
    private OrtSession session;
    private String loadedModel = "";
    private OrtSession.RunOptions runOptions;

    public QuestDepth(Godot godot) { super(godot); }
    @Override public String getPluginName() { return "QuestDepth"; }
    @UsedByGodot public String get_status() { return status; }

    /** inverseDepth describes the raw output; it does NOT mutate saved depth. */
    @UsedByGodot public boolean start(String modelPath, String imagePath,
            String outputPath, int resolution, boolean inverseDepth) {
        if (destroyed || !busy.compareAndSet(false, true)) return false;
        cancelled.set(false);
        publish("loading", "Preparing model", "", 0, 0, outputPath, 0, 0, inverseDepth);
        try {
            worker.execute(() -> convert(modelPath, imagePath, outputPath, resolution, inverseDepth));
            return true;
        } catch (RejectedExecutionException error) {
            busy.set(false);
            publish("error", "Worker stopped", error.toString(), 0, 0, outputPath, 0, 0, inverseDepth);
            return false;
        }
    }

    @UsedByGodot public void cancel() {
        cancelled.set(true);
        synchronized (runLock) {
            if (runOptions != null) {
                try { runOptions.setTerminate(true); } catch (OrtException ignored) { }
            }
        }
    }

    /** Queued on the SAME worker, so a session is never closed underneath a run. */
    @UsedByGodot public void release_model() {
        cancel();
        if (!worker.isShutdown()) {
            try { worker.execute(this::closeSession); } catch (RejectedExecutionException ignored) { }
        }
    }

    @Override public void onMainDestroy() {
        destroyed = true;
        release_model();
        worker.shutdown(); // Never block the VR main thread waiting for inference.
        super.onMainDestroy();
    }

    private void checkCancelled() throws InterruptedException {
        if (cancelled.get() || destroyed) throw new InterruptedException("Conversion cancelled");
    }

    private void closeSession() {
        if (session != null) {
            try { session.close(); } catch (OrtException ignored) { }
            session = null;
        }
        loadedModel = "";
    }

    private void convert(String modelPath, String imagePath, String outputPath,
                         int resolution, boolean inverseDepth) {
        long startTime = SystemClock.elapsedRealtime();
        long inferenceMs = 0;
        Bitmap decoded = null, scaled = null;
        boolean ownsOutput = false;
        try {
            if (resolution < 196 || resolution > 700 || resolution % 14 != 0)
                throw new IOException("Inference side must be 196..700, multiple of 14");
            File model = new File(modelPath).getCanonicalFile();
            File input = new File(imagePath).getCanonicalFile();
            File output = new File(outputPath).getCanonicalFile();
            if (!model.isFile() || model.length() > 1024L * 1024 * 1024)
                throw new IOException("Missing model or model exceeds 1 GiB");
            if (!input.isFile() || input.length() > 32L * 1024 * 1024)
                throw new IOException("Missing input or input exceeds 32 MiB");
            if (output.equals(input) || output.equals(model) || output.exists())
                throw new IOException("Output already exists or aliases an input; refusing overwrite");
            if (!output.getParentFile().isDirectory()) throw new IOException("Output folder missing");
            checkCancelled();
            if (!model.getPath().equals(loadedModel)) {
                closeSession(); // Release previous network BEFORE constructing another.
                if (environment == null) environment = OrtEnvironment.getEnvironment();
                try (OrtSession.SessionOptions options = new OrtSession.SessionOptions()) {
                    options.setIntraOpNumThreads(2);
                    options.setInterOpNumThreads(1);
                    options.setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT);
                    options.setMemoryPatternOptimization(false);
                    options.setCPUArenaAllocator(false);
                    session = environment.createSession(model.getPath(), options);
                    if (session.getNumInputs() != 1 || !session.getInputNames().contains("image")
                            || !session.getOutputNames().contains("depth")) {
                        closeSession();
                        throw new IOException("Expected exported model with input image and output depth");
                    }
                    loadedModel = model.getPath();
                }
            }
            checkCancelled();
            publish("running", "Preparing photograph", "", 0, 0, outputPath, 0, 0, inverseDepth);
            BitmapFactory.Options bounds = new BitmapFactory.Options();
            bounds.inJustDecodeBounds = true;
            BitmapFactory.decodeFile(input.getPath(), bounds);
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0
                    || (long) bounds.outWidth * bounds.outHeight > 32L * 1024 * 1024)
                throw new IOException("Invalid image or more than 32 megapixels");
            BitmapFactory.Options decodeOptions = new BitmapFactory.Options();
            // Source is already orientation-corrected PNG from Godot. Sample before allocation.
            decodeOptions.inSampleSize = 1;
            while (Math.max(bounds.outWidth, bounds.outHeight) / decodeOptions.inSampleSize > resolution * 2)
                decodeOptions.inSampleSize *= 2;
            decodeOptions.inPreferredConfig = Bitmap.Config.ARGB_8888;
            decoded = BitmapFactory.decodeFile(input.getPath(), decodeOptions);
            if (decoded == null) throw new IOException("Android failed to decode working PNG");
            float ratio = (float) resolution / Math.max(decoded.getWidth(), decoded.getHeight());
            int width = Math.max(14, Math.round(decoded.getWidth() * ratio / 14) * 14);
            int height = Math.max(14, Math.round(decoded.getHeight() * ratio / 14) * 14);
            scaled = Bitmap.createScaledBitmap(decoded, width, height, true);
            int count = width * height;
            int[] pixels = new int[count];
            scaled.getPixels(pixels, 0, width, 0, 0, width, height);
            FloatBuffer floats = ByteBuffer.allocateDirect(count * 3 * 4)
                    .order(ByteOrder.nativeOrder()).asFloatBuffer();
            float[] means = {0.485f, 0.456f, 0.406f};
            float[] deviations = {0.229f, 0.224f, 0.225f};
            for (int channel = 0; channel < 3; channel++) {
                checkCancelled();
                for (int pixel : pixels)
                    floats.put((((pixel >> (16 - channel * 8)) & 255) / 255f - means[channel]) / deviations[channel]);
            }
            floats.rewind();
            checkCancelled();
            publish("running", "Estimating depth on device", "", 0, 0, outputPath, width, height, inverseDepth);
            try (OnnxTensor tensor = OnnxTensor.createTensor(environment, floats, new long[]{1, 3, height, width})) {
                synchronized (runLock) {
                    runOptions = new OrtSession.RunOptions();
                    if (cancelled.get()) runOptions.setTerminate(true);
                }
                long inferenceStart = SystemClock.elapsedRealtime();
                try (OrtSession.Result result = session.run(Collections.singletonMap("image", tensor), runOptions)) {
                    inferenceMs = SystemClock.elapsedRealtime() - inferenceStart;
                    checkCancelled();
                    OnnxValue value = result.get("depth").orElseThrow(() -> new IOException("Missing depth output"));
                    if (!(value instanceof OnnxTensor)) throw new IOException("Depth output is not a tensor");
                    OnnxTensor depth = (OnnxTensor) value;
                    long[] shape = depth.getInfo().getShape();
                    if (shape.length < 2 || shape.length > 4) throw new IOException("Invalid depth rank");
                    for (int i = 0; i < shape.length - 2; i++)
                        if (shape[i] != 1) throw new IOException("Only one depth frame is supported");
                    int outHeight = Math.toIntExact(shape[shape.length - 2]);
                    int outWidth = Math.toIntExact(shape[shape.length - 1]);
                    if (outWidth <= 0 || outHeight <= 0 || (long) outWidth * outHeight > 2 * 1024 * 1024)
                        throw new IOException("Depth output exceeds two megapixels");
                    FloatBuffer raw = depth.getFloatBuffer();
                    if (raw == null || raw.remaining() != outWidth * outHeight)
                        throw new IOException("Invalid float depth output");
                    DepthFile.write(output.toPath(), outWidth, outHeight, raw,
                            () -> cancelled.get() || destroyed);
                    ownsOutput = true;
                    checkCancelled();
                    publish("completed", "Depth ready", "", inferenceMs,
                            SystemClock.elapsedRealtime() - startTime, outputPath, outWidth, outHeight, inverseDepth);
                } finally {
                    synchronized (runLock) {
                        if (runOptions != null) { runOptions.close(); runOptions = null; }
                    }
                }
            }
        } catch (Exception | LinkageError | OutOfMemoryError error) {
            if (ownsOutput) new File(outputPath).delete(); // Only the file created by THIS job.
            boolean wasCancelled = cancelled.get() || error instanceof InterruptedException;
            publish(wasCancelled ? "cancelled" : "error", wasCancelled ? "Conversion cancelled" : "Inference failed",
                    error.toString(), inferenceMs, SystemClock.elapsedRealtime() - startTime, outputPath, 0, 0, inverseDepth);
            // Release native arena after a failure; leave prior disk conversions untouched.
            closeSession();
        } finally {
            if (scaled != null && scaled != decoded) scaled.recycle();
            if (decoded != null) decoded.recycle();
            busy.set(false);
        }
    }

    private void publish(String state, String message, String error, long inferenceMs,
                         long totalMs, String output, int width, int height, boolean inverseDepth) {
        try {
            JSONObject data = new JSONObject();
            data.put("state", state); data.put("message", message); data.put("error", error);
            data.put("inference_ms", inferenceMs); data.put("total_ms", totalMs);
            data.put("output_path", output); data.put("width", width); data.put("height", height);
            data.put("inverse_depth", inverseDepth); data.put("runtime", "ONNX Runtime 1.22.0 CPU");
            data.put("java_heap_bytes", Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory());
            data.put("native_heap_bytes", Debug.getNativeHeapAllocatedSize());
            // These are samples, NOT process peak RSS measurements.
            status = data.toString();
        } catch (Exception impossible) { status = "{\"state\":\"error\",\"error\":\"Status serialization failed\"}"; }
    }
}
