# Desktop evidence, 0.3.2

checks.txt: complete isolated headless regression run (Godot 4.6.3 / Linux).
report.json: old/new 0.3.1/0.3.2 reconstruction with identical procedural depths.
memory.json: separate monitored maintenance run; whole-process RSS, not VR usage.
comparison.png: face/hair crops, 0.3.1 top / 0.3.2 bottom, left/right columns.
The existing NASA public-domain astronaut fixture uses PROCEDURAL depth; this is
not AI inference or headset validation. Photo attribution is preserved in
`tests/fixtures/quality/ATTRIBUTION.md` in the baseline project.

Run `python tools/run_checks.py` for tests only. It isolates user storage; do not
run cache deletion tests directly against a normal app profile. No APK is built.
The older quality_reconstruction regression retains historical 0.3.1 labels;
use report.json here for the actual 0.3.1-versus-0.3.2 comparison.
