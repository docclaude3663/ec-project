// XX claude-library (новый файл)
// Ластик: тот же штамп, но слой умножается на (1 - покрытие). blend_mul умножает и цвет, и альфу слоя;
// слой хранит премультиплицированный цвет, поэтому умножение всех каналов на одно число стирает правильно.
shader_type canvas_item;
render_mode blend_mul;

uniform sampler2D pos_tex : filter_nearest, repeat_disable;
uniform sampler2D nrm_tex : filter_nearest, repeat_disable;
uniform vec4 stamps[32];
uniform vec4 stamp_nrm[32];
uniform int stamp_count = 0;
uniform vec4 brush_color = vec4(1.0);   // не используется, нужен для общего кода движка
uniform float flow : hint_range(0.0, 1.0) = 1.0;
uniform float hardness : hint_range(0.0, 0.99) = 0.5;

void fragment() {
	vec4 p = texture(pos_tex, UV);
	if (p.a < 0.5) {
		discard;
	}
	vec3 n = normalize(texture(nrm_tex, UV).xyz);
	float a = 0.0;
	for (int i = 0; i < 32; i++) {
		if (i >= stamp_count) {
			break;
		}
		float d = distance(p.xyz, stamps[i].xyz) / max(stamps[i].w, 0.00001);
		float c = 1.0 - smoothstep(hardness, 1.0, d);
		float facing = smoothstep(0.05, 0.35, dot(n, normalize(stamp_nrm[i].xyz)));
		c *= facing * flow;
		a = a + c * (1.0 - a);
	}
	float k = 1.0 - a;
	COLOR = vec4(k, k, k, k);
}
