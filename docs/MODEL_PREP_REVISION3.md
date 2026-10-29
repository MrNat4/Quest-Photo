# Model preparation revision 3 — verified full-model size repair

Extract **QuestPhoto-model-prep-update-3.zip into the same preparation folder**
containing `Prepare-Models.cmd` and `.model-prep`. Replace matching tool files.
Double-click `Prepare-Models.cmd` and select the same V2 checkpoint as before.
The console now identifies revision 3. No software reinstall, pip upgrade, manual
code edit, model re-download, or changes to the working Quest installation.

## Exact cause and change

Revision 2 fixed the positional embedding but missed upstream DPTHead's final
`F.interpolate(..., (int(patch_h * 14), int(patch_w * 14)), ...)`. Those two Python
`int` conversions baked the first image size into the final output. Declaring
dynamic ONNX axes did not undo that constant.

Revision 3 removes those two casts **only during export**. The entire pinned
upstream head function is otherwise used verbatim, with a guard that refuses the
patch if its expected source expression changes. Final bilinear upsampling still
uses `align_corners=True`; the existing positional adapter still preserves its
bicubic settings and offset. No weights, architecture, Android contract, input
preprocessing, quality presets, or output filenames change. Both original
PyTorch methods are restored before numerical validation. Thus validation uses
the original complete upstream network as the reference.

The revision-2 PowerShell warning fix remains: xFormers is optional/disabled on
CPU, warning text is logged, and actual process exit status determines failure.
Tracer warnings inside the positional custom autograd forward are retained in
the log; its ONNX symbolic explicitly supplies dynamic dimensions. They are not
used as a substitute for testing actual exported graphs.

## Verification actually performed before publishing

Cloud CPU environment: PyTorch 2.6.0+cpu, torchvision 0.21.0+cpu, ONNX 1.17.0,
ONNX Runtime 1.22.0, NumPy 1.26.4, Pillow 11.1.0. Python 3.12 on Linux; this is
not Windows or Android execution.

The **complete official V2 Small architecture** (ViT-S backbone, all transformer
blocks, DPT fusion head and final output) was instantiated with deterministic
generated weights. The last output bias was set positive so ReLU would not mask
numerical differences with all-zero outputs. No layers were stubbed or replaced
by a smaller test model. The bundled real photograph supplied input pixels.
These generated weights do NOT establish learned depth quality or validate the
user's official checkpoint.

1. Exported with revision 2 positional correction only. Reproduced exactly:
   input `[1,3,350,518]` → incorrect output `[1,238,364]`.
2. Exported the complete network with revision 3, first at 238×364 and then at
   350×518. Each graph was tested at eight sizes (height×width):
   238×364, 350×518, 518×350, 518×518, 364×364, 364×252, 196×700, 700×196.
3. All **16 full-model inference cases passed**: output `[1,H,W]`, finite values,
   and numerical agreement with unmodified upstream PyTorch. Largest absolute
   difference: 4.76837158203125e-7. This covers growth, shrinkage, portrait,
   landscape, square/native position grid, and wide/tall inputs.
4. Existing helper, launcher, positional ONNX, and Godot tests were run too.
   Exact outputs are in the included `verification` files.

Reproducible full-network test: `tools/model_prep/test_full_v2.py`. You do not need
to run it manually. Your normal launcher still validates the COMPLETE exported
trained model, including the exact failing sizes and both quality presets, before
packaging. The existing near/far and original-file checks remain enabled.

## Still requires validation

The actual trained checkpoint and learned depth quality, V3 model exports,
Windows PowerShell execution, Android compilation and physical Quest inference.
Revision 3 is a preparation-tool update, not a completed AI application release.
If your normal run fails, `.model-prep/last-run.log` and `last-error.txt` retain
full diagnostics. No additional manual fixes are included in these instructions.
