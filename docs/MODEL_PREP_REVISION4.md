# Model preparation revision 4 — controlled V3 checkpoint compatibility

Extract **QuestPhoto-model-prep-update-4.zip into your existing preparation
folder**, replacing matching tool files. Double-click **Prepare-Models.cmd**.
Select V3 Small's `model.safetensors` and its matching `config.json`, then repeat
for V3 Base. There are no pip commands, reinstalls, dependency changes, or manual
code edits. Do not rerun V2: the patch does not include or change your prepared
`models/v2_small.onnx.bin`, source checkpoints, catalog, or Python environment.

## Narrow checkpoint exception

[Official issue #2](https://github.com/ByteDance-Seed/Depth-Anything-3/issues/2)
reports the missing auxiliary names. The upstream collaborator says the omission
does not affect results and recommends non-strict loading. The later discussion
identifies shared LayerNorm objects in the auxiliary head.

This tool permits only these **six exact missing names**:

```
model.head.scratch.output_conv2_aux.1.2.weight
model.head.scratch.output_conv2_aux.1.2.bias
model.head.scratch.output_conv2_aux.2.2.weight
model.head.scratch.output_conv2_aux.2.2.bias
model.head.scratch.output_conv2_aux.3.2.weight
model.head.scratch.output_conv2_aux.3.2.bias
```

They are aliases of `.0.2.weight` and `.0.2.bias`, which must already exist in the
checkpoint. The loader verifies that the architecture actually shares those
Parameter objects, supplies each absent alias from its existing canonical tensor,
and then runs **strict loading**. It does not accept arbitrary missing auxiliary
keys, initialize missing learned weights randomly, or use blanket `strict=False`.
Unexpected keys, essential omissions, absent canonical tensors, wrong shapes,
conflicting supplied aliases and nonshared architectures are rejected. The
checkpoint dictionary is not modified. Missing-alias details are recorded in
the console and validation report.

## Additional failures found and fixed before delivery

Full-network testing uncovered V3's unsupported `cartesian_prod` during export,
then fixed positional/fusion dimensions that caused incorrect results at larger
sizes. The export-only adapter translates coordinate generation to equivalent
meshgrid operations, retains dynamic rotary frequency bounds, uses the previously
tested positional Resize translation, and keeps final and fusion upsampling
sizes dynamic. It preserves the source model and restores every patched method
and function before comparing against original PyTorch inference. No model source
files or dependencies in your environment are edited. Export is batch-one,
single-view RGB depth, as required by the existing Android contract.

## Tests actually completed

Both **complete official DA3 Small and Base architectures**, at pinned source
`3d835ec1a5802d64a8b8b15f817a1ab54809bfe4`, were initialized with deterministic
**generated weights**. The six aliases were removed to reproduce your checkpoint
condition, then loaded with the controlled exception. Each full model was exported
at 238×364 and tested through ONNX Runtime at all five H×W sizes:

- 238×364 (Balanced landscape)
- 350×518 (High Quality landscape)
- 518×350 (High Quality portrait)
- 518×518 (square/native positional grid)
- 364×364 (Balanced square)

All **10 full-model ONNX inference cases passed**, with correct output shapes,
finite/nonconstant depth and agreement against unmodified PyTorch. Maximum
absolute differences: Small **2.980232238769531e-7**, Base
**2.384185791015625e-7**. Correlations exceeded 0.99999999998.

Seven focused checkpoint-loader tests cover allowed aliases and rejection cases.
The existing Python, V2 positional ONNX and Godot regression suites also pass.
See `verification/` for exact logs, versions and per-size measurements; the full
architecture regression is reproducible via `tools/model_prep/test_full_v3.py`.

Tests ran on Linux CPU, PyTorch 2.6.0+cpu and ONNX Runtime 1.22.0, using the same
pinned library versions already specified by the preparation tool. This does not
constitute Windows, Android, physical Quest, or **real pretrained-checkpoint**
validation. Generated weights establish export/load compatibility, not learned
depth quality. The normal launcher still requires real-checkpoint numerical and
near/far tests to pass before packaging your model. It never marks an untested
checkpoint as validated merely because these architecture tests passed.

V2 conversion/export behavior is unchanged. Your working application and GitHub
main are untouched. This is tool revision 4, not a new APK release.
