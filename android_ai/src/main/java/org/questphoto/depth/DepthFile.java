package org.questphoto.depth;

import java.io.*;
import java.nio.FloatBuffer;
import java.nio.file.*;
import java.util.function.BooleanSupplier;

/** Lossless raw-depth interchange; has no Android dependencies and is tested on desktop. */
public final class DepthFile {
    private DepthFile() { }

    public static void write(Path output, int width, int height, FloatBuffer raw,
                             BooleanSupplier cancelled) throws IOException, InterruptedException {
        if (width <= 0 || height <= 0 || (long) width * height > 2 * 1024 * 1024
                || raw == null || raw.remaining() != width * height)
            throw new IOException("Invalid depth dimensions or sample count");
        if (cancelled.getAsBoolean()) throw new InterruptedException("Conversion cancelled");
        boolean owned = false;
        try {
            // Atomic exclusive creation: never truncates an original, result, or symlink.
            try (OutputStream stream = Files.newOutputStream(output, StandardOpenOption.CREATE_NEW,
                    StandardOpenOption.WRITE);
                 BufferedOutputStream buffered = new BufferedOutputStream(stream)) {
                owned = true;
                buffered.write(new byte[]{'Q', 'P', 'D', '1'});
                writeIntLE(buffered, width);
                writeIntLE(buffered, height);
                int position = 0;
                while (raw.hasRemaining()) {
                    if ((position++ & 4095) == 0 && cancelled.getAsBoolean())
                        throw new InterruptedException("Conversion cancelled");
                    float sample = raw.get();
                    if (!Float.isFinite(sample)) throw new IOException("Model returned nonfinite depth");
                    writeIntLE(buffered, Float.floatToRawIntBits(sample));
                }
            }
        } catch (IOException | InterruptedException | RuntimeException | Error error) {
            // Never delete a pre-existing file: only this invocation can own this path.
            if (owned) {
                try { Files.deleteIfExists(output); } catch (IOException cleanup) { error.addSuppressed(cleanup); }
            }
            throw error;
        }
    }

    private static void writeIntLE(OutputStream stream, int value) throws IOException {
        stream.write(value); stream.write(value >>> 8); stream.write(value >>> 16); stream.write(value >>> 24);
    }
}
