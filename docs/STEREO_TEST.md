# Stereo calibration and headset acceptance

`assets/stereo_test_sbs.png` is a full SBS 2048 × 768 image, left eye first.
The component images are 1024 × 768 each. Both components have the same vertical
coordinates and zero-disparity grid. At default depth/convergence, the green
target has +24 px disparity (left x minus right x), yellow 0 px, and blue −16 px.
The expected ordering is green nearer than the screen, yellow at the screen,
blue behind the screen. This follows rectified parallel stereo geometry; the
fixture does not depend on an AI model.

## What automated tests establish

Run `python3 -m unittest discover -s tests -p 'test_assets.py' -v` from the project
root (requires Pillow). The tests inspect the delivered PNG pixels, verify eye
order and full-SBS dimensions, measure the colored targets' centroids, check
horizontal disparity and vertical alignment, verify zero-disparity background,
and decode the real JPEG photo. They do not verify the headset renderer.

Regenerate fixtures with `python3 tools/generate_calibration.py`. Generation is
deterministic with the same Pillow and DejaVu font versions; font fallback on
other systems can alter text pixels but does not alter disparity geometry.

## Required Quest 3 checks (not performed in the development container)

1. Install and launch the APK using the main build instructions. Select the
   calibration image and stereo mode. Start with default depth/convergence,
   zoom, position, and rotation.
2. Close the right eye: the header must read LEFT EYE. Close the left eye:
   it must read RIGHT EYE. An identical label in both eyes means eye selection
   failed; exchanged labels indicate reversed eye order. Labels deliberately
   differ and are not intended to fuse; inspect depth using the circles.
3. Open both eyes. The grid and yellow circle should sit at the photo plane;
   green should sit closer and blue farther. If ordering is reversed, record
   the renderer backend and whether swapping eyes corrects it.
4. Check that all three targets are vertically aligned and easy to fuse. Move
   the head gently. The photo plane must remain stable in the virtual world.
5. Switch to 2D: both eyes must receive the same image and internal circle depth
   should disappear, while the virtual display itself remains at a 3D position.
6. Check controller transforms and restore defaults. Repeat eye-label checks
   after zoom and pan to detect sampling across the SBS midpoint.
7. Repeat after suspending/resuming the app and with Wi-Fi disabled. Record any
   loss of stereo, controller tracking, image orientation, or readability.

Record APK SHA-256, Quest OS version, renderer, pass/fail per step, and symptoms.
Successful import, shader compilation, or pixel tests alone do not establish
correct stereoscopic rendering or comfortable viewing on a physical Quest.
