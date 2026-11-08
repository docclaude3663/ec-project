class_name LibraryScreen extends Control

# XX claude-library (новый файл)
########################
## LibraryScreen. Экран Library (Model Studio), ATTN_22 §22.5, шаг L1
########################
## Одно окно, один 3D-мир (StudioWorld, как в Icon Studio) и сменные рабочие области справа. Интерфейс собирается кодом.
## Два способа запуска:
##   - оверлей поверх игры (ModeController): дерево на паузе, 3D главного вьюпорта выключено на время;
##   - отдельно (F6 на library_screen.tscn): окно как у студий, без паузы, кнопки «Назад» нет.
## Объект показывает StudioWorld через EntityFactory (как в игре), в своём World3D. Закрытая модель показывается силуэтом.
## При закрытии объект убирается через kill_me (снимает регистрацию в PGM), пауза и 3D возвращаются.

signal closed
## Поставить выбранную модель в игре (L4): ModeController закрывает экран и включает Build с этим исполнением.
## variant пуст, если покраски нет
signal place_requested(setting: EntitySetting, variant: Dictionary)

const StudioWorld := preload("res://core/library/icon_studio/studio_world.gd")
const StudioSettings := preload("res://core/library/icon_studio/studio_settings.gd")
const StageClean := preload("res://core/library/stage/stage_clean.gd")
const Overview := preload("res://core/library/workspace/overview.gd")
const Paint := preload("res://core/library/workspace/paint.gd")

const SETTINGS_PATH := "user://library.cfg"
## Кадров «settle» после создания объекта (как DEFAULT_SETTLE в Icon Studio)
const SETTLE_FRAMES := 2
## Выключать 3D главного вьюпорта, пока открыт экран (в игре под экраном рисовать нечего)
const DISABLE_GAME_3D := true
## Цвет силуэта закрытой модели (ATTN_22 §22.7.1)
const SILHOUETTE_COLOR := Color(0.13, 0.14, 0.16)
## Области экрана: id, название, включена ли (остальные включаются шагами L3 и дальше)
const WORKSPACE_TABS := [
	[&"overview", "Осмотр", true],
	[&"paint", "Покраска", true],
	[&"parts", "Детали", false],
	[&"fit", "Свет", false],
	[&"test", "Стенд", false],
	[&"building", "Здания", false],
	[&"kit", "Сборка", false],
	[&"restore", "Реставрация", false],
]
const HINT_TEXT := "ЛКМ: вращать   ·   Shift+ЛКМ, СКМ, ПКМ: сдвиг   ·   колесо: зум   ·   F: вписать   ·   1–6: ракурс (Shift: сохранить)   ·   Esc: назад"

var rules: LibraryRules
var profile: LibraryProfile
var settings: StudioSettings
var world: StudioWorld
var stage: LibraryStage
var workspace: LibraryWorkspace
var catalog: LibraryCatalog
## Буфер исполнения показанной модели: его правит рабочая область «Покраска». Сбрасывается при выборе другой модели
var variant: ModelVariant = ModelVariant.new()
## Показанная модель (null, пока ничего не выбрано)
var current_setting: EntitySetting:
	get:
		return _current

var _embedded := false
var _prev_paused := false
var _prev_disable_3d: Variant = false
var _vp: Viewport
var _viewport: SubViewport
var _view_area: PanelContainer
var _right_box: VBoxContainer
var _rules_label: Label
var _current: EntitySetting
var _closing := false
var _tab_buttons := {}      # id области -> Button
var _place_btn: Button
var _subject_ready := false
var _last_info: Dictionary = {}
var _last_ms := 0


func _ready() -> void:
	_embedded = get_tree().current_scene != self
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Корень из PackedScene под CanvasLayer получает размер 0: якоря из сцены считались до входа в дерево,
	# а перерасчёта никто не вызывает. Без этого экран схлопывается до минимального размера и не закрывает игру
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	settings = StudioSettings.new()
	settings.name = "StudioSettings"
	settings.path = SETTINGS_PATH
	add_child(settings)
	if not _embedded:
		settings.restore_window()
		get_window().title = "Library · Model Studio"

	profile = VariantIO.load_profile()
	rules = LibraryRules.from_dict(profile.rules) if not profile.rules.is_empty() else LibraryRules.make(LibraryRules.Source.SANDBOX, LibraryRules.Preset.STANDARD)

	_build_ui()
	_build_world()
	_set_workspace(Overview.new())
	_enter_overlay_state()

	# Размеры контейнеров известны только после первого кадра раскладки
	await get_tree().process_frame
	_select_last()


func _exit_tree() -> void:
	if settings:
		settings.flush()
	_leave_overlay_state()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and settings:
		settings.flush()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if workspace != null and workspace.handle_key(k):
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_F:
		world.fit()
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_ESCAPE and _embedded:
		close()
		get_viewport().set_input_as_handled()


## Закрыть экран (в оверлее). Область может отказать, если у неё несохранённая работа
func close() -> void:
	if not _embedded or _closing:
		return
	if workspace != null and not workspace.can_leave():
		return
	_closing = true
	if workspace != null:
		workspace.exit()
	# kill_me снимает регистрацию объекта в PGM; просто освободить дерево недостаточно
	world.clear_subject()
	closed.emit()
	queue_free()


# ==========================================
# ОВЕРЛЕЙ: ПАУЗА И 3D ИГРЫ
# ==========================================

func _enter_overlay_state() -> void:
	if not _embedded:
		return
	_prev_paused = get_tree().paused
	get_tree().paused = true
	_vp = get_viewport()
	if DISABLE_GAME_3D and _vp != null:
		_prev_disable_3d = _vp.get("disable_3d")
		_vp.set("disable_3d", true)


func _leave_overlay_state() -> void:
	if not _embedded:
		return
	if DISABLE_GAME_3D and _vp != null and is_instance_valid(_vp):
		_vp.set("disable_3d", _prev_disable_3d)
	var tree := get_tree()
	if tree != null:
		tree.paused = _prev_paused


# ==========================================
# ИНТЕРФЕЙС
# ==========================================

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.09, 0.1)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	# set_anchors_preset без offsets оставляет прежний (нулевой) размер, поэтому именно _and_offsets_
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	margin.add_child(root)
	root.add_child(_build_header())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	root.add_child(body)
	body.add_child(_build_left())
	body.add_child(_build_center())
	body.add_child(_build_right())

	var hint := Label.new()
	hint.text = HINT_TEXT
	hint.modulate = Color(1, 1, 1, 0.6)
	root.add_child(hint)


func _build_header() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)

	if _embedded:
		var back := Button.new()
		back.text = "← Назад"
		back.pressed.connect(close)
		h.add_child(back)

	var title := Label.new()
	title.text = "LIBRARY · Model Studio"
	h.add_child(title)

	var group := ButtonGroup.new()
	for t in WORKSPACE_TABS:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.button_group = group
		b.disabled = not t[2]
		b.button_pressed = t[0] == &"overview"
		if b.disabled:
			b.tooltip_text = "Включится в следующих шагах (ATTN_22 §22.9)"
		else:
			b.pressed.connect(_on_tab.bind(t[0]))
		_tab_buttons[t[0]] = b
		h.add_child(b)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)

	_rules_label = Label.new()
	_rules_label.text = "Правила: " + rules.label()
	h.add_child(_rules_label)
	if Global.debug_mode:
		var cycle := Button.new()
		cycle.text = "Правила ⟳"
		cycle.tooltip_text = "Отладка: переключить источник (песочница, кампания) и пресет сложности"
		cycle.pressed.connect(_on_cycle_rules)
		h.add_child(cycle)
	return h


func _build_left() -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(280, 0)
	catalog = LibraryCatalog.new(rules, profile)
	catalog.object_selected.connect(_show_object)
	p.add_child(catalog)
	return p


func _build_center() -> Control:
	_view_area = PanelContainer.new()
	_view_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view_area.custom_minimum_size = Vector2(320, 240)
	_view_area.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.11)
	_view_area.add_theme_stylebox_override("panel", bg)
	return _view_area


func _build_right() -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(320, 0)
	var v := VBoxContainer.new()
	p.add_child(v)
	_right_box = VBoxContainer.new()
	_right_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_right_box)
	v.add_child(HSeparator.new())
	_place_btn = Button.new()
	_place_btn.text = "В игру"
	_place_btn.disabled = true
	_place_btn.tooltip_text = "Поставить выбранную модель в игре вместе с покраской. Доступно при запуске из игры"
	_place_btn.pressed.connect(_on_place_pressed)
	v.add_child(_place_btn)
	return p


# ==========================================
# 3D-МИР
# ==========================================

func _build_world() -> void:
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view_area.add_child(svc)

	# Отдельный World3D: объекты Library не видны игре и не видят её (в том числе физика)
	var studio_world3d := World3D.new()
	_viewport = SubViewport.new()
	_viewport.world_3d = studio_world3d
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.handle_input_locally = false
	svc.add_child(_viewport)

	world = StudioWorld.new()
	world.name = "StudioWorld"
	_viewport.add_child(world)
	_view_area.gui_input.connect(world.handle_gui_input)
	var views: Array[SubViewport] = [_viewport]
	world.register_views(views, null)

	stage = StageClean.new()
	stage.apply(world)


# ==========================================
# КАТАЛОГ И ПОКАЗ ОБЪЕКТА
# ==========================================

## Последний показанный объект (или первый в списке), без повторной загрузки, если он уже выбран
func _select_last() -> void:
	var last := str(settings.get_value("state", "last_key", ""))
	if last != "" and catalog.select_key(StringName(last)):
		return
	var first := catalog.first_visible_key()
	if first != &"":
		catalog.select_key(first)


## keep_variant: оставить буфер исполнения (перезагрузка той же модели при смене правил)
func _show_object(s: EntitySetting, keep_variant := false) -> void:
	if s == _current:
		return
	_current = s
	_subject_ready = false
	if not keep_variant:
		variant = ModelVariant.new()
		variant.base = String(s.get_key())
	settings.set_value("state", "last_key", String(s.get_key()))
	if workspace != null:
		workspace.on_loading(s)
	var t0 := Time.get_ticks_msec()
	var info: Dictionary = await world.set_subject(s, StudioWorld.SOURCE_ENTITY, SETTLE_FRAMES)
	if info.stale or s != _current or _closing:
		return
	if info.ok:
		world.fit()
		# Закрытая модель: тёмный силуэт без материалов (ATTN_22 §22.7.1)
		if catalog.is_locked(s.get_key()):
			_apply_silhouette(world.subject)
		elif not PaintData.is_empty(variant.paint):
			apply_variant()
	_subject_ready = info.ok
	_last_info = info
	_last_ms = Time.get_ticks_msec() - t0
	_place_btn.disabled = not _embedded or not info.ok or catalog.is_locked(s.get_key())
	if workspace != null:
		workspace.on_subject(s, info, _last_ms)


func _apply_silhouette(root: Node) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = SILHOUETTE_COLOR
	_silhouette_walk(root, mat)


func _silhouette_walk(n: Node, mat: Material) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_override = mat
		(n as MeshInstance3D).material_overlay = null
	for c in n.get_children():
		_silhouette_walk(c, mat)


# ==========================================
# ИСПОЛНЕНИЕ МОДЕЛИ (L3, L4)
# ==========================================

## Меши кузова показанной модели (C_Visual.mesh_nodes). Тележки и колёса строятся позже и сюда не входят
func body_meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var ent := world.subject as Entity if world != null else null
	if ent == null or not is_instance_valid(ent):
		return out
	var vis := ent.get_comp(C_Visual) as C_Visual
	if vis == null:
		return out
	for m in vis.mesh_nodes:
		if is_instance_valid(m):
			out.append(m)
	return out


## Применить буфер исполнения к показанной модели (идемпотентно: повторное применение не наслаивает материалы)
func apply_variant() -> void:
	VariantApplier.apply(body_meshes(), variant.to_dict())


func is_current_locked() -> bool:
	return _current != null and catalog.is_locked(_current.get_key())


func _on_place_pressed() -> void:
	if _current == null or not _subject_ready or catalog.is_locked(_current.get_key()):
		return
	var v: Dictionary = {} if PaintData.is_empty(variant.paint) else variant.to_dict()
	place_requested.emit(_current, v)


# ==========================================
# ОБЛАСТИ И ПРАВИЛА
# ==========================================

func _set_workspace(ws: LibraryWorkspace) -> void:
	if workspace != null:
		workspace.exit()
		_right_box.remove_child(workspace)
		workspace.queue_free()
	workspace = ws
	workspace.setup(self)
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right_box.add_child(workspace)
	workspace.enter()


## Вкладка области. Если у текущей области несохранённая работа, она может не пустить
func _on_tab(id: StringName) -> void:
	if workspace != null and workspace.id == id:
		return
	if workspace != null and not workspace.can_leave():
		(_tab_buttons[workspace.id] as Button).button_pressed = true
		return
	var ws: LibraryWorkspace
	match id:
		&"paint":
			ws = Paint.new()
		_:
			ws = Overview.new()
	_set_workspace(ws)
	if _current != null and _subject_ready:
		ws.on_subject(_current, _last_info, _last_ms)


func _on_cycle_rules() -> void:
	rules.cycle_debug()
	_rules_label.text = "Правила: " + rules.label()
	profile.rules = rules.to_dict()
	VariantIO.save_profile(profile)
	# Замки и силуэт зависят от правил: перекрасить список и перезагрузить объект
	catalog.refresh_locks()
	if _current != null:
		var cur := _current
		_current = null
		_show_object(cur, true)
