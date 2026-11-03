"""Source delivery contract; no APK build or model conversion."""
from pathlib import Path
import hashlib,io,json,unittest,zipfile
ROOT=Path(__file__).resolve().parents[1]
class DeliveryTests(unittest.TestCase):
 def test_versions_and_gradle(self):
  self.assertIn('config/version="0.3.3"',(ROOT/'project.godot').read_text())
  p=(ROOT/'export_presets.cfg').read_text()
  for value in ['version/name="0.3.3"','version/code=6','quest-photo-0.3.3-debug.apk','plugins/QuestDepth=true','gradle_build/use_gradle_build=true','package/unique_name="org.questphoto.viewer"','gradle_build/min_sdk="26"','include_filter="*.json,*.bin,*.txt"']:
   self.assertIn(value,p)
 def test_components_match_sources_and_hashes(self):
  p=ROOT/'android/plugins';info=json.loads((p/'components.json').read_text())
  self.assertEqual(info['app_version'],'0.3.3')
  for name,digest in info['sha256'].items():self.assertEqual(hashlib.sha256((p/name).read_bytes()).hexdigest(),digest,name)
  for name,digest in info['java_source_sha256'].items():self.assertEqual(hashlib.sha256((ROOT/'android_ai/src/main/java/org/questphoto/depth'/name).read_bytes()).hexdigest(),digest,name)
 def test_required_native_contents_and_licenses(self):
  with zipfile.ZipFile(ROOT/'android/plugins/QuestDepth.aar') as aar:
   self.assertIn('AndroidManifest.xml',aar.namelist())
   with zipfile.ZipFile(io.BytesIO(aar.read('classes.jar'))) as jar:
    for cls in ['QuestDepth','DepthFile','SharedImageExport']:self.assertIn('org/questphoto/depth/'+cls+'.class',jar.namelist())
    self.assertIn(b'export_image',jar.read('org/questphoto/depth/QuestDepth.class'))
  with zipfile.ZipFile(ROOT/'android/plugins/onnxruntime-android-1.22.0.aar') as aar:
   for name in ['libonnxruntime.so','libonnxruntime4j_jni.so']:self.assertIn('jni/arm64-v8a/'+name,aar.namelist())
  for name in ['android_ai/licenses/ONNXRuntime-LICENSE','android_ai/licenses/ONNXRuntime-ThirdPartyNotices.txt','models/licenses/Depth-Anything-V2-LICENSE.txt','models/licenses/Depth-Anything-3-LICENSE.txt']:
   self.assertTrue((ROOT/name).is_file(),name)
