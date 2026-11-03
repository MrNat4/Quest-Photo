package org.questphoto.depth;

import android.content.ContentResolver;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.provider.MediaStore;
import org.json.JSONObject;
import java.io.*;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.UUID;

/** Typed, per-call MediaStore transaction. Never updates an existing image or input. */
public final class SharedImageExport {
    private SharedImageExport() {}
    public static String publish(ContentResolver resolver, String path, String mime) {
        Uri created = null;
        String stage = "validate input";
        try {
            if (Build.VERSION.SDK_INT < 29) throw new IOException("Android 10 or newer required");
            if (resolver == null) throw new IOException("ContentResolver unavailable");
            if (!mime.equals("image/png") && !mime.equals("image/jpeg")) throw new IOException("PNG/JPEG only");
            File input = new File(path).getCanonicalFile();
            if (!input.isFile() || input.length() < 12) throw new IOException("Encoded export is missing or empty");
            // Only READ from the source. No operation in this class deletes or edits it.
            String ext = mime.equals("image/png") ? ".png" : ".jpg";
            String layout = input.getName().contains(".half-sbs.") ? ".half-sbs" : ".sbs";
            String name = "ZDim_" + System.currentTimeMillis() + "_" + UUID.randomUUID() + layout + ext;
            stage = "insert pending MediaStore image";
            ContentValues values = new ContentValues();
            values.put(MediaStore.Images.Media.DISPLAY_NAME, name);
            values.put(MediaStore.Images.Media.MIME_TYPE, mime);
            values.put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Z-Dim/");
            values.put(MediaStore.Images.Media.IS_PENDING, 1);
            created = resolver.insert(MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY), values);
            if (created == null) throw new IOException("Provider returned no new URI");
            stage = "write and close new image";
            MessageDigest expected = MessageDigest.getInstance("SHA-256");
            long copied = 0;
            byte[] buffer = new byte[256 * 1024];
            try (InputStream source = new FileInputStream(input);
                 OutputStream destination = resolver.openOutputStream(created, "w")) {
                if (destination == null) throw new IOException("Provider returned no output stream");
                int count;
                while ((count = source.read(buffer)) != -1) {
                    destination.write(buffer, 0, count);
                    expected.update(buffer, 0, count);
                    copied += count;
                }
                destination.flush();
            }
            if (copied != input.length()) throw new IOException("Source size changed during export");
            stage = "verify stored bytes";
            // Read actual bytes, avoiding getStatSize()=-1 on non-file-backed providers.
            MessageDigest actual = MessageDigest.getInstance("SHA-256");
            long verified = 0;
            try (InputStream saved = resolver.openInputStream(created)) {
                if (saved == null) throw new IOException("Provider returned no input stream");
                int count;
                while ((count = saved.read(buffer)) != -1) {
                    actual.update(buffer, 0, count); verified += count;
                }
            }
            if (verified != copied || !Arrays.equals(expected.digest(), actual.digest()))
                throw new IOException("Saved bytes differ from encoded export");
            stage = "finalize MediaStore image";
            ContentValues done = new ContentValues();
            done.put(MediaStore.Images.Media.IS_PENDING, 0);
            // Java null selections are intentional; no dynamic overload/null coercion.
            if (resolver.update(created, done, null, null) != 1)
                throw new IOException("Provider did not finalize exactly one image");
            stage = "verify published destination";
            String[] projection = {MediaStore.Images.Media.DISPLAY_NAME, MediaStore.Images.Media.RELATIVE_PATH,
                    MediaStore.Images.Media.IS_PENDING};
            try (Cursor row = resolver.query(created, projection, null, null, null)) {
                if (row == null || !row.moveToFirst()) throw new IOException("Published image record not found");
                name = row.getString(0);
                String folder = row.getString(1);
                if (name == null || name.isEmpty() || !("Pictures/Z-Dim/".equals(folder) || "Pictures/Z-Dim".equals(folder))
                        || row.getInt(2) != 0) throw new IOException("Image is not published in Pictures/Z-Dim");
            }
            return new JSONObject().put("uri", created.toString()).put("destination", "Pictures/Z-Dim/" + name)
                    .put("bytes", copied).put("verified", true).toString();
        } catch (Exception failure) {
            String detail = failure.getMessage();
            String message = stage + ": " + failure.getClass().getSimpleName() +
                    (detail == null || detail.isEmpty() ? "" : " — " + detail);
            if (created != null) {
                try {
                    if (resolver.delete(created, null, null) != 1) message += "; cleanup could not remove new row " + created;
                } catch (Exception cleanup) {
                    message += "; cleanup failed for " + created + ": " + cleanup.getClass().getSimpleName();
                }
            }
            try { return new JSONObject().put("error", message).toString(); }
            catch (Exception impossible) { return "{\"error\":\"Export transaction failed\"}"; }
        }
    }
}
