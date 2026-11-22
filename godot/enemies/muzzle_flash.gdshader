shader_type canvas_item;
render_mode blend_add, unshaded;
// Pixel-quantized muzzle flash. Drawn as a quad whose UV.x runs from the muzzle (0) to the flame tip (1).
// Vertex COLOR carries the ammo tint in rgb and the remaining life (1 -> 0) in alpha.
uniform vec2 size = vec2(22.0, 14.0); // quad size in world pixels, for pixel snapping
uniform float seed = 0.0;
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233)) + seed * 3.17) * 43758.5453);
}

void fragment() {
	vec2 cell = floor(UV * size);
	vec2 q = (cell + 0.5) / size;
	float life = clamp(tint.a, 0.0, 1.0);
	float x = q.x;
	float y = (q.y - 0.5) * 2.0;
	// round hot core hugging the muzzle
	float core = 1.0 - length(vec2(x * 2.4, y * 1.05));
	// forward cone, shortening as the flash dies
	float reach = 0.35 + 0.65 * life;
	float width = 0.18 + 0.82 * x / max(reach, 0.01);
	float cone = (1.0 - x / reach) * (1.0 - abs(y) / width);
	// star rays: a few angular spikes that flicker per shot
	float ang = atan(y * 0.6, x + 0.08);
	float rays = pow(0.5 + 0.5 * cos(ang * 9.0 + seed * 6.0), 3.0) * (1.0 - x) * step(abs(y), 0.95);
	float f = max(core * 2.2, max(cone * 1.6, rays * 1.1 * life));
	f += (hash(cell) - 0.5) * 0.25 * step(0.05, f);
	f = clamp(f, 0.0, 1.0) * smoothstep(0.0, 0.25, life);
	// three bands: tint rim, warm body, white-hot centre
	float a = floor(f * 3.999) / 3.0;
	vec3 hot = vec3(1.0, 0.97, 0.86);
	vec3 col = a > 0.9 ? hot : (a > 0.6 ? mix(tint.rgb, hot, 0.55) : tint.rgb);
	COLOR = vec4(col * a * 2.0, a);
}
