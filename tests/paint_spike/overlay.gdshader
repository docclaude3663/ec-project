// XX claude-library (новый файл)
// C2.0: накладка краски поверх материала модели (ATTN_22 §22.7.2.1). Читает слой краски по UV2.
// Переключатели нужны, чтобы прототип показал, как именно хранится цвет в SubViewport:
//   premultiplied: слой хранит цвет, умноженный на альфу (так складывается blend_mix в пустой буфер);
//   srgb_decode: 2D рисует в sRGB-значениях, поэтому для ALBEDO их надо перевести в линейные.
//   push: сдвиг вершин по нормали, если накладка мерцает (z-fighting) на совпадающей геометрии.
shader_type spatial;
render_mode blend_mix, cull_back;

uniform sampler2D layer : filter_linear, repeat_disable;
uniform bool premultiplied = true;
uniform bool srgb_decode = true;
uniform float push = 0.0;
uniform float rough : hint_range(0.0, 1.0) = 0.6;
uniform float metal : hint_range(0.0, 1.0) = 0.0;

void vertex() {
	VERTEX += NORMAL * push;
}

void fragment() {
	vec4 c = texture(layer, UV2);
	vec3 col = c.rgb;
	if (premultiplied) {
		col = c.a > 0.0001 ? c.rgb / c.a : vec3(0.0);
	}
	if (srgb_decode) {
		col = pow(max(col, vec3(0.0)), vec3(2.2));
	}
	ALBEDO = col;
	ALPHA = c.a;
	ROUGHNESS = rough;
	METALLIC = metal;
}
