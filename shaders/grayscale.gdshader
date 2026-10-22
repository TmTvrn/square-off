// Debug view: drains all color so you can check the value hierarchy (toggle with G).
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;

void fragment() {
	vec3 c = texture(screen_texture, SCREEN_UV).rgb;
	float luma = dot(c, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(vec3(luma), 1.0);
}
