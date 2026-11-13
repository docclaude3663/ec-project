class_name StatSpec extends RefCounted

# U9 (ATTN_17 §17.4): новый файл
## Описание одного чипа статистики данными (id, подписи, поле LayoutStats, формат).
## Новый чип добавляется строкой в список TopBar.stat_specs(), сцену трогать не нужно.

var id: StringName
## Полное название: тултип чипа и строка в списке «…»
var title := ""
## Короткая подпись, если у чипа нет иконки
var short := ""
var icon: Texture2D
## Имя поля в LayoutStats
var key: StringName
var unit := ""
var decimals := 0
## Нулевое значение скрывает чип
var hide_zero := true


static func make(p_id: StringName, p_title: String, p_short: String, p_key: StringName,
		p_icon: String = "", p_unit: String = "", p_decimals: int = 0, p_hide_zero: bool = true) -> StatSpec:
	var s := StatSpec.new()
	s.id = p_id
	s.title = p_title
	s.short = p_short
	s.key = p_key
	if p_icon != "" and ResourceLoader.exists(p_icon):
		s.icon = load(p_icon) as Texture2D
	s.unit = p_unit
	s.decimals = p_decimals
	s.hide_zero = p_hide_zero
	return s


func format(v: float) -> String:
	var txt := String.num(v, decimals)
	return txt if unit == "" else "%s %s" % [txt, unit]
