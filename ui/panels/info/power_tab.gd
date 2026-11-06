class_name InfoPowerTab extends InfoTab

###########################
## Вкладка «Питание»: контур и напряжение трака, клипса питания, значения поезда
###########################
## Узлы в info_panel.tscn (PowerTab). Трак обновляется по сигналам PGM (update_tab, on_power_track_updated),
## поезд живыми значениями в refresh().
## D1 (ATTN_10): блок «PowerExtras» строится кодом под таблицей трака: состояние цепи и конфликт клипа,
## «Поменять полярность» (клип), «Изостыки» (чекбокс на каждый сокет трака, доступны и без клипа).

var _extra: VBoxContainer
var _sensor_box: CheckBox
var _sensor_label: Label
var _state_label: Label
var _rev_box: CheckBox
var _reset_btn: Button
var _gap_title: Label
var _gap_row: HFlowContainer
var _gap_boxes: Array[CheckBox] = []
## Для какой сущности построены чекбоксы изостыков
var _gap_for: Entity


func _setup() -> void:
	_n("PowerClipButton").pressed.connect(_on_power_clip_button_pressed)
	_n("ClipContourIDButton").item_selected.connect(_on_contour_id_item_selected)
	_build_extras()
	PGM.sensor_triggered.connect(func(_s: C_OccupancySensor, _o: bool) -> void: update_tab())


func _on_bind() -> void:
	_gap_for = null
	update_tab()


## Блок D1 под таблицей трака (в info_panel.tscn не правится)
func _build_extras() -> void:
	var host := _n("PowerTrackTab") as VBoxContainer
	if host == null:
		return
	_extra = VBoxContainer.new()
	_extra.name = "PowerExtras"
	host.add_child(_extra)

	_state_label = Label.new()
	_state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_state_label.custom_minimum_size = Vector2(260, 0)
	_extra.add_child(_state_label)

	_reset_btn = Button.new()
	_reset_btn.text = "Сбросить защиту вывода"
	_reset_btn.pressed.connect(_on_reset_pressed)
	_extra.add_child(_reset_btn)

	_rev_box = CheckBox.new()
	_rev_box.text = "Поменять полярность (провода клипа)"
	_rev_box.toggled.connect(_on_reversed_toggled)
	_extra.add_child(_rev_box)

	_gap_title = Label.new()
	_gap_title.text = "Изостыки (разрыв цепи на стыке):"
	_extra.add_child(_gap_title)
	_gap_row = HFlowContainer.new()
	_extra.add_child(_gap_row)

	# D6: датчик занятости участка
	_sensor_box = CheckBox.new()
	_sensor_box.text = "Датчик занятости участка"
	_sensor_box.toggled.connect(_on_sensor_toggled)
	_extra.add_child(_sensor_box)
	_sensor_label = Label.new()
	_extra.add_child(_sensor_label)


func update_tab() -> void:
	#await get_tree().physics_frame
	if not target: return
	var identity = target.get_comp(C_Identity)
	if not identity: return
	var _category = identity.get_category()
	
	# Power Track
	match _category:
		&'track':
			_n("PowerTrackTab").show()
			_n("PowerTrainTab").hide()
		
			var _power_comp = target.get_comp(C_PowerTrack) as C_PowerTrack
			var _power_clip = target.get_comp(C_PowerClip) as C_PowerClip
			var _path = target.get_comp(C_Path)
			if _path:
				_n("RadiusLabel").text = str(_path.radius) + ' u/sm'
				_n("DegLabel").text = str(_path.deg) + '°'
				_n("LengthLabel").text = str(_path.get_length()) + ' u/sm'
			_update_extras(_power_comp, _power_clip)
			if not _power_comp: # Если трака нет, то в дефолт все
				_n("PowerClipButton").disabled = true
				_n("PowerClipButton").button_pressed = false
				_n("ClipContourIDButton").disabled = true  # запрещаем менять контур
				_n("TrackContourLabel").text = str(0)
				_n("TrackVoltageLabel").text = str(0)
				_n("FlippedLabel").text = str(0) 
				return

			# Трак
			# XX claude-switch: у кросса с раздельными цепями "1 | 2" (по лучу на путь)
			_n("TrackContourLabel").text = _power_comp.contour_text()
			_n("TrackVoltageLabel").text = _power_comp.voltage_text()
			_n("FlippedLabel").text = _power_comp.flip_text()

			# Power Clip. D1: клип можно поставить на любой трак, в том числе уже питаемый (второй фидер цепи)
			_n("PowerClipButton").disabled = false
			_n("PowerClipButton").button_pressed = _power_clip != null
			_n("ClipContourIDButton").disabled = _power_clip == null  # номер меняется только у клипа
			var _net_id: int = _power_clip.net_id if _power_clip else _power_comp.net_id

			# 💡-option_button- Делаем селектор контура-
			_fill_clip_contour_button(_net_id)

			# Цвета 
			if  PGM.get_power(_net_id) > 0:
				_n("TrackVoltageLabel").modulate = Color(0.0, 0.824, 0.0, 1.0)
			elif PGM.get_power(_net_id) < 0:
				_n("TrackVoltageLabel").modulate = Color(1.0, 0.302, 0.043, 1.0)
			else:
				_n("TrackVoltageLabel").modulate = Color(1.0, 1.0, 1.0, 1.0)
				
		&'train':
			_n("PowerTrackTab").hide()
			_n("PowerTrainTab").show()
			refresh()


func refresh() -> void:
	if not target: return
	var identity = target.get_comp(C_Identity)
	if not identity or identity.get_category() != &'train': return

	var _engine_comp = target.get_comp(C_Engine) as C_Engine
	var _chassis_comp = target.get_comp(C_Chassis) as C_Chassis
	if not _engine_comp or not _chassis_comp: return

	_n("EngineContourLabel").text = str(_engine_comp.power.net_id)
	_n("TrainVoltageLabel").text = str(_engine_comp.power.voltage)

	var _spd = _chassis_comp.current_speed
	_n("SpeedLabel").text = str( "%0.2f" % [_spd] if abs(_spd) > 0.05 else '0.0' )
	var _c_force = _chassis_comp.centrifugal_force
	_n("CentrifugalForceLabel").text = tr( "%0.2f" % [_c_force] if abs(_c_force) > 0.05 else '0.0' )

	# Цвета
	var _pw: float = PGM.get_power(_engine_comp.power.net_id)
	if _pw > 0:
		_n("TrainVoltageLabel").modulate = Color(0.0, 0.824, 0.0, 1.0)
		_n("SpeedLabel").modulate = Color(0.0, 0.824, 0.0, 1.0)
	elif _pw < 0:
		_n("TrainVoltageLabel").modulate = Color(1.0, 0.302, 0.043, 1.0)
		_n("SpeedLabel").modulate = Color(1.0, 0.302, 0.043, 1.0)
	else:
		_n("TrainVoltageLabel").modulate = Color(1.0, 1.0, 1.0, 1.0)
		_n("SpeedLabel").modulate = Color(1.0, 1.0, 1.0, 1.0)


func on_power_track_updated(_contour : int, _voltage : float) ->void:
	if not target: return
	
	var _power_comp = target.has_comp(C_PowerTrack)
	if _power_comp: # Если трак
		_power_comp = target.get_comp(C_PowerTrack)
		_n("TrackContourLabel").text = _power_comp.contour_text()
		_n("TrackVoltageLabel").text = _power_comp.voltage_text()
		_n("FlippedLabel").text = _power_comp.flip_text()
	
		if  _voltage > 0:
			_n("TrackVoltageLabel").modulate = Color(0.0, 0.824, 0.0, 1.0)
		elif _voltage < 0:
			_n("TrackVoltageLabel").modulate = Color(1.0, 0.302, 0.043, 1.0)
		else:
			_n("TrackVoltageLabel").modulate = Color(1.0, 1.0, 1.0, 1.0)


func _on_contour_id_item_selected(index: int):
	if not target: return
	
	var power_clip = target.has_comp(C_PowerClip)
	if power_clip:
		power_clip = target.get_comp(C_PowerClip)

	if not power_clip: return
	
	# Извлекаем зашитый ID контура из выбранного пункта меню
	var new_contour_id = _n("ClipContourIDButton").get_item_id(index)
	
	# Если значение изменилось — обновляем данные компонента
	if power_clip.net_id != new_contour_id:
		power_clip.set_contour(new_contour_id)
		# Вешаем на трак новый контур (пересчет сети поправит остальные траки)
		target.get_comp(C_PowerTrack).net_id = new_contour_id
		
		#await get_tree().physics_frame
		
		PGM.request_recalculate()
		# На всякий случай перерисовываем панель, чтобы закрепить состояние
		update_tab()


func _on_power_clip_button_pressed() -> void:
	
	if not target or not target.has_comp(C_PowerTrack):
		return # это powertrack?
	
	var _btn_pressed: bool = _n("PowerClipButton").button_pressed
	# Выбор контура: трак уже в цепи (второй фидер), иначе номер из списка (0 = первый свободный)
	var _contour: int = (target.get_comp(C_PowerTrack) as C_PowerTrack).net_id
	if _contour == 0:
		var _btn := _n("ClipContourIDButton") as OptionButton
		_contour = _btn.get_item_id(_btn.selected) if _btn.selected >= 0 else 0
	
	# Менеджер проверит и создаст (0 если свободных номеров нет)
	_contour = PGM.create_power_clip(target, _contour, _btn_pressed)
	if _btn_pressed and _contour == 0:
		_n("PowerClipButton").button_pressed = false
	update_tab()


func _fill_clip_contour_button(_current_contour_id) -> void:
	var option_button = _n("ClipContourIDButton") as OptionButton
	option_button.clear() # Полностью очищаем старые пункты
	
	# 1.1️⃣ Добавляем базовый вариант (0 - отключено от питания)
	option_button.add_item("0: Отключено", 0)
	
	# Получаем массив контуров, которые УЖЕ заняты другими клеммами на макете
	var occupied_contours = PGM.get_occupied_contours()
	var current_id = _current_contour_id # Текущий контур этого объекта

	# 2. 2️⃣ Все номера: у цепи может быть несколько фидеров, занятый номер отмечается, но выбирается
	# D2: список выводов всех источников («Вывод 3», у dual «Вывод 11 · A»), не только 10 первых
	for i in PGM.all_labels():
		var _text := PGM.label_text(i)
		if i != current_id and i in occupied_contours:
			_text += " (занят)"
		else:
			_text += " (свободен)"
		option_button.add_item(_text, i) # Текст и внутренний ID элемента
	
	# 3. 3️⃣ Выставляем визуальный фокус на текущий контур объекта
	# Так как мы передавали реальный ID контура вторым аргументом в add_item,
	# мы можем легко найти индекс нужной строки
	for idx in range(option_button.item_count):
		if option_button.get_item_id(idx) == current_id:
			option_button.select(idx)
			break


## Блок D1: состояние цепи, «Поменять полярность», изостыки
func _on_sensor_toggled(on: bool) -> void:
	if target == null:
		return
	if on and not target.has_comp(C_OccupancySensor):
		target.add_component(C_OccupancySensor.new())
	elif not on:
		target.remove_component(C_OccupancySensor)
	_update_extras(target.get_comp(C_PowerTrack) as C_PowerTrack, target.get_comp(C_PowerClip) as C_PowerClip)


func _update_extras(power_track: C_PowerTrack, clip: C_PowerClip) -> void:
	if _extra == null:
		return
	_extra.visible = power_track != null
	if power_track == null:
		return
	var sensor := target.get_comp(C_OccupancySensor) as C_OccupancySensor
	_sensor_box.set_pressed_no_signal(sensor != null)
	_sensor_label.visible = sensor != null
	if sensor != null:
		_sensor_label.text = "Участок %s, проходов: %d" % [sensor.state_text(), sensor.passes]
		_sensor_label.modulate = Color(1.0, 0.45, 0.2) if sensor.occupied else Color(0.4, 0.9, 0.4)

	# Состояние: что не так с клипом, треком или цепью
	var lines: PackedStringArray = []
	if clip and clip.conflict_text() != "":
		lines.append(clip.conflict_text())
	if power_track.fault:
		lines.append("КЗ: здесь не сходится полярность (реверсивная петля или перепутанные провода)")
	if clip and clip.wired:
		lines.append("Питается по проводу от вывода %d%s" % [clip.wire_net, " (скрутка)" if clip.wire_flip else ""] if clip.wire_net != 0 else "Провод подключен, но не доходит до вывода пульта: клип обесточен")
	elif clip and PGM.wiring_required:
		lines.append("Проводка обязательна: клипу нужен провод от пульта")
	var net_id: int = clip.net_id if clip else power_track.net_id
	if net_id != 0 and PGM.shorted_nets.has(net_id):
		lines.append("Цепь %d в КЗ полярности: защита отключает напряжение (сброс: кнопка ниже после устранения причины)" % net_id)
	var out: PowerOutput = PGM.get_output(net_id) if net_id != 0 else null
	if out != null and out.tripped:
		lines.append("Вывод %d отключен защитой: %s" % [net_id, out.state_text()])
	elif out != null and out.state == PowerOutput.State.OVERLOAD:
		lines.append("Перегрузка вывода %d: %.2f А при лимите %.2f А" % [net_id, out.current, out.i_max])
	_reset_btn.visible = out != null and out.tripped
	_state_label.text = "\n".join(lines)
	_state_label.visible = not lines.is_empty()
	_state_label.modulate = Color(1.0, 0.45, 0.2, 1.0)

	# Полярность подключения клипа
	_rev_box.visible = clip != null
	if clip:
		_rev_box.set_pressed_no_signal(clip.reversed)

	# Изостыки: чекбокс на каждый сокет (пересобираются при смене цели)
	var sock := target.get_comp(C_Socket) as C_Socket
	var count: int = sock.sockets.size() if sock else 0
	if _gap_for != target or _gap_boxes.size() != count:
		_rebuild_gap_boxes(sock, count)
	for i in _gap_boxes.size():
		_gap_boxes[i].set_pressed_no_signal(sock.is_gap(i))
	var gaps_on: bool = PGM.rules.gaps_enabled   # D7: при gaps_enabled = false изостыки скрыты
	_gap_title.visible = count > 0 and gaps_on
	_gap_row.visible = count > 0 and gaps_on


func _rebuild_gap_boxes(sock: C_Socket, count: int) -> void:
	for b in _gap_boxes:
		if is_instance_valid(b):
			b.queue_free()
	_gap_boxes.clear()
	_gap_for = target
	for i in count:
		var box := CheckBox.new()
		box.text = "%d: %s" % [i, sock.socket_label(i)]
		box.toggled.connect(_on_gap_toggled.bind(i))
		_gap_row.add_child(box)
		_gap_boxes.append(box)


func _on_reversed_toggled(on: bool) -> void:
	if not target:
		return
	var clip := target.get_comp(C_PowerClip) as C_PowerClip
	if clip:
		clip.set_reversed(on)


func _on_gap_toggled(on: bool, socket_index: int) -> void:
	if not target:
		return
	var sock := target.get_comp(C_Socket) as C_Socket
	if sock:
		sock.set_gap(socket_index, on)


## Сброс защиты вывода этого фидера. Если причина не устранена, защита сработает снова
func _on_reset_pressed() -> void:
	if not target:
		return
	var clip := target.get_comp(C_PowerClip) as C_PowerClip
	var pt := target.get_comp(C_PowerTrack) as C_PowerTrack
	var net_id: int = clip.net_id if clip else (pt.net_id if pt else 0)
	if net_id != 0:
		PGM.reset_output(net_id)
	update_tab()
