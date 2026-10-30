"""Builder input protection and package checks, without touching Windows settings."""
import hashlib,json,sys,tempfile,unittest,zipfile
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from apk_builder.core import *
ROOT=Path(__file__).resolve().parents[1]

class BuilderTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name)
  self.models=self.root/'models';self.models.mkdir()
  self.catalog={}
  for name in MODEL_IDS:
   path=self.models/(name+'.onnx.bin');path.write_bytes(b'fixture-only-'+name.encode())
   self.catalog[name]={'installed':True,'onnx_sha256':digest(path),'bytes':path.stat().st_size}
  self.save_catalog()
 def tearDown(self):self.tmp.cleanup()
 def save_catalog(self):(self.models/'catalog.json').write_text(json.dumps(self.catalog))
 def working(self):
  p=self.root/'working';p.mkdir();(p/'android/build').mkdir(parents=True)
  (p/'android/build/build.gradle').write_text('// existing local template')
  (p/'project.godot').write_text('[application]\nconfig/name="My Working Quest App"\nconfig/version="0.2.0"\n[rendering]\ncustom=true\n')
  (p/'export_presets.cfg').write_text((ROOT/'export_presets.cfg').read_text()+'\nkeystore/debug="res://private.keystore"\nkeystore/debug_password="private-password"\n')
  (p/'private.keystore').write_bytes(b'original-signing-key')
  (p/'.godot').mkdir();(p/'.godot/export_credentials.cfg').write_text('my-credentials')
  return p
 def test_validated_models_and_corruption(self):
  _,rows=verify_models(self.models,lambda _:None);self.assertEqual(len(rows),3)
  (self.models/'v3_base.onnx.bin').write_bytes(b'corruption')
  with self.assertRaisesRegex(ValueError,'SHA-256'):verify_models(self.models,lambda _:None)
 def test_unvalidated_catalog_rejected(self):
  self.catalog['v3_small']['installed']=False;self.save_catalog()
  with self.assertRaisesRegex(ValueError,'validated checksum'):verify_models(self.models,lambda _:None)
 def test_stage_preserves_original_project_models_and_credentials(self):
  working=self.working();before={str(p.relative_to(working)):digest(p) for p in working.rglob('*') if p.is_file()}
  model_hashes={p.name:digest(p) for p in self.models.iterdir()}
  stage=self.root/'staged';expected=stage_project(ROOT,working,self.models,stage,71)
  self.assertEqual(expected,{'preset':'Quest 3','package':'org.questphoto.viewer','version':'0.3.0-dev.71','code':71})
  self.assertEqual(before,{str(p.relative_to(working)):digest(p) for p in working.rglob('*') if p.is_file()})
  self.assertEqual(model_hashes,{p.name:digest(p) for p in self.models.iterdir()})
  self.assertEqual((stage/'.godot/export_credentials.cfg').read_text(),'my-credentials')
  self.assertEqual((stage/'private.keystore').read_bytes(),b'original-signing-key')
  self.assertIn('keystore/debug_password="private-password"',(stage/'export_presets.cfg').read_text())
  self.assertIn('config/name="My Working Quest App"',(stage/'project.godot').read_text())
  self.assertIn('plugins/QuestDepth=true',(stage/'export_presets.cfg').read_text())
  self.assertIn('version/name="0.3.0-dev.71"',(stage/'export_presets.cfg').read_text())
  with self.assertRaises(ValueError):stage_project(ROOT,working,self.models,working/'child',72)
  with self.assertRaises(ValueError):stage_project(ROOT,working,self.models,stage,72)
 def test_custom_gradle_base_and_signing_guard(self):
  working=self.working();external=self.root/'custom-android';(external/'build').mkdir(parents=True)
  (external/'build/build.gradle').write_text('// custom template')
  (external/'.build_version').write_text('4.6.3.stable')
  preset=working/'export_presets.cfg';preset.write_text(preset.read_text()+'\ngradle_build/gradle_build_directory='+json.dumps(str(external))+'\n')
  stage=self.root/'staged';stage_project(ROOT,working,self.models,stage,72)
  self.assertEqual((stage/'android/build/build.gradle').read_text(),'// custom template')
  self.assertEqual((stage/'android/.build_version').read_text(),'4.6.3.stable')
  self.assertIn('gradle_build/gradle_build_directory="res://android"',(stage/'export_presets.cfg').read_text())
  self.assertTrue(preset_debug_key(stage,'Quest 3'))
  (stage/'private.keystore').unlink()
  with self.assertRaisesRegex(ValueError,'keystore cannot'):preset_debug_key(stage,'Quest 3')
 def test_apk_missing_models_fails_before_external_commands(self):
  apk=self.root/'bad.apk'
  with zipfile.ZipFile(apk,'w') as z:z.writestr('dummy',b'not-a-production-apk')
  _,models=verify_models(self.models,lambda _:None)
  with self.assertRaisesRegex(ValueError,'APK missing model'):verify_apk(apk,models,{},self.root,self.root/'java')
 def test_apk_detects_corrupted_model_before_claiming_success(self):
  apk=self.root/'bad.apk'
  with zipfile.ZipFile(apk,'w') as z:
   for name in MODEL_IDS:z.writestr('assets/models/'+name+'.onnx.bin',b'corrupt')
  _,models=verify_models(self.models,lambda _:None)
  with self.assertRaisesRegex(ValueError,'checksum mismatch'):verify_apk(apk,models,{},self.root,self.root/'java')
 def test_portable_editor_preserves_existing_profile(self):
  exe=self.root/'godot.exe';exe.write_bytes(b'editor')
  settings=self.root/'settings.tres';settings.write_text('[resource]\nexport/android/debug_keystore="C:/existing/debug.keystore"\nexport/android/debug_keystore_user="existing-alias"\n')
  original=settings.read_bytes();templates=self.root/'templates';templates.mkdir();(templates/'android_debug.apk').write_bytes(b'template')
  build=self.root/'build';build.mkdir()
  result=portable_editor(exe,build,self.root/'sdk',self.root/'jdk',[settings],[templates],[],preset_has_key=True)
  self.assertTrue(result.is_file());self.assertEqual(original,settings.read_bytes())
  copied=(build/'editor/editor_data/editor_settings-4.6.tres').read_text()
  self.assertIn('existing-alias',copied);self.assertIn('C:/existing/debug.keystore',copied)
  self.assertTrue((build/'editor/._sc_').exists())

if __name__=='__main__':unittest.main()
