extends Node

########################
## Настройки студий (ATTN_18 §18.3.4, шаг I0); окном студии не управляют (ATTN_22 §22.5.4)
########################
## Свой файл user://icon_studio.cfg, настройки игры (user://settings.cfg) не трогаем.
## Запись отложенная: раз в секунду проверяем, что изменилось, и пишем. Кнопка Stop в редакторе
## не присылает сигнал закрытия окна, поэтому одной записи на выходе мало (ATTN_18 §18.2, п. 6).

## Путь файла настроек. По умолчанию Icon Studio; другие студии (Track Studio) ставят свой до add_child
var path := "user://icon_studio.cfg"
const SAVE_PERIOD := 1.0

var _cfg := ConfigFile.new()
var _dirty := false
var _timer: Timer


func _ready() -> void:
	_cfg.load(path)
	_timer = Timer.new()
	_timer.wait_time = SAVE_PERIOD
	_timer.timeout.connect(flush)
	add_child(_timer)
	_timer.start()


## default = null допустим: ConfigFile на null-умолчании ругается, поэтому проверяем ключ сами
func get_value(section: String, key: String, default: Variant = null) -> Variant:
	if not _cfg.has_section_key(section, key):
		return default
	return _cfg.get_value(section, key)


func set_value(section: String, key: String, value: Variant) -> void:
	# Массивы и словари храним копией: иначе правка «по месту» не отличается от сохранённого значения
	if value is Array or value is Dictionary:
		value = value.duplicate(true)
	if _cfg.has_section_key(section, key) and _cfg.get_value(section, key) == value:
		return
	_cfg.set_value(section, key, value)
	_dirty = true


## Пишет файл, если что-то изменилось
func flush() -> void:
	if not _dirty:
		return
	var err := _cfg.save(path)
	if err == OK:
		_dirty = false
	else:
		push_warning("Studio: не удалось записать %s (код %d)" % [path, err])


## Стирает все настройки
func reset_all() -> void:
	_cfg.clear()
	_dirty = true
