import org.questphoto.depth.DepthFile;
import java.nio.*;
import java.nio.file.*;
import java.security.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;

public class DepthFileTest {
    private static int checks;
    private static void check(boolean value, String message) {
        checks++;
        if (!value) throw new AssertionError(message);
    }
    public static void main(String[] arguments) throws Exception {
        Path folder = Files.createTempDirectory("quest-depth-file-test");
        try {
            Path output = folder.resolve("output.qpd");
            float[] values = {-0f, 0.3f, 12.5f, -12.75f, Float.MIN_VALUE, Float.MAX_VALUE};
            DepthFile.write(output, 3, 2, FloatBuffer.wrap(values), () -> false);
            byte[] before = Files.readAllBytes(output);
            ByteBuffer read = ByteBuffer.wrap(before).order(ByteOrder.LITTLE_ENDIAN);
            check(read.getInt() == 0x31445051, "QPD1 magic");
            check(read.getInt() == 3 && read.getInt() == 2, "dimensions little endian");
            for (float value : values) check(read.getInt() == Float.floatToRawIntBits(value), "raw float bits unchanged");
            check(!read.hasRemaining(), "exact file length");
            byte[] hash = MessageDigest.getInstance("SHA-256").digest(before);
            try {
                DepthFile.write(output, 3, 2, FloatBuffer.wrap(new float[6]), () -> false);
                throw new AssertionError("existing destination overwritten");
            } catch (FileAlreadyExistsException expected) { checks++; }
            check(Arrays.equals(hash, MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(output))), "existing file SHA-256 unchanged");
            Path invalid = folder.resolve("invalid.qpd");
            try {
                DepthFile.write(invalid, 1, 1, FloatBuffer.wrap(new float[]{Float.NaN}), () -> false);
                throw new AssertionError("NaN accepted");
            } catch (java.io.IOException expected) { check(!Files.exists(invalid), "failed output cleaned"); }
            Path cancelled = folder.resolve("cancelled.qpd");
            AtomicInteger polls = new AtomicInteger();
            try {
                DepthFile.write(cancelled, 100, 100, FloatBuffer.wrap(new float[10000]), () -> polls.incrementAndGet() > 2);
                throw new AssertionError("cancellation ignored");
            } catch (InterruptedException expected) { check(!Files.exists(cancelled), "partially cancelled output cleaned"); }
            Path symlink = folder.resolve("symlink.qpd");
            try {
                Files.createSymbolicLink(symlink, output);
                try {
                    DepthFile.write(symlink, 1, 1, FloatBuffer.wrap(new float[1]), () -> false);
                    throw new AssertionError("symlink destination overwritten");
                } catch (FileAlreadyExistsException expected) { checks++; }
                check(Files.isSymbolicLink(symlink), "pre-existing symlink retained");
                check(Arrays.equals(hash, MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(output))), "symlink target SHA-256 unchanged");
            } catch (UnsupportedOperationException | java.nio.file.FileSystemException unavailable) {
                System.out.println("Symlink test unavailable on this filesystem: " + unavailable);
            }
            System.out.println("PASS: " + checks + " real Java depth-file checks (not Android inference)");
        } finally {
            try (java.util.stream.Stream<Path> paths = Files.walk(folder)) {
                paths.sorted(Comparator.reverseOrder()).forEach(path -> { try { Files.delete(path); } catch (Exception ignored) { } });
            }
        }
    }
}
