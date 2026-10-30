"""Read-only source/model inputs; all writes are to an isolated build directory."""
from pathlib import Path
import hashlib,json,os,re,shutil,struct,subprocess,sys,zipfile
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from update_project import sections,join_sections,set_option,update_project_metadata,update_export_metadata
MODEL_IDS=('v2_small','v3_small','v3_base')
NATIVE_FILES=('QuestDepth.gdap','QuestDepth.aar','onnxruntime-android-1.22.0.aar')

def digest(path):
 h=hashlib.sha256()
 with open(path,'rb') as f:
  for chunk in iter(lambda:f.read(1024*1024),b''):h.update(chunk)
 return h.hexdigest()

def verify_models(folder,notify=print):
 folder=Path(folder).resolve()
 if not (folder/'catalog.json').is_file() and (folder/'models/catalog.json').is_file():folder=folder/'models'
 catalog=json.loads((folder/'catalog.json').read_text(encoding='utf-8-sig'))
 result={}
 for name in MODEL_IDS:
  row=catalog.get(name,{})
  expected=row.get('onnx_sha256','')
  if row.get('installed') is not True or not re.fullmatch('[0-9a-f]{64}',str(expected)):
   raise ValueError(f'{name}: missing validated checksum/installed marker in catalog.json. Select your completed models folder.')
  path=folder/(name+'.onnx.bin')
  notify('Checking validated model: '+name)
  if not path.is_file() or path.stat().st_size<8 or digest(path)!=expected:
   raise ValueError(f'{name}: model file missing or SHA-256 mismatch. Original files were not changed.')
  if row.get('bytes') is not None and int(row['bytes'])!=path.stat().st_size:raise ValueError(name+': recorded file size mismatch')
  report=folder/'validation'/name/'report.json'
  if report.is_file():
   r=json.loads(report.read_text())
   if r.get('model')!=name or r.get('onnx_sha256')!=expected:raise ValueError(name+': validation report/catalog mismatch')
  result[name]={'sha256':expected,'bytes':path.stat().st_size}
 return folder,result

def verify_components(package):
 info=json.loads((package/'android/plugins/components.json').read_text())
 if info.get('godot')!='4.6.3' or info.get('onnxruntime')!='1.22.0':raise ValueError('Native component version mismatch')
 for name in NATIVE_FILES:
  if digest(package/'android/plugins'/name)!=info['sha256'][name]:raise ValueError('Damaged native component: '+name)
 return info

def option(text,key,default=''):
 match=re.search(r'^'+re.escape(key)+r'\s*=\s*(.*?)\s*$',text,re.M)
 if not match:return default
 value=match.group(1)
 if value.startswith('"'):
  return json.loads(value)
 return value

def android_presets(text):
 return [(h,b) for h,b in sections(text) if re.fullmatch(r'\[preset\.\d+\]',h) and option(b,'platform')=='Android']

def stage_project(package,working,models,destination,code):
 package,working,models,destination=map(lambda p:Path(p).resolve(),(package,working,models,destination))
 if destination==working or working in destination.parents or destination in working.parents:raise ValueError('Build staging must be outside your working project')
 if destination.exists():raise ValueError('Refusing to replace existing build folder')
 def ignore(directory,names):
  skipped={'.git','.godot','.gradle','.model-prep','__pycache__','builds','.build','.venv','venv'}
  if Path(directory).name!='android':skipped.add('build')
  if Path(directory)==working:skipped.add('models')
  return [n for n in names if n in skipped or n.startswith('.quest-photo-backup-') or n.lower().endswith(('.apk','.aab'))]
 shutil.copytree(working,destination,ignore=ignore,symlinks=False)
 # Godot's credential file belongs only to this local build copy; never distribute it.
 credential=working/'.godot/export_credentials.cfg'
 if credential.is_file():
  (destination/'.godot').mkdir(exist_ok=True);shutil.copy2(credential,destination/'.godot/export_credentials.cfg')
 for directory in ('scripts','scenes','shaders','assets'):
  shutil.copytree(package/directory,destination/directory,dirs_exist_ok=True)
 shutil.copy2(package/'openxr_action_map.tres',destination/'openxr_action_map.tres')
 shutil.copytree(package/'android/plugins',destination/'android/plugins',dirs_exist_ok=True)
 # Copy only installed model inputs and notices, not model-preparation environment.
 (destination/'models').mkdir(exist_ok=True)
 for name in MODEL_IDS:shutil.copy2(models/(name+'.onnx.bin'),destination/'models'/(name+'.onnx.bin'))
 shutil.copy2(models/'catalog.json',destination/'models/catalog.json')
 if (models/'licenses').is_dir():shutil.copytree(models/'licenses',destination/'models/licenses')
 for relative in ('LICENSE','THIRD_PARTY_NOTICES.md','android_ai/licenses'):
  p=package/relative
  if p.is_dir():shutil.copytree(p,destination/'third_party'/Path(relative).name,dirs_exist_ok=True)
  elif p.is_file():shutil.copy2(p,destination/p.name)
 version=f'0.3.0-dev.{code}'
 project=destination/'project.godot'
 values=sections(project.read_text(encoding='utf-8-sig'))
 for i,(header,body) in enumerate(values):
  if header=='[application]':values[i]=(header,set_option(body,'config/version',json.dumps(version)))
  if header=='[rendering]':values[i]=(header,set_option(body,'textures/vram_compression/import_etc2_astc','true'))
 project.write_text(join_sections(values),encoding='utf-8')
 preset_path=destination/'export_presets.cfg'
 text=preset_path.read_text(encoding='utf-8-sig')
 presets=android_presets(text)
 if not presets:raise ValueError('No Android export preset found in the selected working project')
 # Prefer the runnable preset; otherwise the first existing Android preset.
 header,body=next(((h,b) for h,b in presets if option(b,'runnable')=='true'),presets[0])
 index=re.search(r'\d+',header).group();name=option(body,'name')
 values=sections(text);package_id=''
 for i,(h,b) in enumerate(values):
  if h==header:
   b=set_option(b,'export_filter','"all_resources"')
   existing=[v.strip() for v in option(b,'include_filter').split(',') if v.strip()]
   for v in ('*.bin','*.json','*.txt','third_party/*'):
    if v not in existing:existing.append(v)
   b=set_option(b,'include_filter',json.dumps(','.join(existing)))
   exclusions=[v.strip() for v in option(b,'exclude_filter').split(',') if v.strip()]
   for v in ('tools/*','tests/*','docs/*','build/*','builds/*','verification/*','recovery/*','*.zip','*.bundle','.model-prep/*','android_ai/*'):
    if v not in exclusions:exclusions.append(v)
   b=set_option(b,'exclude_filter',json.dumps(','.join(exclusions)))
   values[i]=(h,b)
  if h==f'[preset.{index}.options]':
   package_id=option(b,'package/unique_name')
   if not package_id or '$' in package_id:raise ValueError('Use an explicit Android package ID in the working preset; cannot verify an unresolved placeholder')
   custom=option(b,'gradle_build/gradle_build_directory')
   if custom:
    custom_path=working/custom[6:] if custom.startswith('res://') else Path(custom)
    if not custom_path.is_absolute():custom_path=working/custom_path
    custom_path=custom_path/'build'  # Godot adds /build to this preset's base directory.
    if custom_path.resolve()!=(working/'android/build').resolve():
     if (destination/'android/build').exists():shutil.rmtree(destination/'android/build')
     shutil.copytree(custom_path,destination/'android/build',ignore=ignore)
     if (custom_path.parent/'.build_version').is_file():shutil.copy2(custom_path.parent/'.build_version',destination/'android/.build_version')
   updates={'gradle_build/use_gradle_build':'true','gradle_build/gradle_build_directory':'"res://android"','gradle_build/export_format':'0','gradle_build/min_sdk':json.dumps(str(max(26,int(option(b,'gradle_build/min_sdk','0') or '0')))),'plugins/QuestDepth':'true','architectures/arm64-v8a':'true','architectures/armeabi-v7a':'false','architectures/x86':'false','architectures/x86_64':'false','version/code':str(code),'version/name':json.dumps(version)}
   for k,v in updates.items():b=set_option(b,k,v)
   values[i]=(h,b)
 preset_path.write_text(join_sections(values),encoding='utf-8')
 if not (destination/'android/build/build.gradle').is_file():raise ValueError('Selected project has no installed working Android Gradle template. Select the project that built your working APK.')
 return {'preset':name,'package':package_id,'version':version,'code':code}

def verify_apk(apk,models,expected,build_tools,java):
 apk=Path(apk)
 if not apk.is_file():raise ValueError('Godot did not produce the APK')
 with zipfile.ZipFile(apk) as z:
  names=z.namelist()
  for model,row in models.items():
   path='assets/models/'+model+'.onnx.bin'
   if names.count(path)!=1:raise ValueError('APK missing model or unexpected packing: '+path)
   h=hashlib.sha256()
   with z.open(path) as f:
    for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
   if h.hexdigest()!=row['sha256']:raise ValueError('APK model checksum mismatch: '+model)
  for lib in ('libonnxruntime.so','libonnxruntime4j_jni.so','libgodot_android.so'):
   path='lib/arm64-v8a/'+lib
   if path not in names:raise ValueError('Missing ARM64 library: '+path)
   with z.open(path) as f:header=f.read(20)
   if header[:4]!=b'\x7fELF' or header[4]!=2 or struct.unpack_from('<H',header,18)[0]!=183:raise ValueError('Not an ARM64 ELF: '+lib)
  if any(n.startswith('lib/') and not n.startswith('lib/arm64-v8a/') and n.endswith('.so') for n in names):raise ValueError('Unexpected non-ARM64 library in APK')
  if not any(b'Lorg/questphoto/depth/QuestDepth;' in z.read(n) for n in names if re.fullmatch(r'classes\d*\.dex',n)):raise ValueError('QuestDepth Java plugin missing from DEX')
  if b'QuestDepth' not in z.read('AndroidManifest.xml') and 'QuestDepth'.encode('utf-16le') not in z.read('AndroidManifest.xml'):raise ValueError('QuestDepth plugin metadata missing')
  if 'assets/models/catalog.json' not in names:raise ValueError('Model catalog missing from APK')
  catalog=json.loads(z.read('assets/models/catalog.json'))
  for name,row in models.items():
   if catalog.get(name,{}).get('onnx_sha256')!=row['sha256']:raise ValueError('Packaged catalog checksum mismatch')
 suffix='.exe' if os.name=='nt' else ''
 badging=subprocess.check_output([str(Path(build_tools)/('aapt'+suffix)),'dump','badging',str(apk)],text=True,encoding='utf-8',errors='replace')
 for k,v in [('name',expected['package']),('versionCode',str(expected['code'])),('versionName',expected['version'])]:
  if f"{k}='{v}'" not in badging.splitlines()[0]:raise ValueError('APK manifest identity/version mismatch: '+k)
 subprocess.run([str(java),'-jar',str(Path(build_tools)/'lib/apksigner.jar'),'verify','--verbose',str(apk)],check=True)
 return {'apk':str(apk),'sha256':digest(apk),'models':models,'identity':expected,'arm64':True,'signature_verified':True}

def preset_debug_key(project,preset_name):
 """Read existing signing configuration; do not generate a replacement key."""
 project=Path(project)
 values=sections((project/'export_presets.cfg').read_text(encoding='utf-8-sig'))
 index=next(re.search(r'\d+',h).group() for h,b in values if re.fullmatch(r'\[preset\.\d+\]',h) and option(b,'name')==preset_name)
 credential=project/'.godot/export_credentials.cfg'
 private=sections(credential.read_text(encoding='utf-8-sig')) if credential.is_file() else []
 body=next((b for h,b in private if h==f'[preset.{index}]'),'')
 public=next((b for h,b in values if h==f'[preset.{index}.options]'),'')
 key=os.environ.get('GODOT_ANDROID_KEYSTORE_DEBUG_PATH') or option(body,'keystore/debug') or option(public,'keystore/debug')
 if not key:return False
 path=project/key[6:] if key.startswith('res://') else Path(key)
 if not path.is_absolute():path=project/path
 if not path.is_file():raise ValueError('Existing preset debug keystore cannot be found: '+str(path))
 return True

def portable_editor(godot,build,sdk,jdk,settings_files,template_folders,debug_key_candidates,preset_has_key=False):
 """Clone the editor into self-contained mode; never write the user's editor profile."""
 godot,build,sdk,jdk=map(Path,(godot,build,sdk,jdk))
 bin_dir=build/'editor';bin_dir.mkdir()
 shutil.copy2(godot,bin_dir/godot.name)
 if godot.stem.endswith('_console'):
  main=godot.with_name(godot.stem[:-8]+'.exe')
  if main.is_file():shutil.copy2(main,bin_dir/main.name)
 for dll in godot.parent.glob('*.dll'):shutil.copy2(dll,bin_dir/dll.name)
 (bin_dir/'._sc_').write_text('')
 data=bin_dir/'editor_data';data.mkdir()
 config=next((Path(p) for p in settings_files if Path(p).is_file()),None)
 contents=config.read_text(encoding='utf-8-sig') if config else '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
 for key,value in [('export/android/android_sdk_path',str(sdk).replace('\\','/')),('export/android/java_sdk_path',str(jdk).replace('\\','/'))]:
  contents=set_option(contents,key,json.dumps(value))
 configured_key=option(contents,'export/android/debug_keystore')
 if not configured_key:
  found=next((Path(p) for p in debug_key_candidates if Path(p).is_file()),None)
  if found:contents=set_option(contents,'export/android/debug_keystore',json.dumps(str(found).replace('\\','/')))
 configured_key=option(contents,'export/android/debug_keystore')
 if not preset_has_key and (not configured_key or not Path(configured_key).is_file()):
  raise ValueError('Cannot locate your existing debug signing key. Refusing to generate a different key; select the editor/project that produced your working APK.')
 # Keep aliases/passwords from existing settings. No keystore is generated by this helper.
 (data/'editor_settings-4.6.tres').write_text(contents,encoding='utf-8')
 template=next((Path(p) for p in template_folders if (Path(p)/'android_debug.apk').is_file()),None)
 if template is None:raise ValueError('Cannot find the existing Godot 4.6.3 Android export templates')
 target=data/'export_templates/4.6.3.stable';target.mkdir(parents=True)
 for name in ('android_debug.apk','android_release.apk','android_source.zip','version.txt'):
  if (template/name).is_file():shutil.copy2(template/name,target/name)
 return bin_dir/godot.name
