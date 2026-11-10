// XX claude-library (новый файл)
// Копирует картинку в слой без смешивания (отмена, повтор, очистка, загрузка). blend_disabled пишет значения как есть,
// в том числе альфу, поэтому премультиплицированный цвет слоя не искажается.
shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D src : filter_nearest, repeat_disable;

void fragment() {
	COLOR = texture(src, UV);
}
