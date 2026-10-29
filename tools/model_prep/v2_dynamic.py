"""Export-only DINOv2 positional Resize: preserve original bicubic/offset math.
The official float(w0)/float(h0) trace freezes scales. This symbolic computes
ONNX Resize scales from runtime dimensions. No learned weights are changed.
"""
import math
import types
import torch
from torch.nn import functional as F

class DynamicPosition(torch.autograd.Function):
 @staticmethod
 def forward(ctx, pos, width, height, patch, offset):
  grid=math.isqrt(pos.shape[1]-1)
  w,h=int(width.item()),int(height.item())
  if w//patch==grid and h//patch==grid and w==h:
   return pos
  patches=pos[:,1:].float().reshape(1,grid,grid,pos.shape[-1]).permute(0,3,1,2)
  patches=F.interpolate(patches,scale_factor=((w//patch+offset)/grid,(h//patch+offset)/grid),mode='bicubic',align_corners=False,antialias=False)
  return torch.cat((pos[:,:1].float(),patches.permute(0,2,3,1).flatten(1,2)),dim=1).to(pos.dtype)

 @staticmethod
 def symbolic(g,pos,width,height,patch,offset):
  from torch.onnx import symbolic_helper as sh
  patch=sh._parse_arg(patch,'i'); offset=sh._parse_arg(offset,'f')
  shape=sh._get_tensor_sizes(pos)
  grid=math.isqrt(shape[1]-1); dim=shape[2]
  def const(v,dtype=torch.float32): return g.op('Constant',value_t=torch.tensor(v,dtype=dtype))
  def unsqueeze(v): return g.op('Unsqueeze',v,const([0],torch.int64))
  # Integer patch-grid dimensions remain connected to input Shape nodes.
  w=g.op('Floor',g.op('Div',g.op('Cast',width,to_i=1),const(float(patch))))
  h=g.op('Floor',g.op('Div',g.op('Cast',height,to_i=1),const(float(patch))))
  same=g.op('And',g.op('Equal',w,const(float(grid))),g.op('Equal',h,const(float(grid))))
  extra=g.op('Where',same,const(0.),const(offset))
  scales=g.op('Concat',const([1.,1.]),unsqueeze(g.op('Div',g.op('Add',w,extra),const(float(grid)))),unsqueeze(g.op('Div',g.op('Add',h,extra),const(float(grid)))),axis_i=0)
  cls=g.op('Slice',pos,const([0],torch.int64),const([1],torch.int64),const([1],torch.int64))
  patches=g.op('Slice',pos,const([1],torch.int64),const([grid*grid+1],torch.int64),const([1],torch.int64))
  patches=g.op('Transpose',g.op('Reshape',patches,const([1,grid,grid,dim],torch.int64)),perm_i=[0,3,1,2])
  resized=g.op('Resize',patches,const([]),scales,mode_s='cubic',coordinate_transformation_mode_s='half_pixel',cubic_coeff_a_f=-0.75)
  tokens=g.op('Reshape',g.op('Transpose',resized,perm_i=[0,2,3,1]),const([1,-1,dim],torch.int64))
  return g.op('Concat',cls,tokens,axis_i=1)

def install(backbone):
 if backbone.interpolate_antialias:
  raise ValueError('V2 exporter supports official non-antialiased Small checkpoint only')
 original=backbone.interpolate_pos_encoding
 def dynamic(self,x,w,h):
  # Tracing supplies dimension tensors; preserve them rather than creating constants.
  wt=w if isinstance(w,torch.Tensor) else torch.tensor(w,device=x.device)
  ht=h if isinstance(h,torch.Tensor) else torch.tensor(h,device=x.device)
  return DynamicPosition.apply(self.pos_embed,wt,ht,self.patch_size,self.interpolate_offset).to(x.dtype)
 backbone.interpolate_pos_encoding=types.MethodType(dynamic,backbone)
 return original

def self_test():
 """Small graph, no checkpoint: reproduce frozen-size failure before expensive export."""
 import numpy as np
 import onnxruntime as ort
 import tempfile
 from pathlib import Path
 torch.manual_seed(7)
 class Probe(torch.nn.Module):
  def __init__(self):
   super().__init__(); self.register_buffer('pos',torch.randn(1,1370,4))
  def forward(self,image):
   shape=torch._shape_as_tensor(image)
   return DynamicPosition.apply(self.pos,shape[2],shape[3],14,0.1)
 probe=Probe().eval()
 with tempfile.TemporaryDirectory() as tmp:
  path=Path(tmp)/'dynamic.onnx'
  torch.onnx.export(probe,torch.zeros(1,3,364,252),str(path),opset_version=17,dynamo=False,input_names=['image'],output_names=['position'],dynamic_axes={'image':{2:'h',3:'w'},'position':{1:'tokens'}})
  session=ort.InferenceSession(str(path),providers=['CPUExecutionProvider'])
  results=[]
  for h,w in [(364,252),(518,350),(350,518),(518,518),(364,364),(252,364),(196,700)]:
   x=torch.zeros(1,3,h,w)
   with torch.no_grad(): expected=probe(x).numpy()
   actual=session.run(None,{'image':x.numpy()})[0]
   np.testing.assert_allclose(actual,expected,rtol=2e-4,atol=2e-4)
   assert actual.shape==(1,(h//14)*(w//14)+1,4)
   results.append({'height':h,'width':w,'max_abs_error':float(np.max(np.abs(actual-expected)))})
 return results

def install_depth_head(head):
 """Remove only the two Python int casts that freeze final output H/W.

 Use the pinned upstream implementation verbatim otherwise. Fail closed if its
 source changes, rather than substituting a partial or approximate depth head.
 """
 import inspect
 import textwrap
 original=head.forward
 source=textwrap.dedent(inspect.getsource(type(head).forward))
 old='(int(patch_h * 14), int(patch_w * 14))'
 if source.count(old)!=1:
  raise ValueError('Unexpected V2 DPTHead implementation; refusing an unverified resize patch')
 source=source.replace(old,'(patch_h * 14, patch_w * 14)')
 namespace={}
 exec(compile(source,'<quest-v2-dynamic-depth-head>','exec'), original.__func__.__globals__,namespace)
 head.forward=types.MethodType(namespace['forward'],head)
 return original
