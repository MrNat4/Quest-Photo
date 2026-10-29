"""Launcher process semantics and export adapter structure; no checkpoint claims."""
import importlib.util, subprocess, sys, tempfile, unittest, ast
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def module(name):
 spec=importlib.util.spec_from_file_location(name,ROOT/'tools/model_prep'/f'{name}.py')
 value=importlib.util.module_from_spec(spec); spec.loader.exec_module(value); return value
class LauncherTests(unittest.TestCase):
 def test_stderr_warning_is_not_failure(self):
  with tempfile.TemporaryDirectory() as d:
   path=Path(d)/'log'
   code=module('run_logged').run([sys.executable,'-c',"import sys; print('xFormers not available',file=sys.stderr); print('continued')"],path)
   self.assertEqual(code,0); self.assertIn('continued',path.read_text()); self.assertIn('xFormers',path.read_text())
 def test_real_failure_exit_and_trace_preserved(self):
  with tempfile.TemporaryDirectory() as d:
   path=Path(d)/'log'
   code=module('run_logged').run([sys.executable,'-c',"raise RuntimeError('model failure')"],path)
   self.assertNotEqual(code,0); self.assertIn('RuntimeError: model failure',path.read_text())
 def test_launcher_keeps_existing_environment(self):
  s=(ROOT/'tools/model_prep/Prepare-Models.ps1').read_text()
  self.assertNotIn('-m pip',s); self.assertIn('run_logged.py',s); self.assertIn('$LASTEXITCODE',s)
 def test_adapter_restores_reference_before_testing(self):
  s=(ROOT/'tools/model_prep/prepare.py').read_text()
  self.assertLess(s.index('model.pretrained.interpolate_pos_encoding=original_position'),s.index("session.run(['depth']"))
 def test_adapter_export_graph_has_runtime_scales(self):
  # Structural guard against reintroducing float(w)/float(h) constant tracing.
  s=(ROOT/'tools/model_prep/v2_dynamic.py').read_text(); ast.parse(s)
  symbolic=s[s.index(' def symbolic'):s.index('\ndef install')]
  self.assertIn("g.op('Cast',width",symbolic); self.assertIn("g.op('Cast',height",symbolic)
  self.assertIn("g.op('Resize',patches,const([]),scales",symbolic)
  self.assertIn("same",symbolic); self.assertIn('cubic_coeff_a_f=-0.75',symbolic)
 @unittest.skipUnless(all(importlib.util.find_spec(m) for m in ['torch','onnx','onnxruntime']), 'PyTorch/ONNX unavailable in this executor')
 def test_actual_dynamic_onnx_at_seven_sizes(self):
  self.assertEqual(len(module('v2_dynamic').self_test()),7)
