"""Package tracked source plus recovered compiled native dependencies; no local secrets."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,zipfile
from apk_builder.core import NATIVE_FILES,digest,verify_components
ROOT=Path(__file__).resolve().parents[1]

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--id',required=True);args=parser.parse_args()
 if not args.id.isdigit():raise SystemExit('Package ID must be a unique positive build number')
 commit=os.environ.get('GITHUB_SHA') or subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
 plugins=ROOT/'android/plugins'
 components={'godot':'4.6.3','onnxruntime':'1.22.0','source_commit':commit,'package_id':args.id,
  'sha256':{name:digest(plugins/name) for name in NATIVE_FILES}}
 (plugins/'components.json').write_text(json.dumps(components,indent=2)+'\n')
 verify_components(ROOT)
 tracked=subprocess.check_output(['git','ls-files','-z'],cwd=ROOT).decode().split('\0')
 files={Path(p) for p in tracked if p and not p.startswith(('recovery/','verification/revision')) and not p.endswith(('.zip','.bundle','.apk','.aab','.keystore','.jks'))}
 files.update(Path('android/plugins')/name for name in (*NATIVE_FILES,'components.json'))
 for path in (ROOT/'android_ai/build/test-results/testReleaseUnitTest').glob('TEST-*.xml'):
  target=ROOT/'verification/android-integration'/path.name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(path.read_bytes());files.add(target.relative_to(ROOT))
 # Keep all tests in source, but never include a test graph as an installed model.
 if any(str(p).startswith('models/') and str(p).endswith('.onnx.bin') for p in files):raise ValueError('Refusing packaged model binaries; user supplies validated models')
 output=ROOT/'build/distribution';output.mkdir(parents=True,exist_ok=True)
 archive=output/f'ZDim-0.3.0-Android-Dev{args.id}.zip'
 if archive.exists():raise FileExistsError('Unique artifact name already exists; use a new package ID')
 with zipfile.ZipFile(archive,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
  for relative in sorted(files):z.write(ROOT/relative,str(relative))
 checksum=archive.with_suffix('.zip.sha256');checksum.write_text(digest(archive)+'  '+archive.name+'\n')
 print(archive);print(checksum.read_text().strip())

if __name__=='__main__':main()
