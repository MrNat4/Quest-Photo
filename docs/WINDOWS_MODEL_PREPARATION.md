> **Current preparation tool: revision 3.** [Replacement instructions and full-model verification](MODEL_PREP_REVISION3.md). Apply to your existing preparation folder; no reinstall.

> Existing users: apply [revision 2](MODEL_PREP_REVISION2.md) in the same preparation folder. It reuses the installed environment and fixes V2 dynamic positional resizing and PowerShell warning handling.

# Local Windows model preparation — development tool revision 1

This is an **unvalidated real-model exporter**, not a finished 0.3.0 release.
The recovered application regression suite passes after the export-worker fix.
No model inference or Android compilation was possible in the cloud. Your local
run is the next validation step. V3 ONNX operator/dynamic-shape compatibility is
particularly unverified: failures stop packaging and produce an error log.

## Run without changing the working 0.2.0 installation

1. Extract `QuestPhoto-0.3.0-model-prep-1.zip` into a **new folder** on your laptop.
   Leave your existing Godot project and installed Quest application untouched.
2. Install **64-bit Python 3.11** from python.org if missing. Keep the Python
   launcher and Tcl/Tk components enabled. No Git installation is needed.
3. Double-click **Prepare-Models.cmd** in the new folder. It opens PowerShell,
   creates an isolated `.model-prep/venv`, installs pinned CPU Python dependencies,
   and opens file-selection dialogs. Internet is needed on the laptop for Python
   libraries and pinned official architecture source, **never for model weights**.
   No photograph, weight, config or report is uploaded. Expect several GB of disk
   use, substantial RAM, and potentially minutes per test. Use one launcher at a time.
4. First select `depth_anything_v2_vits.pth`. Select your own photograph with an
   obvious near object and distant background. Click **NEAR first, FAR second**.
   Use visible surfaces away from boundaries and sky. The bundled Grace Hopper
   photograph supplies a second real scene automatically.
5. Let the console finish. A successful run explicitly prints **PASS: packaged**.
   Run the launcher again for each V3 `model.safetensors`, choosing its matching
   `config.json`. Config identity determines Small versus Base; filenames do not.
   Keep the two V3 downloads in separate folders. Strict state-dict loading rejects
   a wrongly paired architecture/checkpoint. Unknown configs are rejected.
6. Stop here and report the results before updating/building the headset app.
   Send `.model-prep/last-error.txt` and `last-run.log` on failure; on success send
   `models/validation/<model>/report.json` (and optionally depth previews).
   These logs may contain local paths; the previews depict your chosen photo.
   **Do not send the large weights.** Logs are replaced on the next run, so copy
   each model's failure log before trying another.

If PowerShell is blocked by an organizational policy, do not override that policy;
run through an approved terminal or report the message. The launcher uses process-
only execution-policy Bypass, never changes the machine policy, and accepts no
remote script input. The first dependency installation can take several minutes.

## Validation and installation contract

V2 wraps the official `DepthAnythingV2(vits,64,[48,96,192,384])` network. V3 builds
the official Small/Base YAML architecture, loads the full Hub-prefixed safetensors
strictly, introduces a singleton view axis, and returns only raw depth. Neither
adapter downloads weights nor replaces real inference with a synthetic map.

The exported graph has one float32 **image** input `[1,3,H,W]`, ImageNet RGB
normalization, and **depth** output `[1,H,W]`. Opset 17, single-file float32 weights,
and ONNX Runtime **1.22.0 CPU** match the Android plugin source. Dynamic H/W are
multiples of 14, with longest sides **364 Balanced / 518 High Quality**. Testing
covers both presets, portrait/landscape shapes, two actual scenes, finite and
nonconstant output, and PyTorch-versus-ORT correlation ≥0.995 and normalized RMSE
≤0.02. Those thresholds catch export errors; they do not certify visual quality.

The near/far annotation tests depth direction on the selected scene at both presets:
V2 larger=near; V3 smaller=near (relative distance, not calibrated metres). A failed
annotation check blocks packaging; choose clearer surfaces or report the output.
Near-white depth previews and actual inference timings are retained with the report.
All checkpoint/config files are read-only and their hashes are compared after tests.
Only passing models are copied to:

- `models/v2_small.onnx.bin`
- `models/v3_small.onnx.bin`
- `models/v3_base.onnx.bin`

`models/catalog.json` records model identity, checkpoint/source hashes, ONNX hash,
size, and desktop validation status. Existing different ONNX files are never
silently replaced. Do not publish the downloaded checkpoints or generated graphs
until their exact upstream Apache-2.0 checkpoint provenance has been confirmed;
local filenames and successful tensor loading do not prove license provenance.
Official source license notices are copied into `models/licenses/<model>/`.

This does not build the Android plugin. Its source and build steps remain in
[ANDROID_AI.md](ANDROID_AI.md); its AAR and Android preprocessing still need actual
compilation/device validation. Desktop passing results do not prove headset operation.
No incomplete work is merged to main. This uniquely named tool package is a
0.3.0 development snapshot, not another released APK with a reused version code.
