shader_type canvas_item;
// Arena floor. The albedo is baked per theme (arena_level.gd); this adds:
//  - a normal map derived from the albedo, so the PointLight2D pool rakes across asphalt grain, grout, planks
//  - specular (wet puddles, polished marble, waxed wood, glossy spy floor)
//  - per-theme life: rain ripples in puddles, cloud shadows outdoors, harbour water, data pulses in Spy HQ
//  - soft prop shadows (light from the upper left) and contact occlusion along walls and props
uniform int theme_id = 0;   // 0 street, 1 marble, 2 gravel, 3 tile, 4 parquet, 5 planks, 6 grid
uniform vec2 world_size = vec2(1600.0, 1100.0);
uniform vec4 prop_rects[8];
uniform float prop_h[8];
uniform int prop_count = 0;
uniform vec4 lamp_col : source_color = vec4(1.0);
varying vec4 v_spec;   // rgb specular colour, a shininess (fragment -> light)

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p = p * 2.03 + 11.7; a *= 0.5; }
	return v;
}
float lum(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }
float sd_box(vec2 p, vec2 a, vec2 b) {
	vec2 c = (a + b) * 0.5; vec2 e = (b - a) * 0.5; vec2 d = abs(p - c) - e;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

void fragment() {
	vec2 w = UV * world_size;
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec4 base = texture(TEXTURE, UV);
	vec3 col = base.rgb;
	// height from albedo luminance -> OpenGL-style normal (green up)
	float hl = lum(texture(TEXTURE, UV - vec2(px.x, 0.0)).rgb);
	float hr = lum(texture(TEXTURE, UV + vec2(px.x, 0.0)).rgb);
	float hu = lum(texture(TEXTURE, UV - vec2(0.0, px.y)).rgb);
	float hd = lum(texture(TEXTURE, UV + vec2(0.0, px.y)).rgb);
	float bump = theme_id == 6 ? 1.0 : 3.0;
	vec2 g = vec2(hl - hr, hd - hu) * bump;
	float grain = (theme_id == 0 || theme_id == 2) ? 0.22 : 0.08;
	g += (vec2(noise(w * 0.8), noise(w * 0.8 + 17.0)) - 0.5) * grain;
	vec3 spec = vec3(0.0); float shine = 0.3;
	float edge = min(min(w.x, world_size.x - w.x), min(w.y, world_size.y - w.y));
	bool inside = edge > 16.0;
	bool outdoor = theme_id == 0 || theme_id == 2 || theme_id == 5;

	if (theme_id == 0 && inside) {
		// wet asphalt: puddles that mirror the lamps, with rain ripples
		float wet = smoothstep(0.56, 0.64, fbm(w * 0.0055 + vec2(3.1, 7.7)));
		float damp = smoothstep(0.45, 0.6, fbm(w * 0.0055 + vec2(3.1, 7.7)));
		col = mix(col, col * 0.9, damp);
		col = mix(col, col * 0.7 + vec3(0.02, 0.03, 0.05), wet);
		vec2 cell = floor(w / 22.0); vec2 f = fract(w / 22.0) - 0.5;
		float tt = fract(TIME * 0.8 + hash(cell) * 7.0);
		vec2 off = (vec2(hash(cell + 3.1), hash(cell + 5.3)) - 0.5) * 0.5;
		float r = length(f - off);
		float ring = exp(-abs(r - tt * 0.55) * 28.0) * (1.0 - tt) * step(0.35, hash(cell + 9.9));
		g += normalize(f - off + 0.0001) * ring * 1.4 * wet;
		col += vec3(0.5, 0.6, 0.7) * ring * 0.12 * wet;
		spec = vec3(0.9, 0.95, 1.0) * (0.08 * damp + 0.8 * wet); shine = mix(0.35, 1.0, wet);
	} else if (theme_id == 1) {
		float vein = abs(sin(w.x * 0.012 + w.y * 0.007 + fbm(w * 0.008) * 7.0));
		col *= 1.0 - 0.1 * smoothstep(0.97, 1.0, 1.0 - vein);
		float sweep = smoothstep(0.0, 0.04, 0.04 - abs(fract((w.x + w.y) / 1400.0 - TIME * 0.05) - 0.5));
		col += vec3(1.0, 0.95, 0.85) * sweep * 0.06;
		spec = vec3(1.0, 0.95, 0.85) * 0.3; shine = 0.8;
	} else if (theme_id == 3) {
		spec = vec3(0.22); shine = 0.6;
	} else if (theme_id == 4) {
		spec = vec3(1.0, 0.85, 0.6) * 0.3; shine = 0.55;
	} else if (theme_id == 5 && w.y > world_size.y - 72.0 && w.y < world_size.y - 16.0) {
		// harbour water: rolling swell with glints
		float t = TIME;
		float wv = sin(w.x * 0.045 + t * 1.6 + sin(w.y * 0.2 + t) * 1.5) + 0.6 * sin(w.x * 0.11 - t * 2.3 + w.y * 0.3);
		float n = fbm(vec2(w.x * 0.02 - t * 0.4, w.y * 0.08 + t * 0.2));
		col = mix(vec3(0.05, 0.2, 0.32), vec3(0.14, 0.42, 0.56), 0.5 + 0.25 * wv + 0.3 * (n - 0.5));
		col += vec3(0.8, 0.95, 1.0) * smoothstep(0.78, 0.86, n + 0.12 * wv) * 0.35;
		float foam = smoothstep(6.0, 0.0, w.y - (world_size.y - 70.0) - 2.0 * sin(w.x * 0.07 + t * 2.0));
		col = mix(col, vec3(0.85, 0.92, 0.95), foam * 0.6);
		g = vec2(cos(w.x * 0.045 + t * 1.6), sin(w.y * 0.2 + t)) * 0.6;
		spec = vec3(1.0); shine = 1.0;
	} else if (theme_id == 6) {
		vec3 trace = vec3(0.122, 0.541, 0.627);
		vec3 cyan = vec3(0.25, 0.9, 1.0);
		if (distance(base.rgb, trace) < 0.1) {
			float lane = hash(vec2(floor(w.y / 64.0), floor(w.x / 640.0)));
			float p = fract(w.x / 420.0 - TIME * (0.35 + lane * 0.5) + lane * 5.0);
			col += cyan * (smoothstep(0.86, 1.0, p) * 2.2 + 0.25);
		}
		vec3 gridc = vec3(0.086, 0.188, 0.227);
		if (distance(base.rgb, gridc) < 0.05) {
			float ring = fract(length(w - world_size * 0.5) / 520.0 - TIME * 0.22);
			col += cyan * (smoothstep(0.93, 1.0, ring) * 0.9 + 0.08);
		}
		spec = vec3(0.4, 0.9, 1.0) * 0.6; shine = 0.9;
	}
	if (outdoor && inside) {   // drifting cloud shadows
		float cl = fbm(w * 0.0016 + TIME * vec2(0.012, 0.006));
		col *= 1.0 - 0.14 * smoothstep(0.5, 0.72, cl);
	}
	// soft prop shadows (sun/lamps from the upper left) + contact occlusion
	float sh = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i >= prop_count) break;
		vec4 r = prop_rects[i]; float hh = prop_h[i];
		float s = sd_box(w, r.xy + vec2(hh * 0.25, 2.0), r.zw + vec2(hh * 0.5, hh * 0.18));
		sh = max(sh, (1.0 - smoothstep(-6.0, 12.0, s)) * 0.5);
		float c = sd_box(w, r.xy, r.zw);
		sh = max(sh, (1.0 - smoothstep(0.0, 22.0, c)) * 0.35);
	}
	if (inside) {
		col *= mix(0.5, 1.0, smoothstep(16.0, 80.0, edge));
		col *= 1.0 - sh;
	}
	COLOR = vec4(col, base.a);
	NORMAL_MAP = normalize(vec3(g, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
	v_spec = vec4(spec, shine);
}

void light() {
	float nl = max(0.0, dot(NORMAL, LIGHT_DIRECTION));
	vec3 hv = normalize(LIGHT_DIRECTION + vec3(0.0, 0.0, 1.0));
	float s = pow(max(0.0, dot(NORMAL, hv)), exp2(v_spec.a * 7.0 + 1.0)) * (v_spec.a * 1.5 + 0.4);
	vec3 lc = LIGHT_COLOR.rgb * LIGHT_ENERGY;
	LIGHT = vec4(COLOR.rgb * lc * nl + v_spec.rgb * lc * s, LIGHT_COLOR.a);
}
