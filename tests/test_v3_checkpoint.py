"""Exact auxiliary alias exception; synthetic module, not inference validation."""
import importlib.util,sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools/model_prep'))
from v3_checkpoint import ALLOWED_MISSING,PREFIX,load_checked
HAS_TORCH=importlib.util.find_spec('torch') is not None
@unittest.skipUnless(HAS_TORCH,'requires PyTorch')
class V3CheckpointTests(unittest.TestCase):
 def fixture(self,shared=True):
  import torch
  nn=torch.nn
  root=nn.Module();root.model=nn.Module();root.model.head=nn.Module();root.model.head.scratch=nn.Module()
  norm=nn.LayerNorm(4)
  root.model.head.scratch.output_conv2_aux=nn.ModuleList([nn.Sequential(nn.Linear(4,4),nn.Identity(),norm if shared else nn.LayerNorm(4)) for _ in range(4)])
  weights={k:v.clone() for k,v in root.state_dict().items() if k not in ALLOWED_MISSING}
  return root,weights
 def test_exact_six_and_strict_full(self):
  import torch
  root,weights=self.fixture();self.assertEqual(len(ALLOWED_MISSING),6)
  weights[PREFIX+'0.2.weight'].fill_(2.5)
  before={k:v.clone() for k,v in weights.items()}
  result=load_checked(root,weights);self.assertEqual(set(result['allowed_missing_aliases']),ALLOWED_MISSING)
  for index in range(4):self.assertTrue(torch.equal(root.get_parameter(PREFIX+str(index)+'.2.weight'),weights[PREFIX+'0.2.weight']))
  for k in before:self.assertTrue(torch.equal(before[k],weights[k]))
  self.assertEqual(load_checked(root,root.state_dict())['allowed_missing_aliases'],[])
 def test_essential_missing(self):
  root,w=self.fixture();del w[PREFIX+'0.0.weight']
  with self.assertRaisesRegex(ValueError,'essential'):load_checked(root,w)
 def test_extra(self):
  root,w=self.fixture();w['unknown']=next(iter(w.values()))
  with self.assertRaisesRegex(ValueError,'unexpected'):load_checked(root,w)
 def test_canonical_missing(self):
  root,w=self.fixture();del w[PREFIX+'0.2.bias']
  with self.assertRaises(ValueError):load_checked(root,w)
 def test_wrong_shape(self):
  root,w=self.fixture();w[PREFIX+'0.0.weight']=w[PREFIX+'0.0.weight'][:1]
  with self.assertRaisesRegex(ValueError,'shapes'):load_checked(root,w)
 def test_conflicting_alias(self):
  root,w=self.fixture();w[PREFIX+'1.2.weight']=w[PREFIX+'0.2.weight']+1
  with self.assertRaisesRegex(ValueError,'Conflicting'):load_checked(root,w)
 def test_not_shared(self):
  root,w=self.fixture(shared=False)
  with self.assertRaisesRegex(ValueError,'not the documented'):load_checked(root,w)
