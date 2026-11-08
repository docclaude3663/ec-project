class_name MarqueeOverlay extends Control

# XX claude-switch (новый файл)
## Рамка выделения на экране (полупрозрачный прямоугольник с контуром). Мышь не перехватывает.

var _rect := Rect2()


func _init() -> void:
	name = "MarqueeOverlay"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


## Rect2() скрывает рамку
func set_rect(r: Rect2) -> void:
	_rect = r
	queue_redraw()


func _draw() -> void:
	if _rect.size.x < 1.0 and _rect.size.y < 1.0:
		return
	draw_rect(_rect, Color(0.69, 0.49, 1.0, 0.14), true)
	draw_rect(_rect, Color(0.69, 0.49, 1.0, 0.95), false, 1.5)
