package org.questphoto.depth;

import android.graphics.Bitmap;
import org.junit.*;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;
import org.json.JSONObject;
import java.io.*;
import java.nio.*;
import java.nio.file.*;
import java.util.*;
import static org.junit.Assert.*;

/** Runs the actual Java plugin + ONNX Runtime CPU under Robolectric, not a headset. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk=28, manifest=Config.NONE)
public class QuestDepthTest {
    private QuestDepth plugin;
    private Path folder, model, photo;
    @Before public void setup() throws Exception {
        folder=Files.createTempDirectory("quest-plugin-test");
        model=folder.resolve("model.onnx");
        try(InputStream in=getClass().getResourceAsStream("/bridge_fixture.onnx")) { Files.copy(in,model); }
        photo=folder.resolve("photo.png");
        Bitmap b=Bitmap.createBitmap(56,28,Bitmap.Config.ARGB_8888); b.eraseColor(0xffff0000);
        try(OutputStream out=Files.newOutputStream(photo)) { assertTrue(b.compress(Bitmap.CompressFormat.PNG,100,out)); }
        b.recycle(); plugin=new QuestDepth(null);
    }
    private JSONObject terminal() throws Exception {
        long until=System.currentTimeMillis()+30000;
        while(System.currentTimeMillis()<until) {
            JSONObject status=new JSONObject(plugin.get_status());
            if(Arrays.asList("completed","cancelled","error").contains(status.getString("state"))) {
                // Allow the worker finally block to finish before the next job.
                Thread.sleep(30); return status;
            }
            Thread.sleep(10);
        }
        throw new AssertionError("plugin timed out: "+plugin.get_status());
    }
    private JSONObject run(Path network, Path output, int size) throws Exception {
        assertTrue(plugin.start(network.toString(),photo.toString(),output.toString(),size,true));
        return terminal();
    }
    @Test public void realRuntimePreprocessOutputAndSessionReuse() throws Exception {
        byte[] original=Files.readAllBytes(photo);
        Path out=folder.resolve("a.qpd");
        JSONObject first=run(model,out,364); assertEquals(first.toString(),"completed",first.getString("state"));
        ByteBuffer depth=ByteBuffer.wrap(Files.readAllBytes(out)).order(ByteOrder.LITTLE_ENDIAN);
        assertEquals(0x31445051,depth.getInt()); assertEquals(364,depth.getInt()); assertEquals(182,depth.getInt());
        float expected=((1f-.485f)/.229f+(0f-.456f)/.224f+(0f-.406f)/.225f)/3f;
        assertEquals(expected,depth.getFloat(),1e-5f);
        JSONObject second=run(model,folder.resolve("b.qpd"),518);
        assertEquals("completed",second.getString("state")); assertEquals(1,second.getInt("sessions_opened"));
        assertArrayEquals(original,Files.readAllBytes(photo));
    }
    @Test public void switchClosesPreviousAndPreservesOutputs() throws Exception {
        Path out=folder.resolve("a.qpd"); assertEquals("completed",run(model,out,364).getString("state"));
        byte[] saved=Files.readAllBytes(out);
        Path other=folder.resolve("other.onnx"); Files.copy(model,other);
        JSONObject status=run(other,folder.resolve("b.qpd"),364);
        assertEquals("completed",status.getString("state")); assertEquals(2,status.getInt("sessions_opened"));assertEquals(1,status.getInt("sessions_closed"));
        assertArrayEquals(saved,Files.readAllBytes(out));
    }
    @Test public void cancellationAndBusyGuard() throws Exception {
        Path out=folder.resolve("cancel.qpd");
        assertTrue(plugin.start(model.toString(),photo.toString(),out.toString(),518,true));
        assertFalse(plugin.start(model.toString(),photo.toString(),folder.resolve("second.qpd").toString(),518,true));
        plugin.cancel();JSONObject status=terminal(); assertEquals(status.toString(),"cancelled",status.getString("state"));
        assertFalse(Files.exists(out));
        assertEquals("completed",run(model,folder.resolve("retry.qpd"),364).getString("state"));
    }
    @Test public void existingOutputAndBadModelDoNotChangeOriginals() throws Exception {
        byte[] original=Files.readAllBytes(photo);
        assertEquals("error",run(model,photo,364).getString("state")); assertArrayEquals(original,Files.readAllBytes(photo));
        Path bad=folder.resolve("bad.onnx");Files.write(bad,new byte[]{1,2,3});
        assertEquals("error",run(bad,folder.resolve("bad.qpd"),364).getString("state"));
        assertFalse(Files.exists(folder.resolve("bad.qpd")));
        assertEquals("completed",run(model,folder.resolve("retry.qpd"),364).getString("state"));
    }
    @After public void cleanup() throws Exception { if(plugin!=null)plugin.onMainDestroy(); }
}
