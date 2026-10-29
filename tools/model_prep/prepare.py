"""Local checkpoint export. Model files never leave this computer."""
from pathlib import Path
import os, sys, json, hashlib, tempfile, urllib.request, zipfile, shutil, time, traceback
ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / '.model-prep'
SOURCES = {
 'v2': ('DepthAnything/Depth-Anything-V2', 'a561b849ebae10a6f5ef49e26c83cbbcd36c71bf'),
 'v3': ('ByteDance-Seed/Depth-Anything-3', '3d835ec1a5802d64a8b8b15f817a1ab54809bfe4')}

def sha(path):
 h = hashlib.sha256()
 with open(path, 'rb') as f:
  for block in iter(lambda: f.read(1024*1024), b''): h.update(block)
 return h.hexdigest()

def identity(config):
 value = json.loads(Path(config).read_text(encoding='utf-8'))
 name = value.get('model_name')
 if name not in ('da3-small', 'da3-base'):
  raise ValueError(f'Expected official da3-small or da3-base config.json; found model_name={name!r}. Do not rename a configuration to force a match.')
 return 'v3_small' if name == 'da3-small' else 'v3_base'

def source(version):
 repo, revision = SOURCES[version]
 target = CACHE / (version + '-' + revision)
 if not target.exists():
  print('Downloading architecture source (NOT weights):', repo, revision, flush=True)
  CACHE.mkdir(exist_ok=True)
  with tempfile.TemporaryDirectory(dir=CACHE) as tmp:
   archive = Path(tmp)/'source.zip'
   urllib.request.urlretrieve(f'https://github.com/{repo}/archive/{revision}.zip', archive)
   with zipfile.ZipFile(archive) as z:
    for name in z.namelist():
     if '..' in Path(name).parts or Path(name).is_absolute(): raise ValueError('Unsafe source archive')
    z.extractall(tmp)
   folder = next(p for p in Path(tmp).iterdir() if p.is_dir())
   shutil.move(str(folder), target)
 sys.path.insert(0, str(target if version == 'v2' else target/'src'))
 return target

def dimensions(w, h, side):
 import math
 return tuple(max(14, math.floor(v*side/max(w,h)/14+0.5)*14) for v in (w,h))

def tensor(image, size):
 import numpy as np, torch
 from PIL import Image
 pixels = np.asarray(image.resize(size, Image.Resampling.BILINEAR), dtype=np.float32)/255
 pixels = (pixels - np.array([.485,.456,.406],np.float32))/np.array([.229,.224,.225],np.float32)
 return torch.from_numpy(pixels.transpose(2,0,1).copy())[None]

def load_model(kind, weights, config):
 import torch
 version = 'v2' if kind == 'v2_small' else 'v3'
 src = source(version)
 if version == 'v2':
  from depth_anything_v2.dpt import DepthAnythingV2
  model = DepthAnythingV2(encoder='vits', features=64, out_channels=[48,96,192,384])
  model.load_state_dict(torch.load(weights, map_location='cpu', weights_only=True), strict=True)
 else:
  from depth_anything_3.cfg import load_config, create_object
  from safetensors.torch import load_file
  if identity(config) != kind: raise ValueError('Checkpoint/config model identity mismatch')
  name = 'da3-small' if kind == 'v3_small' else 'da3-base'
  # Match official Hub wrapper state-dict prefix without importing its optional UI/export stack.
  class Wrapper(torch.nn.Module):
   def __init__(self):
    super().__init__()
    self.model = create_object(load_config(str(src/'src/depth_anything_3/configs'/f'{name}.yaml')))
   def forward(self, image):
    result = self.model(image.unsqueeze(1), export_feat_layers=[], infer_gs=False, ref_view_strategy='first')
    return result['depth'].reshape(image.shape[0], image.shape[2], image.shape[3])
  model = Wrapper()
  model.load_state_dict(load_file(str(weights), device='cpu'), strict=True)
 return model.float().eval(), src

def validate_output(reference, result):
 import numpy as np
 if result.shape != reference.shape or result.ndim != 3 or result.shape[0] != 1:
  raise ValueError(f'Bad depth shape: {result.shape}, expected {reference.shape}')
 if not np.isfinite(result).all() or not np.isfinite(reference).all(): raise ValueError('Nonfinite depth')
 span = float(np.percentile(reference,98)-np.percentile(reference,2))
 if span <= 1e-7: raise ValueError('Flat depth map')
 rmse = float(np.sqrt(np.mean((reference-result)**2))/span)
 corr = float(np.corrcoef(reference.ravel(),result.ravel())[0,1])
 if not np.isfinite(corr) or rmse > .02 or corr < .995:
  raise ValueError(f'ONNX differs from PyTorch: normalized RMSE={rmse}, correlation={corr}')
 return {'normalized_rmse':rmse,'correlation':corr}

def direction(depth, near, far, inverse):
 import numpy as np
 def patch(point):
  x = min(depth.shape[1]-1, int(point[0]*depth.shape[1])); y = min(depth.shape[0]-1,int(point[1]*depth.shape[0]))
  return float(np.median(depth[max(0,y-2):y+3,max(0,x-2):x+3]))
 n,f = patch(near),patch(far)
 if not (n > f if inverse else 0 < n < f):
  raise ValueError(f'Near/far check failed: near={n}, far={f}. Inspect the selected points/model; no output installed.')
 return {'near':n,'far':f,'larger_is_nearer':inverse}

def prepare(kind, weights, config, photo, near, far):
 import numpy as np, torch, onnx, onnxruntime as ort
 from PIL import Image, ImageOps
 torch.set_num_threads(2)
 os.environ['HF_HUB_OFFLINE']='1'; os.environ['XFORMERS_DISABLED']='1'
 weights = Path(weights); original_hash = sha(weights)
 config_hash = sha(config) if config else None
 model, src = load_model(kind, weights, config)
 image = ImageOps.exif_transpose(Image.open(photo)).convert('RGB')
 second = Image.open(ROOT/'assets/sample_photo.jpg').convert('RGB')
 if sha(photo) == sha(ROOT/'assets/sample_photo.jpg'): raise ValueError('Choose your own different photo for the scene comparison.')
 report = {'model':kind,'checkpoint_sha256':original_hash,'config_sha256':config_hash,'source_revision':SOURCES['v2' if kind=='v2_small' else 'v3'][1], 'torch':torch.__version__, 'onnxruntime':ort.__version__, 'tests':[],'device':'Windows/desktop CPU; not Android validation'}
 output = ROOT/'models'; output.mkdir(exist_ok=True)
 with tempfile.TemporaryDirectory(dir=CACHE) as tmp:
  graph = Path(tmp)/'model.onnx'
  example = tensor(image, dimensions(*image.size,364))
  print('Exporting',kind,'(may take minutes)…',flush=True)
  with torch.no_grad():
   torch.onnx.export(model,example,str(graph),input_names=['image'],output_names=['depth'],opset_version=17,
    dynamo=False,do_constant_folding=True,dynamic_axes={'image':{2:'height',3:'width'},'depth':{1:'height',2:'width'}})
  graph_model = onnx.load(str(graph)); onnx.checker.check_model(graph_model)
  if any(t.data_location == onnx.TensorProto.EXTERNAL for t in graph_model.graph.initializer):
   raise ValueError('External tensor data not supported by packaged Android contract')
  del graph_model
  options=ort.SessionOptions(); options.intra_op_num_threads=2; options.inter_op_num_threads=1
  session=ort.InferenceSession(str(graph),sess_options=options,providers=['CPUExecutionProvider'])
  if len(session.get_inputs()) != 1 or session.get_inputs()[0].name != 'image' or session.get_inputs()[0].type != 'tensor(float)':
   raise ValueError('Incorrect ONNX input contract')
  scenes=[]
  # Both presets, both orientations, and a second actual scene. Dynamic tracing must generalize.
  cases=[(image,dimensions(*image.size,s),'user',s) for s in (364,518)]
  cases += [(image,(252,364),'portrait',364),(image,(518,350),'landscape',518),(second,dimensions(*second.size,364),'second',364)]
  with torch.no_grad():
   for picture,size,label,side in cases:
    x=tensor(picture,size); start=time.perf_counter(); reference=model(x).cpu().numpy()
    if reference.shape != (1,size[1],size[0]): raise ValueError(f'Unexpected native output {reference.shape}')
    native_seconds=time.perf_counter()-start; start=time.perf_counter()
    result=session.run(['depth'],{'image':x.numpy()})[0]; elapsed=time.perf_counter()-start
    row=validate_output(reference,result); row.update(scene=label,shape=list(result.shape),preset_side=side,torch_seconds=native_seconds,onnx_seconds=elapsed)
    if label=='user': row['depth_direction']=direction(result[0],near,far,kind=='v2_small')
    report['tests'].append(row); print(row,flush=True)
    if label in ('user','second') and side==364:
     normalized=(result[0]-result.min())/max(float(result.max()-result.min()),1e-12)
     if kind!='v2_small': normalized=1-normalized
     preview=Image.fromarray((normalized*255).astype('uint8'))
     preview.save(Path(tmp)/(label+'-near-white.png'))
     scenes.append(np.asarray(preview.resize((64,64)),np.float32))
  if np.mean(np.abs(scenes[0]-scenes[1])) < 1: raise ValueError('Different scenes produced indistinguishable depth')
  if sha(weights)!=original_hash or (config and sha(config)!=config_hash): raise ValueError('Source checkpoint changed during preparation')
  report['onnx_sha256']=sha(graph); report['bytes']=graph.stat().st_size
  reports=output/'validation'/kind; reports.mkdir(parents=True,exist_ok=True)
  (reports/'report.json').write_text(json.dumps(report,indent=2))
  for p in Path(tmp).glob('*-near-white.png'): shutil.copy2(p,reports/p.name)
  target=output/(kind+'.onnx.bin')
  if target.exists():
   if sha(target)!=report['onnx_sha256']: raise ValueError(f'{target} already exists with different bytes. Move it aside explicitly to replace it.')
  else: shutil.copy2(graph,target)
  catalog_path=output/'catalog.json'; catalog=json.loads(catalog_path.read_text())
  catalog[kind].update(installed=True,revision=original_hash,onnx_sha256=report['onnx_sha256'],validation='Desktop real-photo ONNX/PyTorch and annotated near/far passed',bytes=report['bytes'],source_revision=report['source_revision'])
  temp=catalog_path.with_suffix('.tmp'); temp.write_text(json.dumps(catalog,indent=2)); temp.replace(catalog_path)
  notices=output/'licenses'/kind; notices.mkdir(parents=True,exist_ok=True)
  for p in src.glob('*LICENSE*'): shutil.copy2(p,notices/p.name)
 print('PASS: packaged',target,'Android/Quest testing is still required.',flush=True)

def guided():
 import tkinter as tk
 from tkinter import filedialog, messagebox
 from PIL import Image, ImageOps, ImageTk
 root=tk.Tk(); root.withdraw()
 def pick(title,pattern):
  value=filedialog.askopenfilename(title=title,filetypes=[('Required file',pattern)],initialdir=str(Path.home()/'Downloads'))
  if not value: raise RuntimeError('Cancelled; existing outputs preserved')
  return value
 messagebox.showinfo('Quest Photo model preparation','Choose V2 .pth first, or one V3 model.safetensors. For V3 you will then choose its matching config.json. Run once per model. Files stay on this laptop.')
 weights=pick('Select V2 .pth or V3 model.safetensors','*.pth *.safetensors')
 config=None
 if Path(weights).suffix.lower()=='.pth': kind='v2_small'
 else: config=pick('Select matching V3 config.json','*.json'); kind=identity(config)
 messagebox.showinfo('Model identity',f'Preparing {kind}. Strict weight loading will reject a mismatched checkpoint. Select a photo with clear foreground and background; then click a nearby surface followed by a distant surface.')
 photo=pick('Choose a real photo with obvious near and far surfaces','*.jpg *.jpeg *.png')
 picture=ImageOps.exif_transpose(Image.open(photo)).convert('RGB'); picture.thumbnail((1000,700))
 window=tk.Toplevel(root); window.title('Click NEAR object, then FAR background (avoid borders/sky)')
 im=ImageTk.PhotoImage(picture); canvas=tk.Canvas(window,width=picture.width,height=picture.height); canvas.pack(); canvas.create_image(0,0,anchor='nw',image=im)
 points=[]
 def clicked(event):
  points.append((event.x/picture.width,event.y/picture.height))
  canvas.create_oval(event.x-4,event.y-4,event.x+4,event.y+4,fill='red')
  if len(points)==2: window.destroy()
 canvas.bind('<Button-1>',clicked); root.wait_window(window)
 if len(points)!=2: raise RuntimeError('Near/far annotation cancelled')
 root.destroy()
 prepare(kind,weights,config,photo,*points)

if __name__=='__main__':
 CACHE.mkdir(exist_ok=True)
 try: guided()
 except Exception:
  text=traceback.format_exc(); (CACHE/'last-error.txt').write_text(text); print(text,file=sys.stderr)
  print('FAILED. No claim of a usable model. Send .model-prep/last-error.txt and console log, not your weights.',file=sys.stderr); sys.exit(1)
