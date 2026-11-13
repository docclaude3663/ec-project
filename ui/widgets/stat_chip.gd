class_name StatChip extends HBoxContainer

# U9 (ATTN_17 §17.4): новый файл
## Чип статистики: иконка (или короткая подпись), значение, тултип. Видимостью по нулю и по месту
## управляет TopBar: чип только говорит, есть ли у него что показать (has_value).

@onready var _icon: TextureRect = %Icon
@onready var _short: Label = %Short
@onready var _value: Label = %Value

var spec: StatSpec
var has_value := false


func setup(s: StatSpec) -> void:
	spec = s
	tooltip_text = s.title
	_icon.texture = s.icon
	_icon.visible = s.icon != null
	_short.text = s.short
	_short.visible = s.icon == null
	set_value(0.0)


func set_value(v: float) -> void:
	_value.text = spec.format(v)
	has_value = not (spec.hide_zero and is_zero_approx(v))


## Строка для списка «…», когда чип не поместился
func summary() -> String:
	return "%s: %s" % [spec.title, _value.text]
