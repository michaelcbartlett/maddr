shader_type canvas_item;
render_mode unshaded;
uniform sampler2D explored_mask : filter_linear, repeat_disable;
uniform vec2 player_position = vec2(4096.0);
uniform vec2 world_size = vec2(8192.0);
uniform float vision_radius = 240.0;
void fragment() {
	float known = texture(explored_mask,UV).r;
	float visibility = smoothstep(vision_radius*0.65,vision_radius,length(UV*world_size-player_position));
	COLOR = vec4(0.015,0.025,0.04,mix(0.985,0.62,known)*visibility);
}
