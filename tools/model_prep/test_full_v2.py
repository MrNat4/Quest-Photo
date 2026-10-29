"""Complete official V2 Small, generated weights; NOT learned-depth validation.
Run with the preparation environment: python tools/model_prep/test_full_v2.py
"""
import os
os.environ['XFORMERS_DISABLED']='1'
from pathlib import Path
import json,time,sys
import torch, numpy as np, onnx, onnxruntime as ort
from PIL import Image
from prepare import source, tensor, ROOT, CACHE
from v2_dynamic import install, install_depth_head

def main():
 torch.set_num_threads(2); torch.manual_seed(20261029)
 CACHE.mkdir(exist_ok=True)
 source('v2')
 from depth_anything_v2.dpt import DepthAnythingV2
 model=DepthAnythingV2(encoder='vits',features=64,out_channels=[48,96,192,384]).eval()
 # Keep random untrained outputs positive so final ReLU does not hide differences.
 with torch.no_grad(): model.depth_head.scratch.output_conv2[2].bias.fill_(1)
 image=Image.open(ROOT/'assets/sample_photo.jpg').convert('RGB')
 report={'weights':'deterministically generated; not official learned checkpoint','torch':torch.__version__,'ort':ort.__version__,'cases':[]}
 options=ort.SessionOptions();options.intra_op_num_threads=2;options.inter_op_num_threads=1
 def export(path,size,fix_head):
  old=install(model.pretrained);head=install_depth_head(model.depth_head) if fix_head else None
  try:
   with torch.no_grad():
    torch.onnx.export(model,tensor(image,size),str(path),opset_version=17,dynamo=False,input_names=['image'],output_names=['depth'],dynamic_axes={'image':{2:'h',3:'w'},'depth':{1:'h',2:'w'}})
  finally:
   model.pretrained.interpolate_pos_encoding=old
   if head is not None:model.depth_head.forward=head
  onnx.checker.check_model(str(path))
 # Reproduce revision 2 with the COMPLETE network, not the position-only probe.
 oldpath=CACHE/'full-v2-revision2.onnx'; export(oldpath,(364,238),False)
 session=ort.InferenceSession(str(oldpath),sess_options=options,providers=['CPUExecutionProvider'])
 oldshape=list(session.run(['depth'],{'image':tensor(image,(518,350)).numpy()})[0].shape)
 report['revision2_output_for_350x518']=oldshape
 assert oldshape==[1,238,364],oldshape
 del session
 oldpath.unlink()
 for export_size in [(364,238),(518,350)]:
  path=CACHE/'full-v2-revision3.onnx';export(path,export_size,True)
  session=ort.InferenceSession(str(path),sess_options=options,providers=['CPUExecutionProvider'])
  for size in [(364,238),(518,350),(350,518),(518,518),(364,364),(252,364),(700,196),(196,700)]:
   x=tensor(image,size)
   with torch.no_grad():reference=model(x).numpy()
   begin=time.perf_counter();actual=session.run(['depth'],{'image':x.numpy()})[0];seconds=time.perf_counter()-begin
   assert actual.shape==reference.shape==(1,size[1],size[0]),(size,actual.shape)
   assert np.isfinite(actual).all()
   np.testing.assert_allclose(actual,reference,rtol=2e-4,atol=2e-4)
   row={'export_size_wh':export_size,'input_size_wh':size,'output_shape':list(actual.shape),'max_abs_error':float(np.abs(actual-reference).max()),'ort_seconds':seconds}
   report['cases'].append(row);print(row,flush=True)
  del session;path.unlink()
 report_path=ROOT/'build/full-v2-revision3-report.json';report_path.parent.mkdir(exist_ok=True)
 report_path.write_text(json.dumps(report,indent=2));print('PASS: full V2 generated-weight model, 16 multi-size cases; revision 2 reproduced',flush=True)
if __name__=='__main__':main()
