shader_type spatial;
render_mode diffuse_toon, specular_toon;

uniform sampler2D heightmap;
uniform sampler2D normalmap;
uniform float max_height;
uniform mat4 inverse_transform;
varying float v_hole;

float height(vec2 position) {
	return texture(heightmap, position).r * max_height;
}

void vertex() {
	vec4 wpos = WORLD_MATRIX * vec4(VERTEX, 1);
	vec2 cell_coords = vec2(1024, 1024) + (inverse_transform * wpos).xz;
	cell_coords += vec2(0.5);
	
	UV = cell_coords / vec2(textureSize(heightmap, 0));

	float h = height(UV);
	v_hole = texture(heightmap, UV).a;

	VERTEX.y = h;
	
	NORMAL = normalize(vec3(h - height(UV + vec2(1, 0.0)), 0.1, h - height(UV + vec2(0.0, 1))));
}

void fragment() {
	if (v_hole < 0.5) {
		discard;
	}
	
	ROUGHNESS = 1.0;
	ALBEDO = texture(heightmap, UV).rgb;
	NORMALMAP = texture(normalmap, UV).xyz;
}