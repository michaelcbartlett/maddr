shader_type canvas_item;
render_mode unshaded;
#include "res://levels/water_surface.gdshaderinc"
uniform float clock = 0.0;
uniform float ground_y = 0.0;
varying vec2 world_position;
void vertex() { world_position=(MODEL_MATRIX*vec4(VERTEX,0.0,1.0)).xy; }
void fragment() {
	float wet=water_mask(world_position);
	if(wet<0.01) { discard; }
	vec2 uv=UV;
	uv.x+=sin(floor(world_position.y/2.0)*0.7+clock*3.0)*TEXTURE_PIXEL_SIZE.x*0.7;
	vec4 source=texture(TEXTURE,uv)*COLOR;
	float depth=max(0.0,world_position.y-ground_y);
	float fade=exp(-depth/90.0);
	float ripple=0.7+0.3*water_noise(vec2(floor(world_position.y/2.0),clock*1.5));
	COLOR=vec4(source.rgb*vec3(0.57,0.68,0.82),source.a*wet*fade*ripple*0.33);
}
