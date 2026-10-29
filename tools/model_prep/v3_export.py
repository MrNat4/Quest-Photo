"""Scoped export-only translations for pinned DA3 Small/Base; original methods restored."""
import inspect,textwrap,types
from contextlib import contextmanager
import torch

def patch_method(obj,name,replacements,undo):
 old=getattr(obj,name);source=textwrap.dedent(inspect.getsource(old.__func__))
 for before,after in replacements:
  if source.count(before)!=1:raise ValueError(f'Unexpected upstream {name}; refusing export patch')
  source=source.replace(before,after)
 scope={};exec(compile(source,'<quest-v3-export>','exec'),old.__func__.__globals__,scope)
 setattr(obj,name,types.MethodType(scope[name],obj));undo.append(lambda:setattr(obj,name,old))

def positions(batch_size,height,width,device):
 y,x=torch.meshgrid(torch.arange(height,device=device),torch.arange(width,device=device),indexing='ij')
 return torch.stack((y,x),dim=-1).reshape(1,height*width,2).expand(batch_size,-1,-1).clone()

@contextmanager
def export_context(model):
 undo=[]
 try:
  from v2_dynamic import install as install_position
  from depth_anything_3.model import dualdpt,dpt
  from depth_anything_3.model.utils import head_utils
  def interpolate(x,size=None,scale_factor=None,mode="bilinear",align_corners=True):
   if size is None:
    shape=torch._shape_as_tensor(x).to(torch.float32)
    size=(torch.floor(shape[-2]*scale_factor).to(torch.int64),torch.floor(shape[-1]*scale_factor).to(torch.int64))
   return torch.nn.functional.interpolate(x,size=size,mode=mode,align_corners=align_corners)
  for owner in (dualdpt,dpt,head_utils):
   old_interpolate=owner.custom_interpolate
   owner.custom_interpolate=interpolate
   undo.append(lambda o=owner,v=old_interpolate:setattr(o,'custom_interpolate',v))
  head=model.model.head
  patch_method(head,'_forward_impl',[
   ('int(ph * self.patch_size / self.down_ratio)','ph * self.patch_size // self.down_ratio'),
   ('int(pw * self.patch_size / self.down_ratio)','pw * self.patch_size // self.down_ratio')],undo)
  for module in model.modules():
   if hasattr(module,'interpolate_pos_encoding'):
    original_position=install_position(module)
    undo.append(lambda m=module,v=original_position:setattr(m,'interpolate_pos_encoding',v))
   if hasattr(module,'position_getter') and module.position_getter is not None:
    old=module.position_getter;module.position_getter=positions
    undo.append(lambda m=module,v=old:setattr(m,'position_getter',v))
   if module.__class__.__name__=='RotaryPositionEmbedding2D':
    module.frequency_cache.clear()
    patch_method(module,'forward',[('int(positions.max()) + 1','positions.max() + 1')],undo)
    undo.append(lambda m=module:m.frequency_cache.clear())
  yield
 finally:
  for restore in reversed(undo):restore()
