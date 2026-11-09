// XX claude-library (новый файл)
// C2.0: штамп кисти по 3D-позиции (ATTN_22 §22.7.2.1). Рисуется в SubViewport размером с карту краски.
// Для каждого текселя берётся его позиция на модели (карта позиций, UV2) и сравнивается с центрами штампов.
// Накопление в SubViewport идёт за счёт render_target_clear_mode = ONCE и blend_mix: кадр дорисовывается поверх прежнего.
shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D pos_tex : filter_nearest, repeat_disable;   // xyz: позиция, a: 1 если тексель покрыт
uniform sampler2D nrm_tex : filter_nearest, repeat_disable;   // xyz: нормаль
uniform vec4 stamps[32];       // xyz: центр штампа (локальные координаты меша), w: радиус
uniform vec4 stamp_nrm[32];    // xyz: нормаль в точке попадания
uniform int stamp_count = 0;
uniform vec4 brush_color = vec4(1.0, 0.0, 0.0, 1.0);
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
		// не красить обратную сторону тонких деталей: нормаль текселя должна смотреть туда же, что и нормаль попадания
		float facing = smoothstep(0.05, 0.35, dot(n, normalize(stamp_nrm[i].xyz)));
		c *= facing * flow;
		a = a + c * (1.0 - a);
	}
	COLOR = vec4(brush_color.rgb, a);
}
