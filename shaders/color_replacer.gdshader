shader_type canvas_item;

// 色彩替换
uniform vec4 color_1 : source_color = vec4(1.0);
uniform vec4 color_replace_1 : source_color;
uniform float color_threshold_1 : hint_range(0.0, 1.0, 0.001) = 0.01;

uniform vec4 color_2 : source_color = vec4(1.0);
uniform vec4 color_replace_2 : source_color;
uniform float color_threshold_2 : hint_range(0.0, 1.0, 0.001) = 0.01;

uniform vec4 color_3 : source_color = vec4(1.0);
uniform vec4 color_replace_3 : source_color;
uniform float color_threshold_3 : hint_range(0.0, 1.0, 0.001) = 0.01;

void fragment() {
	vec4 color = texture(TEXTURE, UV);

	// 颜色替换
	float dis_color_1 = length(color.rgb - color_1.rgb);
	float dis_color_2 = length(color.rgb - color_2.rgb);
	float dis_color_3 = length(color.rgb - color_3.rgb);
	if (dis_color_1 < color_threshold_1) {
		color = color_replace_1;
	} else if (dis_color_2 < color_threshold_2) {
		color = color_replace_2;
	} else if (dis_color_3 < color_threshold_3) {
		color = color_replace_3;
	}

	COLOR = color;
}
