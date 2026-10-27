# Known issues and limitations

- No APK yet: SDK, full JDK and export templates unavailable; network proxy
  unreachable from shell. The preset has been recognized by Godot, not deployed.
- No physical Quest, OpenXR runtime or usable graphics display in this workspace.
  The headless renderer is a dummy. Shader compilation, output eye isolation,
  controller hardware and lifecycle behavior are not proven by these tests.
- Ordinary photos remain 2D. No AI depth, depth editor, segmentation, generative
  reconstruction, GIF or video processing exists in this version.
- Local loading is synchronous; a large decode can interrupt frames. File/dimension
  caps bound input sizes but worst-case peak memory has not been profiled on Quest.
- Local browsing is sequential. Quest import currently requires debug ADB transfer;
  no Storage Access Framework picker, thumbnails or controller ray UI yet.
- Full SBS left-first is recognized by `.sbs` filename suffix. Half SBS and EXIF
  orientation/color profiles are not interpreted. Sources must be oriented first.
- Transparent PNGs are displayed on the opaque image plane; alpha compositing
  is not supported. Grayscale/depth files are not auto-interpreted as depth.
- Convergence can reveal black borders. Automatic disparity comfort calibration
  and depth-strength control await the depth pipeline.
- Screen placement resets on launch. Per-photo view preferences are saved but
  this is not a full editing-project format. Same-path replacement reuses settings.
- Build script/preflight was exercised only without a complete Android toolchain;
  successful build/signature verification remains untested.
