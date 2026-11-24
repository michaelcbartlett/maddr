// Shared by the floor and reflected sprites, so water edges agree exactly.
uniform sampler2D water_map : filter_linear, repeat_disable;
uniform vec2 water_world_size = vec2(3200.0,2200.0);
uniform bool use_water_map = false;
float water_hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float water_noise(vec2 p) {
	vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(water_hash(i),water_hash(i+vec2(1.0,0.0)),f.x),mix(water_hash(i+vec2(0.0,1.0)),water_hash(i+vec2(1.0)),f.x),f.y);
}
float water_field(vec2 w) {
	if(use_water_map) { return texture(water_map,w/water_world_size).r; }
	vec2 p=floor(w/2.0)*vec2(0.009,0.016)+vec2(3.1,7.7);
	float value=0.0; float amplitude=0.5;
	for(int i=0;i<4;i++) { value+=amplitude*water_noise(p); p=p*2.03+11.7; amplitude*=0.5; }
	return value;
}
float water_mask(vec2 w) { return smoothstep(0.525,0.565,water_field(w)); }
