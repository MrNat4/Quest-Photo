"""Guided, isolated APK build using the user's existing Godot/SDK/JDK/Gradle."""
from pathlib import Path
import json,os,re,shutil,subprocess,sys,time,traceback,uuid
from apk_builder.core import verify_models,verify_components,stage_project,verify_apk,portable_editor,preset_debug_key,option,sections,android_presets
PACKAGE=Path(__file__).resolve().parents[1]

def run(args,log,env=None):
 print('Running:',Path(args[0]).name,' '.join(args[1:3]),flush=True)
 p=subprocess.Popen([str(a) for a in args],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace',env=env)
 failed_script=False
 with open(log,'w',encoding='utf-8') as f:
  for line in p.stdout:
   print(line,end='',flush=True);f.write(line);f.flush()
   failed_script |= 'SCRIPT ERROR:' in line or 'Parse Error' in line
 code=p.wait()
 if code or failed_script:raise RuntimeError(f'{Path(args[0]).name} failed (exit {code}). See {log}')

def main():
 import tkinter as tk
 from tkinter import filedialog,messagebox
 if os.name!='nt':raise RuntimeError('Use Build-ZDim.cmd on your Windows laptop; cloud tests use the same core functions independently.')
 root=tk.Tk();root.withdraw()
 prefs_path=PACKAGE/'.apk-builder-paths.json'
 prefs=json.loads(prefs_path.read_text()) if prefs_path.exists() else {}
 def folder(key,title,valid):
  candidate=Path(prefs.get(key,''))
  if not valid(candidate):
   choice=filedialog.askdirectory(title=title,mustexist=True)
   if not choice:raise RuntimeError('Build cancelled. Originals unchanged.')
   candidate=Path(choice)
  if not valid(candidate):raise ValueError('Selected folder is not valid: '+title)
  prefs[key]=str(candidate.resolve());return candidate.resolve()
 working=folder('working','Select the WORKING Godot project (contains project.godot and your Android setup)',lambda p:(p/'project.godot').is_file() and (p/'export_presets.cfg').is_file())
 models=folder('models','Select the completed MODELS folder (or its parent project)',lambda p:(p/'catalog.json').is_file() or (p/'models/catalog.json').is_file())
 print('Checking packaged native components…',flush=True);components=verify_components(PACKAGE)
 models,model_info=verify_models(models)
 godot=Path(prefs.get('godot',shutil.which('godot') or ''))
 if not godot.is_file():
  choice=filedialog.askopenfilename(title='Select your Godot 4.6.3 executable (console version preferred)',filetypes=[('Godot executable','*.exe')])
  if not choice:raise RuntimeError('Build cancelled.')
  godot=Path(choice)
 console=godot.with_name(godot.stem+'_console.exe')
 if console.is_file():godot=console
 version=subprocess.check_output([str(godot),'--headless','--version'],text=True,encoding='utf-8',errors='replace').strip()
 if not version.startswith('4.6.3.stable'):raise ValueError('Expected Godot 4.6.3; found '+version)
 prefs['godot']=str(godot.resolve())
 settings=[]
 for location in (Path(os.environ.get('APPDATA',''))/'Godot',godot.parent/'editor_data',godot.parent/'editor_data/config'):
  settings.extend(location.glob('editor_settings-4.6*.tres'))
 configured='\n'.join(p.read_text(encoding='utf-8-sig') for p in settings)
 sdk_candidates=[option(configured,'export/android/android_sdk_path'),os.environ.get('ANDROID_HOME',''),os.environ.get('ANDROID_SDK_ROOT',''),str(Path(os.environ.get('LOCALAPPDATA',''))/'Android/Sdk')]
 jdk_candidates=[option(configured,'export/android/java_sdk_path'),os.environ.get('JAVA_HOME','')]
 def locate(key,title,candidates,valid):
  for p in [prefs.get(key,'')]+candidates:
   if p and valid(Path(p)):prefs[key]=p;return Path(p).resolve()
  return folder(key,title,valid)
 sdk=locate('sdk','Select your existing Android SDK folder',sdk_candidates,lambda p:(p/'build-tools').is_dir())
 jdk=locate('jdk','Select your existing JDK folder',jdk_candidates,lambda p:(p/'bin/java.exe').is_file() and (p/'bin/javac.exe').is_file())
 build_tools=sorted((p for p in (sdk/'build-tools').iterdir() if (p/'aapt.exe').is_file() and (p/'lib/apksigner.jar').is_file()),key=lambda p:tuple(int(n) for n in re.findall(r'\d+',p.name)))
 if not build_tools:raise ValueError('Existing SDK has no usable build-tools/apksigner')
 prefs_path.write_text(json.dumps(prefs,indent=2))
 base=Path(os.environ.get('LOCALAPPDATA',str(Path.home())))/'ZDimBuilds';base.mkdir(parents=True,exist_ok=True)
 # Windows locks release automatically after crashes; no stale lock cleanup needed.
 import msvcrt
 lock=open(base/'builder.lock','a+b');lock.seek(0);lock.write(b'0');lock.flush();lock.seek(0)
 try:msvcrt.locking(lock.fileno(),msvcrt.LK_NBLCK,1)
 except OSError:raise RuntimeError('Another Z-Dim build is running; wait for it to finish.')
 counter=base/'build-counter.json';counters=json.loads(counter.read_text()) if counter.exists() else {}
 preset_text=(working/'export_presets.cfg').read_text(encoding='utf-8-sig')
 old_codes=[int(option(b,'version/code','0')) for h,b in sections(preset_text) if h.endswith('.options]')]
 code=max([2]+old_codes+[int(counters.get('last',0))])+1
 counters['last']=code;counter.write_text(json.dumps(counters))
 build=base/(f'0.3.0-dev.{code}-'+uuid.uuid4().hex[:8]);build.mkdir()
 stage=build/'project'
 print('Preparing isolated build copy:',build,flush=True)
 expected=stage_project(PACKAGE,working,models,stage,code)
 # The copied template uses the already installed SDK/JDK, never the original folder as output.
 (stage/'android/build/local.properties').write_text('sdk.dir='+str(sdk).replace('\\','/')+'\n',encoding='utf-8')
 env=dict(os.environ);env['JAVA_HOME']=str(jdk);env['ANDROID_HOME']=str(sdk);env['ANDROID_SDK_ROOT']=str(sdk)
 env['PATH']=str(jdk/'bin')+os.pathsep+env.get('PATH','')
 template_folders=[Path(os.environ.get('APPDATA',''))/'Godot/export_templates/4.6.3.stable',godot.parent/'editor_data/export_templates/4.6.3.stable']
 keys=[Path(os.environ.get('APPDATA',''))/'Godot/debug.keystore',godot.parent/'editor_data/debug.keystore',Path.home()/'.android/debug.keystore']
 godot=portable_editor(godot,build,sdk,jdk,settings,template_folders,keys,preset_debug_key(stage,expected['preset']))
 apk=build/(f'ZDim-0.3.0-dev.{code}.apk')
 run([str(godot),'--headless','--xr-mode','off','--path',str(stage),'--editor','--import','--quit'],build/'import.log',env)
 run([str(godot),'--headless','--xr-mode','off','--path',str(stage),'--export-debug',expected['preset'],str(apk)],build/'export.log',env)
 report=verify_apk(apk,model_info,expected,build_tools[-1],jdk/'bin/java.exe')
 # Confirm originals still match their recorded hashes after the whole build.
 verify_models(models)
 report['source_build']=components.get('source_commit');report['original_project']=str(working)
 (build/'verification.json').write_text(json.dumps(report,indent=2))
 (build/'APK.sha256').write_text(report['sha256']+'  '+apk.name+'\n')
 print('\nSUCCESS — APK compiled, signed, and verified:',apk,flush=True)
 print('No APK was installed. Your existing project and model originals are unchanged.',flush=True)
 messagebox.showinfo('Z-Dim build verified',f'APK ready:\n{apk}\n\nModel hashes, ARM64 libraries, plugin metadata, signature and version verified.\nHeadset testing is still required.')
 os.startfile(build)
 root.destroy();lock.close()

if __name__=='__main__':
 try:main()
 except Exception:
  text=traceback.format_exc();print(text,file=sys.stderr)
  (PACKAGE/'last-apk-build-error.txt').write_text(text,encoding='utf-8')
  print('BUILD FAILED. No success claim; see last-apk-build-error.txt and the build logs.',file=sys.stderr)
  sys.exit(1)
