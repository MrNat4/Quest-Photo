# Model preparation revision 2 — replacement tool only

Extract **QuestPhoto-model-prep-update-2.zip directly into your EXISTING model
preparation folder**, the folder containing `Prepare-Models.cmd` and `.model-prep`.
Choose Replace for matching tool files. Then double-click `Prepare-Models.cmd` as
before. Do not delete `.model-prep`, move your model downloads, reinstall Python,
or update the working Quest 0.2.0 project. This update contains no model files,
application settings, or environment. It does not run pip or upgrade packages.

The V2 failure is caused by the pinned official DINOv2 positional-embedding function
converting runtime dimensions to Python floats while tracing. The resulting ONNX
Resize scales are frozen at export size; the positional tokens cannot broadcast
against a larger image's tokens. Dynamic input labels alone cannot repair that.

Revision 2 installs an **export-only** positional interpolation adapter. Its ONNX
Resize scales depend on runtime image height/width. It retains official bicubic
half-pixel interpolation, cubic coefficient -0.75, offset 0.1, and the native
518-square positional-grid shortcut. No weights, model architecture, Android
input format, output filenames, or presets change. After export it restores the
original upstream PyTorch method: numerical validation compares ONNX against the
unmodified reference, not the adapter. V3 paths are unchanged.

Before loading V2 weights, the tool automatically runs a small ONNX positional
Resize regression at seven shapes: 364×252, 518×350, 350×518, 518×518, 364×364,
252×364 and 196×700. It compares actual ONNX Runtime results against PyTorch.
This takes much less work than another full export and stops early on a bad
adapter. Full real-photo inference at both presets and additional shapes remains
mandatory before packaging. Reports include `tool_revision: 2` and Resize results.

The CPU route intentionally does not use xFormers. Its “not available/disabled”
warnings are expected. Windows PowerShell 5.1 with ErrorActionPreference=Stop can
mistake Python's stderr warning for a terminating error. A Python subprocess wrapper
now combines stderr/stdout before PowerShell receives them, preserves all messages
in `.model-prep/last-run.log`, and propagates the actual process exit code. Real
inference errors still fail. No warning-based inference success is possible.

Verification here: Python syntax, launcher subprocess warning/failure tests and
existing preparation/helper/Godot regression suites. Actual PyTorch/ONNX regression
is automatically executed on your laptop; this cloud executor lacks those libraries
and checkpoints. PowerShell itself is also unavailable here. **The corrected full
V2 export still requires your local checkpoint run; V3 and Android remain unverified.**
If it fails, `last-run.log` and `last-error.txt` contain the details. No further
manual edits are part of this update. The package is a numbered preparation-tool
revision, not a new APK or a claim that 0.3.0 is release-ready.
