"""Full official V3 architectures: generated weights, not pretrained quality."""
import os
os.environ['XFORMERS_DISABLED']='1'
from pathlib import Path
import sys,json,time,gc
import torch,numpy as np,onnx,onnxruntime as ort
from PIL import Image
from prepare import ROOT,CACHE,source,tensor,validate_output
from v3_export import export_context
from v3_checkpoint import build_model,load_checked,ALLOWED_MISSING

def main(kind):
 torch.set_num_threads(2);torch.manual_seed(20261029)
 src=source('v3');model=build_model(kind,src).eval()
 weights=model.state_dict();checkpoint={k:v for k,v in weights.items() if k not in ALLOWED_MISSING}
 report={'model':kind,'weights':'generated, not pretrained','parameter_count':sum(p.numel() for p in model.parameters()),'torch':torch.__version__,'ort':ort.__version__,'cases':[]}
 report['checkpoint']=load_checked(model,checkpoint)
 del weights,checkpoint
 image=Image.open(ROOT/'assets/sample_photo.jpg').convert('RGB')
 path=CACHE/(kind+'-test.onnx')
 with torch.no_grad(),export_context(model):
  torch.onnx.export(model,tensor(image,(364,238)),str(path),opset_version=17,dynamo=False,input_names=['image'],output_names=['depth'],dynamic_axes={'image':{2:'h',3:'w'},'depth':{1:'h',2:'w'}})
 onnx.checker.check_model(str(path))
 opts=ort.SessionOptions();opts.intra_op_num_threads=2;opts.inter_op_num_threads=1
 session=ort.InferenceSession(str(path),sess_options=opts,providers=['CPUExecutionProvider'])
 with torch.no_grad():
  for size in [(364,238),(518,350),(350,518),(518,518),(364,364)]:
   x=tensor(image,size);reference=model(x).numpy();start=time.perf_counter()
   actual=session.run(['depth'],{'image':x.numpy()})[0]
   assert actual.shape==reference.shape==(1,size[1],size[0])
   row=validate_output(reference,actual);row.update(size_wh=size,max_abs_error=float(np.abs(actual-reference).max()),ort_seconds=time.perf_counter()-start)
   report['cases'].append(row);print(row,flush=True)
 (ROOT/'build'/f'{kind}-revision4-report.json').write_text(json.dumps(report,indent=2))
 del session;path.unlink();print('PASS',kind,flush=True)
if __name__=='__main__':main(sys.argv[1])
