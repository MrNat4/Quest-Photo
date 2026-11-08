package org.questphoto.depth;
import android.content.*;
import android.database.*;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.shadows.ShadowContentResolver;
import org.json.JSONObject;
import org.junit.*;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;
import java.io.*;
import java.nio.file.*;
import java.util.*;
import static org.junit.Assert.*;

/** Typed ContentResolver calls with a fault-injecting local provider; not Quest MediaStore. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk=29,manifest=Config.NONE)
public class SharedImageExportTest {
    private ContentResolver resolver;
    private Provider provider;
    private File original;
    public static class Provider extends ContentProvider {
        String fail=""; int next=0,deleted=0;
        Map<Uri,ContentValues> rows=new HashMap<>(); Map<Uri,File> files=new HashMap<>();
        public boolean onCreate(){return true;}
        public String getType(Uri u){return "image/png";}
        public Uri insert(Uri u,ContentValues v){
            if(fail.equals("insert"))return null;
            Uri own=Uri.parse("content://media/external_primary/images/media/"+(++next));
            try {files.put(own,File.createTempFile("media-test",".image"));}catch(IOException e){throw new RuntimeException(e);}
            rows.put(own,new ContentValues(v));return own;
        }
        public ParcelFileDescriptor openFile(Uri u,String mode)throws FileNotFoundException {
            if(fail.equals(mode.equals("w")?"write":"read"))throw new FileNotFoundException("injected "+mode);
            if(mode.equals("r")&&fail.equals("corrupt"))try{Files.write(files.get(u).toPath(),new byte[]{9});}catch(IOException e){throw new RuntimeException(e);}
            return ParcelFileDescriptor.open(files.get(u),mode.equals("w")?ParcelFileDescriptor.MODE_WRITE_ONLY|ParcelFileDescriptor.MODE_TRUNCATE:ParcelFileDescriptor.MODE_READ_ONLY);
        }
        public int update(Uri u,ContentValues v,String where,String[] args){assertNull(where);assertNull(args);if(fail.equals("finalize"))return 0;rows.get(u).putAll(v);return 1;}
        public Cursor query(Uri u,String[] fields,String where,String[] args,String order){
            assertNull(where);assertNull(args);assertNull(order);
            if(fail.equals("query"))return null;
            MatrixCursor c=new MatrixCursor(fields);ContentValues v=rows.get(u);
            c.addRow(new Object[]{v.getAsString("_display_name"),fail.equals("folder")?"Pictures/Wrong/":v.getAsString("relative_path"),fail.equals("pending")?1:v.getAsInteger("is_pending")});return c;
        }
        public int delete(Uri u,String where,String[] args){assertTrue(rows.containsKey(u));rows.remove(u);files.remove(u).delete();deleted++;return 1;}
    }
    @Before public void setup()throws Exception {
        resolver=RuntimeEnvironment.getApplication().getContentResolver();provider=new Provider();android.content.pm.ProviderInfo info=new android.content.pm.ProviderInfo();info.authority="media";provider.attachInfo(RuntimeEnvironment.getApplication(),info);ShadowContentResolver.registerProviderInternal("media",provider);
        original=File.createTempFile("source.half-sbs", ".png");byte[] b=new byte[600001];new Random(1).nextBytes(b);Files.write(original.toPath(),b);
    }
    @Test public void repeatedPngJpegReadbackAndNoOverwrite()throws Exception {
        byte[] before=Files.readAllBytes(original.toPath());Set<String> names=new HashSet<>();
        for(String mime:Arrays.asList("image/png","image/jpeg","image/png")){
            JSONObject result=new JSONObject(SharedImageExport.publish(resolver,original.toString(),mime));
            assertFalse(result.toString(),result.has("error"));assertTrue(result.getBoolean("verified"));assertEquals(before.length,result.getLong("bytes"));assertTrue(names.add(result.getString("destination")));
            assertArrayEquals(before,Files.readAllBytes(provider.files.get(Uri.parse(result.getString("uri"))).toPath()));
        }
        assertEquals(3,provider.rows.size());assertEquals(0,provider.deleted);assertArrayEquals(before,Files.readAllBytes(original.toPath()));
    }
    @Test public void errorsRollbackOnlyOwnRowAndRetryWorks()throws Exception {
        byte[] before=Files.readAllBytes(original.toPath());
        JSONObject good=new JSONObject(SharedImageExport.publish(resolver,original.toString(),"image/png"));Uri old=Uri.parse(good.getString("uri"));
        for(String fault:Arrays.asList("insert","write","read","corrupt","finalize","query","folder","pending")){
            provider.fail=fault;JSONObject failed=new JSONObject(SharedImageExport.publish(resolver,original.toString(),"image/png"));
            assertTrue(fault+failed,failed.has("error"));assertTrue(failed.getString("error").contains(":"));assertEquals(fault,1,provider.rows.size());assertTrue(provider.rows.containsKey(old));assertArrayEquals(before,Files.readAllBytes(original.toPath()));
        }
        provider.fail="";assertTrue(new JSONObject(SharedImageExport.publish(resolver,original.toString(),"image/jpeg")).getBoolean("verified"));
    }
    @Test public void realEncodedFullHalfPngJpegRoundTrip() throws Exception {
        Path directory=Files.createTempDirectory("sbs-roundtrip");
        for(boolean half:Arrays.asList(false,true)) for(boolean jpeg:Arrays.asList(false,true)) {
            String suffix=(half?".half-sbs":".sbs")+(jpeg?".jpg":".png");
            Path input=directory.resolve("image"+suffix);
            android.graphics.Bitmap bitmap=android.graphics.Bitmap.createBitmap(half?16:32,16,android.graphics.Bitmap.Config.ARGB_8888);
            bitmap.eraseColor(0xff00aaff);
            try(OutputStream out=Files.newOutputStream(input)) {assertTrue(bitmap.compress(jpeg?android.graphics.Bitmap.CompressFormat.JPEG:android.graphics.Bitmap.CompressFormat.PNG,95,out));}
            bitmap.recycle();byte[] source=Files.readAllBytes(input);
            JSONObject result=new JSONObject(SharedImageExport.publish(resolver,input.toString(),jpeg?"image/jpeg":"image/png"));
            assertTrue(result.toString(),result.getBoolean("verified"));assertTrue(result.getString("destination").endsWith(suffix));
            File saved=provider.files.get(Uri.parse(result.getString("uri")));
            assertArrayEquals(source,Files.readAllBytes(saved.toPath()));
            android.graphics.Bitmap decoded=android.graphics.BitmapFactory.decodeFile(saved.toString());
            assertNotNull(decoded);assertEquals(half?16:32,decoded.getWidth());assertEquals(16,decoded.getHeight());decoded.recycle();
            assertArrayEquals(source,Files.readAllBytes(input));Files.delete(input);
        }
        Files.delete(directory);
    }
    @Test public void exportMethodIsPublicAnnotatedAndGodotCompatible() throws Exception {
        java.lang.reflect.Method method=QuestDepth.class.getDeclaredMethod("export_image",String.class,String.class);
        assertTrue(java.lang.reflect.Modifier.isPublic(method.getModifiers()));
        assertEquals(String.class,method.getReturnType());
        assertNotNull(method.getAnnotation(org.godotengine.godot.plugin.UsedByGodot.class));
    }
    @After public void cleanup(){original.delete();for(File file:provider.files.values())file.delete();}
}
