shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

uniform sampler2D photograph : source_color, filter_linear, repeat_disable;
uniform bool is_sbs = false;
uniform bool stereo_enabled = true;
uniform bool swap_eyes = false;
// Desktop inspection only; XR uses VIEW_INDEX (0 left, 1 right).
uniform int preview_eye = 0;
uniform bool xr_active = false;
uniform float zoom = 1.0;
uniform vec2 pan = vec2(0.0);
uniform float convergence = 0.0;

void fragment() {
    int eye = xr_active ? int(VIEW_INDEX) : preview_eye;
    if (swap_eyes) { eye = 1 - eye; }
    if (!stereo_enabled || !is_sbs) { eye = 0; }
    vec2 uv = (UV - vec2(0.5)) / zoom + vec2(0.5) + pan;
    if (is_sbs && stereo_enabled) {
        uv.x += (eye == 0 ? -1.0 : 1.0) * convergence;
    }
    bool outside = any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)));
    // Clamp to pixel centres before packing to avoid opposite-eye seam bleed.
    vec2 dimensions = vec2(textureSize(photograph, 0));
    if (is_sbs) { dimensions.x *= 0.5; }
    uv = clamp(uv, vec2(0.5) / dimensions, vec2(1.0) - vec2(0.5) / dimensions);
    if (is_sbs) { uv.x = (uv.x + float(eye)) * 0.5; }
    ALBEDO = outside ? vec3(0.0) : texture(photograph, uv).rgb;
}
