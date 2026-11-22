shader_type canvas_item;
render_mode unshaded, blend_add;

uniform vec4 beam_color : source_color = vec4(1.0,0.18,0.18,1.0);
uniform float beam_length = 300.0;
uniform float beam_radius = 5.0;
uniform float padding = 22.0;
uniform float opacity = 1.0;
uniform float clock = 0.0;
uniform float chain = 0.0;
uniform float burning = 0.0;
uniform float frost = 0.0;
uniform float toxic = 0.0;
uniform float mind = 0.0;

float hash(float n) { return fract(sin(n*127.1)*43758.5453); }

void fragment() {
	vec2 dimensions = vec2(beam_length+(beam_radius+padding)*2.0,(beam_radius+padding)*2.0);
	vec2 p = UV*dimensions-vec2(beam_radius+padding,beam_radius+padding);
	vec2 axis = vec2(clamp(p.x,0.0,beam_length),0.0);
	float distance_to_ray = length(p-axis);
	float edge = distance_to_ray-beam_radius;
	float body = 1.0-smoothstep(-0.8,0.8,edge);
	float core = 1.0-smoothstep(beam_radius*0.12,beam_radius*0.52,distance_to_ray);
	float halo = exp(-max(edge,0.0)*0.20)*0.24;
	float travel = 0.78+0.22*sin(p.x*0.14-clock*28.0);
	vec3 color = beam_color.rgb*(body*0.8+halo)*travel+vec3(1.0,0.91,0.85)*core*1.35;
	float cap_fade = 1.0-smoothstep(beam_radius+2.0,beam_radius+padding,length(vec2(p.x-clamp(p.x,0.0,beam_length),0.0)));
	float heat = exp(-max(edge,0.0)*0.105)*(0.20+0.10*sin(p.x*0.08-clock*10.0));
	color += burning*vec3(1.0,0.13,0.025)*heat;
	color += frost*vec3(0.18,0.7,1.0)*halo*0.9;
	color += toxic*vec3(0.25,1.0,0.06)*halo*0.8;
	color += mind*vec3(0.65,0.1,1.0)*halo*0.8;
	float electricity = 0.0;
	for (int i=0; i<2; i++) {
		float cell = floor(p.x/13.0);
		float cycle = floor(clock*22.0)+float(i)*19.0;
		float jagged = mix(hash(cell+cycle),hash(cell+1.0+cycle),fract(p.x/13.0))*2.0-1.0;
		float side = i==0 ? -1.0 : 1.0;
		float electric_y = side*(beam_radius+4.0)+jagged*5.0;
		electricity += 1.0-smoothstep(0.35,1.2,abs(p.y-electric_y));
	}
	color += chain*vec3(1.0,0.87,0.28)*electricity*cap_fade;
	float far_fade = 1.0-smoothstep(beam_radius+padding-5.0,beam_radius+padding,distance_to_ray);
	COLOR = vec4(color,opacity*cap_fade*far_fade);
}
