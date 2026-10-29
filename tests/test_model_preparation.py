"""Contract tests only; these do not run neural inference."""
import importlib.util, tempfile, unittest, json
from pathlib import Path
import numpy as np
spec=importlib.util.spec_from_file_location('prep',Path(__file__).resolve().parents[1]/'tools/model_prep/prepare.py')
prep=importlib.util.module_from_spec(spec); spec.loader.exec_module(prep)
class PreparationTests(unittest.TestCase):
 def test_identity(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'config.json'
   for name,expected in [('da3-small','v3_small'),('da3-base','v3_base')]:
    p.write_text(json.dumps({'model_name':name})); self.assertEqual(prep.identity(p),expected)
   p.write_text('{"model_name":"da3-large"}')
   with self.assertRaises(ValueError): prep.identity(p)
 def test_android_rounding(self):
  self.assertEqual(prep.dimensions(600,400,364),(364,238))
  for side in [364,518]:
   w,h=prep.dimensions(300,800,side); self.assertEqual(h,side); self.assertEqual(w%14,0)
 def test_output_gate(self):
  a=np.arange(400,dtype=np.float32).reshape(1,20,20)
  prep.validate_output(a,a.copy())
  for b in [a[:,:,0],np.zeros_like(a),a[::-1,:,::-1],a*np.nan]:
   with self.assertRaises(ValueError): prep.validate_output(a,b)
 def test_depth_direction(self):
  depth=np.tile(np.arange(1,21,dtype=np.float32),(20,1))
  prep.direction(depth,(.8,.5),(.2,.5),True)
  prep.direction(depth,(.2,.5),(.8,.5),False)
  with self.assertRaises(ValueError): prep.direction(depth,(.2,.5),(.8,.5),True)
 def test_hash_read_only(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'original'; p.write_bytes(b'unchanged'); before=p.read_bytes()
   self.assertEqual(len(prep.sha(p)),64); self.assertEqual(p.read_bytes(),before)
