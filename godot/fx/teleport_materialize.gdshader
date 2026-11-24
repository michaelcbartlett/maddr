shader_type canvas_item;
uniform float ground_y=0.0;
uniform float reveal_height=0.0;
uniform float glow=0.0;
varying vec2 world_position;
void vertex(){ world_position=(MODEL_MATRIX*vec4(VERTEX,0.0,1.0)).xy; }
void fragment(){
	if(reveal_height<=0.001){ discard; }
	float edge=world_position.y-(ground_y-reveal_height);
	COLOR.a*=step(0.0,edge);
	float scan=(1.0-smoothstep(0.0,5.0,edge))*step(0.0,edge);
	COLOR.rgb=mix(COLOR.rgb,vec3(0.35,1.0,0.58),clamp(glow*0.7+scan*0.85,0.0,1.0));
}
