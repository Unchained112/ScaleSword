shader_type canvas_item;

uniform vec4 key_color : source_color = vec4(0.13333334, 0.13725491, 0.13725491, 1.0);
uniform float key_threshold : hint_range(0.0, 0.5, 0.001) = 0.03;
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform float charge_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	vec4 color = texture(TEXTURE, UV);
	if (distance(color.rgb, key_color.rgb) < key_threshold) {
		color.a = 0.0;
	}
	color *= tint;
	vec3 charged = mix(color.rgb, vec3(1.0, 0.26, 0.08), charge_amount * 0.82);
	vec3 flashed = mix(charged, vec3(1.0), flash_amount);
	COLOR = vec4(flashed, color.a);
}
