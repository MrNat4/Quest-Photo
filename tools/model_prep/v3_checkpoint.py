"""DA3 issue #2 exception: six shared LayerNorm aliases, never arbitrary keys."""
PREFIX='model.head.scratch.output_conv2_aux.'
ALLOWED_MISSING=frozenset(f'{PREFIX}{index}.2.{field}' for index in (1,2,3) for field in ('weight','bias'))

def load_checked(model,weights):
 import torch
 expected=model.state_dict()
 missing=set(expected)-set(weights);unexpected=set(weights)-set(expected)
 if missing-ALLOWED_MISSING or unexpected:
  raise ValueError(f'Incompatible V3 checkpoint: essential/unknown missing={sorted(missing-ALLOWED_MISSING)}, unexpected={sorted(unexpected)}')
 repaired=dict(weights)
 for alias in sorted(ALLOWED_MISSING):
  field=alias.rsplit('.',1)[1];canonical=PREFIX+'0.2.'+field
  if alias not in expected or canonical not in weights:
   raise ValueError('Unexpected auxiliary normalization architecture or missing canonical parameter: '+canonical)
  if model.get_parameter(alias) is not model.get_parameter(canonical):
   raise ValueError('Refusing missing auxiliary parameter that is not the documented shared alias: '+alias)
  if alias in weights and not torch.equal(weights[alias],weights[canonical]):
   raise ValueError('Conflicting shared normalization weights: '+alias)
  if alias in missing:
   repaired[alias]=weights[canonical]
 bad_shapes=[k for k,v in repaired.items() if tuple(v.shape)!=tuple(expected[k].shape)]
 if bad_shapes:raise ValueError('Incompatible V3 checkpoint tensor shapes: '+str(bad_shapes))
 # Strict loading still rejects any shape mismatch, essential omission or extra key.
 model.load_state_dict(repaired,strict=True)
 return {'allowed_missing_aliases':sorted(missing),'unexpected_keys':[], 'strategy':'shared canonical tensors restored, then strict=True', 'upstream_issue':'https://github.com/ByteDance-Seed/Depth-Anything-3/issues/2'}

def build_model(kind,src):
 import torch
 from depth_anything_3.cfg import load_config,create_object
 if kind not in ('v3_small','v3_base'):raise ValueError('Unsupported V3 architecture')
 name='da3-small' if kind=='v3_small' else 'da3-base'
 class Wrapper(torch.nn.Module):
  def __init__(self):
   super().__init__()
   self.model=create_object(load_config(str(src/'src/depth_anything_3/configs'/f'{name}.yaml')))
  def forward(self,image):
   result=self.model(image.unsqueeze(1),export_feat_layers=[],infer_gs=False,ref_view_strategy='first')
   return result['depth'].reshape(image.shape[0],image.shape[2],image.shape[3])
 return Wrapper()
