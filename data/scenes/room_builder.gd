class_name RoomBuilder extends Node3D

########################
## RoomRoot. Строит комнату из RoomConfig под собой. НЕ в EntitiesRoot и не сохраняется (TDD §14.1).
########################
## S2: greybox из коробок (пол, стены с проёмами, потолок, мебель-заглушки) + подмакетник.
## Подмакетник (Table): верх на слое ground, ножки на room. Он не скрывается кнопкой «Комната».
## Всё остальное (Room) на слое room (физика) и на visual layer Global.ROOM_VISUAL_LAYER.
## Комната слушает ObserveController.observe_action (категория room), про поезда не знает ничего.

## ⚡ Комнату показали или спрятали (CameraBounds выключает ограничение)
signal room_visible_changed(on: bool)

@export var config: RoomConfig
## Стены и потолок не отбрасывают тень: иначе низкое солнце затемнит стол. Окно и рама в S4
@export var walls_cast_shadow := false
## В режиме Observe стены отбрасывают тень: на столе виден рисунок окна. В остальных режимах свет ровный
@export var window_shadows_in_observe := true
## Временный свет для проверки масштаба. Включать, только если в главной сцене нет своего солнца
@export var temp_light := false

var visuals: Node3D    # пол, стены, потолок, мебель
var ceiling: Node3D
var _ceiling_mesh: MeshInstance3D   # плита потолка: скрытая в Observe, она всё равно отбрасывает тень (закрывает солнце сверху)
var table: Node3D

var _mats := {}
var _walls: Array[MeshInstance3D] = []   # стены, рама, шторы и подоконник: тень только в Observe
var _decor: RoomDecor
var _wall_col := Color(0.80, 0.79, 0.76)
var _room_visible := true
var _ceiling_visible := false
var _walls_shadow_now := false

const COL_CEILING := Color(0.90, 0.90, 0.88)
const COL_TABLE := Color(0.62, 0.50, 0.38)
const COL_TABLE_LEG := Color(0.45, 0.36, 0.28)

## Мебель-заглушки. size: X, Y(высота), Z. xz: центр на полу. По §14.4
const PROPS := [
	{"name": "Bed", "size": Vector3(90, 45, 200), "xz": Vector2(-195, -90), "color": Color(0.55, 0.62, 0.78)},
	{"name": "Desk", "size": Vector3(60, 75, 120), "xz": Vector2(210, 40), "color": Color(0.72, 0.60, 0.45)},
	{"name": "Chair", "size": Vector3(40, 45, 40), "xz": Vector2(160, 40), "color": Color(0.50, 0.50, 0.55)},
	{"name": "Wardrobe", "size": Vector3(100, 200, 50), "xz": Vector2(-190, 165), "color": Color(0.66, 0.55, 0.42)},
	{"name": "Shelf", "size": Vector3(80, 180, 30), "xz": Vector2(200, -175), "color": Color(0.70, 0.58, 0.40)},
	{"name": "Rug", "size": Vector3(160, 1, 110), "xz": Vector2(0, 125), "color": Color(0.78, 0.45, 0.40), "collide": false},
]


func _ready() -> void:
	if config == null:
		config = RoomConfig.new()
	if Global.fast_debug:
		# Режим быстрой загрузки: комнату не строим, подмакетником служит скрытый WoodFloor из сцены
		print("[FAST] комната не строится, пол WoodFloor")
		_use_wood_floor()
		return
	add_to_group(&"room_root")
	_walls_shadow_now = walls_cast_shadow
	build()
	_connect_observe()
	_connect_gfx()


## Debug: включает старую большую землю (WoodFloor) вместо подмакетника и комнаты
func _use_wood_floor() -> void:
	var f := get_tree().root.find_child("WoodFloor", true, false) as Node3D
	if f == null:
		push_warning("RoomBuilder: WoodFloor не найден, в fast_debug нет земли")
		return
	f.visible = true
	var shape := f.find_child("CollisionShape3D", true, false) as CollisionShape3D
	if shape:
		shape.set_deferred("disabled", false)


## Карточки категории Room (S1). Ищем по группе: ObserveController живёт в сцене UI, а %-имена видны только внутри своей сцены
func _connect_observe() -> void:
	await get_tree().process_frame   # контроллер встаёт в группу в своём _ready
	var oc = get_tree().get_first_node_in_group(&"observe_controller")
	if oc:
		oc.observe_action.connect(_on_observe_action)
		oc.observe_entered.connect(func(): _set_observe_shadows(true))
		oc.observe_exited.connect(func(): _set_observe_shadows(false))
	else:
		push_warning("RoomBuilder: ObserveController не найден, кнопки категории Room не работают")


## Лампочка светится по GFX.lamp_changed, мелочи прячутся по QualityPreset.room_detail_lod
func _connect_gfx() -> void:
	await get_tree().process_frame
	GFX.lamp_changed.connect(_on_lamp_changed)
	GFX.quality_changed.connect(func(_id): _apply_detail())
	if _decor:
		_decor.set_lamp_glow(GFX.is_lamp_on())
	_apply_detail()


func _on_lamp_changed(on: bool) -> void:
	if _decor:
		_decor.set_lamp_glow(on)


func _apply_detail() -> void:
	if _decor == null:
		return
	var q: QualityPreset = GFX.get_quality()
	_decor.set_detail(q.room_detail_lod if q else 1)


## Тень стен, рамы и штор: рисунок окна на столе только в Observe
func _set_observe_shadows(on: bool) -> void:
	_walls_shadow_now = window_shadows_in_observe if on else walls_cast_shadow
	set_walls_cast_shadow(_walls_shadow_now)


## Пересобрать всё (после смены config). Стол тоже: при игре лучше rebuild_room()
func build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_mats.clear()
	_build_table()
	_build_room()

	if temp_light:
		var l := DirectionalLight3D.new()
		l.name = "TempSun"
		l.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
		l.shadow_enabled = true
		l.directional_shadow_max_distance = 700.0
		add_child(l)


## Пересобрать только комнату (смена варианта), стол с вагонами не трогаем
func rebuild_room() -> void:
	if visuals:
		remove_child(visuals)
		visuals.queue_free()
	_mats.clear()
	_build_room()


func _build_room() -> void:
	_walls.clear()
	ceiling = null
	_decor = null
	visuals = Node3D.new()
	visuals.name = "Room"
	add_child(visuals)
	if config.scene:
		visuals.add_child(config.scene.instantiate())
	else:
		_build_greybox()
	# Состояние переживает пересборку
	visuals.visible = _room_visible
	_apply_ceiling()
	set_walls_cast_shadow(_walls_shadow_now)
	_apply_detail()


## Смена варианта (слоты wall, bedding, curtains, posters, см. RoomDecor.VARIANTS)
func set_variant(slot: String, value: String) -> void:
	if config.variants.get(slot, "") == value:
		return
	config.variants[slot] = value
	rebuild_room()


func get_bounds() -> AABB:
	return config.bounds


func set_room_visible(on: bool) -> void:
	_room_visible = on
	if visuals:
		visuals.visible = on
	room_visible_changed.emit(on)


## Тень от стен (рисунок окна на столе). Потолок и небо в окне тень не отбрасывают никогда
func set_walls_cast_shadow(on: bool) -> void:
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for m in _walls:
		m.cast_shadow = mode
	_apply_ceiling()


## Потолок: нода всегда активна, а плита либо видна (и отбрасывает тень), либо скрыта, но отбрасывает тень, когда стены
## её отбрасывают (Observe). Без этого солнце заходило поверх стен и на стенах была видна верхняя граница тени
func _apply_ceiling() -> void:
	if ceiling == null or _ceiling_mesh == null:
		return
	ceiling.visible = true
	if _walls_shadow_now:
		_ceiling_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _ceiling_visible \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	else:
		_ceiling_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ceiling_mesh.visible = _ceiling_visible or _walls_shadow_now


func set_ceiling_visible(on: bool) -> void:
	_ceiling_visible = on
	_apply_ceiling()


## ⚡Сигнал из ObserveController
func _on_observe_action(_cat: StringName, _id: StringName, _pressed: bool) -> void:
	if _cat != &'room':
		return
	match _id:
		&'room_visible':
			set_room_visible(_pressed)
			return
		&'ceiling':
			set_ceiling_visible(_pressed)
			return
	# Варианты: wall_cream, bed_blue, curt_yellow, poster_trains
	if not _pressed:
		return
	var s := String(_id)
	for pair in [["wall_", "wall"], ["bed_", "bedding"], ["curt_", "curtains"], ["poster_", "posters"]]:
		if s.begins_with(pair[0]):
			set_variant(pair[1], s.trim_prefix(pair[0]))
			return


# ==========================================
# Подмакетник
# ==========================================

func _build_table() -> void:
	var c := config
	table = Node3D.new()
	table.name = "Table"
	add_child(table)

	var th := c.table_top_thickness
	# Верх стола = ground (слой 1): по нему бьют лучи тулов, underground_depth и опоры
	_box(table, "TableTop", Vector3(c.table_top.x, th, c.table_top.y), Vector3(0.0, -th * 0.5, 0.0),
			COL_TABLE, Global.active_layers(['ground']), 1, true)

	var leg_h := -c.floor_y - th
	if leg_h <= 0.0:
		return
	var lx := c.table_top.x * 0.5 - c.table_leg * 0.5 - 3.0
	var lz := c.table_top.y * 0.5 - c.table_leg * 0.5 - 3.0
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(table, "Leg", Vector3(c.table_leg, leg_h, c.table_leg),
					Vector3(sx * lx, c.floor_y + leg_h * 0.5, sz * lz),
					COL_TABLE_LEG, Global.active_layers(['room']), 1, true)


# ==========================================
# Greybox
# ==========================================

func _build_greybox() -> void:
	var c := config
	var t := c.wall_thickness
	var fy := c.floor_y
	var room_layer := Global.active_layers(['room'])
	var vis := _vis_layer()

	_decor = RoomDecor.new(c, vis, _lamp_height())
	_wall_col = _decor.wall_color()

	var floor_mi := _box(visuals, "Floor", Vector3(c.size.x + 2.0 * t, t, c.size.z + 2.0 * t), Vector3(0.0, fy - t * 0.5, 0.0),
			_decor.floor_color(), room_layer, vis, true)
	floor_mi.material_override = _parquet_mat(_decor.floor_color())

	_wall_z(-1.0, c.window)   # север: окно
	_wall_z(1.0, c.door)      # юг: дверь
	_wall_x(-1.0)
	_wall_x(1.0)
	_build_window_frame()
	_build_sky_card()
	_build_fake_ao()

	# Потолок: отдельной нодой, по умолчанию скрыт, без коллизии
	ceiling = Node3D.new()
	ceiling.name = "Ceiling"
	visuals.add_child(ceiling)
	_ceiling_mesh = _box(ceiling, "CeilingSlab", Vector3(c.size.x + 2.0 * t, t, c.size.z + 2.0 * t),
			Vector3(0.0, fy + c.size.y + t * 0.5, 0.0), COL_CEILING, 0, vis, false)
	_apply_ceiling()

	# Мебель: коллизия простой коробкой (слой room), внешний вид строит RoomDecor
	for p in PROPS:
		if p.get("collide", true):
			var sz: Vector3 = p.size
			var xz: Vector2 = p.xz
			_collider(visuals, p.name, sz, Vector3(xz.x, fy + sz.y * 0.5, xz.y), room_layer)

	_decor.build(visuals)
	for part in _decor.window_parts:
		_walls.append(part)


## Стена вдоль X на z = sgn * (hz + t/2) с необязательным проёмом {x, w, sill, h}
func _wall_z(sgn: float, op: Dictionary) -> void:
	var c := config
	var hx := c.size.x * 0.5
	var cz := sgn * (c.size.z * 0.5 + c.wall_thickness * 0.5)
	var x0 := -hx - c.wall_thickness
	var x1 := hx + c.wall_thickness
	var y0 := c.floor_y
	var y1 := c.floor_y + c.size.y
	var nm := "WallS" if sgn > 0.0 else "WallN"
	if op.is_empty():
		_slab(nm, x0, x1, y0, y1, cz)
		return
	var l: float = op.x - op.w * 0.5
	var r: float = op.x + op.w * 0.5
	var s0: float = y0 + op.sill
	var s1: float = s0 + op.h
	if op.sill > 0.0:
		_slab(nm + "_Below", x0, x1, y0, s0, cz)
	if s1 < y1:
		_slab(nm + "_Above", x0, x1, s1, y1, cz)
	_slab(nm + "_Left", x0, l, s0, s1, cz)
	_slab(nm + "_Right", r, x1, s0, s1, cz)


## Стена вдоль Z (между северной и южной, углы принадлежат им)
func _wall_x(sgn: float) -> void:
	var c := config
	var cx := sgn * (c.size.x * 0.5 + c.wall_thickness * 0.5)
	_walls.append(_box(visuals, "WallE" if sgn > 0.0 else "WallW",
			Vector3(c.wall_thickness, c.size.y, c.size.z), Vector3(cx, c.floor_y + c.size.y * 0.5, 0.0),
			_wall_col, Global.active_layers(['room']), _vis_layer(), walls_cast_shadow))


## Паркет процедурным шейдером (без текстур и геометрии): доски 12 × 100 см вразбежку, лёгкий разброс оттенка и тёмные швы.
## Швы гаснут на расстоянии (fwidth), чтобы не рябило. Рисунок считается по мировым координатам XZ
const PARQUET_SHADER := """
shader_type spatial;
uniform vec4 base_color : source_color = vec4(0.74, 0.58, 0.40, 1.0);
uniform float plank_w = 12.0;
uniform float plank_len = 100.0;
uniform float groove = 0.35;
uniform float tint = 0.07;
varying vec3 wp;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float row = floor(wp.z / plank_w);
	float off = hash(vec2(row, 3.0)) * plank_len;
	float colm = floor((wp.x + off) / plank_len);
	float fz = wp.z / plank_w - row;
	float fx = (wp.x + off) / plank_len - colm;
	float gap = min(min(fz, 1.0 - fz) * plank_w, min(fx, 1.0 - fx) * plank_len);
	float g = 1.0 - smoothstep(0.0, groove, gap);
	float fw = max(fwidth(wp.x), fwidth(wp.z));
	g *= 1.0 - smoothstep(0.3, 1.2, fw);
	float t = (hash(vec2(row, colm)) - 0.5) * 2.0 * tint;
	vec3 c = base_color.rgb * (1.0 + t);
	c = mix(c, c * 0.55, g * 0.85);
	ALBEDO = c;
	ROUGHNESS = 0.85;
}
"""
var _parquet_shader: Shader


func _parquet_mat(color: Color) -> ShaderMaterial:
	if _parquet_shader == null:
		_parquet_shader = Shader.new()
		_parquet_shader.code = PARQUET_SHADER
	var m := ShaderMaterial.new()
	m.shader = _parquet_shader
	m.set_shader_parameter("base_color", color)   # Color, а не Vector3: иначе source_color не переведёт sRGB в linear и пол выцветает
	return m


## Ложный AO (ATTN_14 §14.13): мягкое затемнение у плинтуса и в вертикальных углах. SSAO в Clean выключен и почти ничего
## не давал, а плоские стены без этого читаются как нарисованные. 9 полупрозрачных квадов без теней, на visual-слое комнаты.
## Стена с дверью (юг) пропущена: квад повис бы в проёме
const AO_COLOR := Color(0.05, 0.07, 0.16)
const AO_ALPHA := 0.55
const AO_FLOOR_H := 60.0      # высота полосы у пола, см
const AO_CORNER_W := 32.0     # ширина полосы в вертикальном углу, см
const AO_GAP := 0.3           # отступ от стены против z-fighting, см


func _build_fake_ao() -> void:
	var c := config
	var hx := c.size.x * 0.5
	var hz := c.size.z * 0.5
	var y0 := c.floor_y
	var h := c.size.y
	var root := Node3D.new()
	root.name = "FakeAO"
	visuals.add_child(root)
	var tex_floor := _ao_tex(true)
	var tex_corner := _ao_tex(false)
	# Полосы у пола: север, запад, восток (rot_y: куда смотрит нормаль квада внутрь комнаты)
	_ao_quad(root, "FloorN", Vector2(c.size.x, AO_FLOOR_H), Vector3(0.0, y0 + AO_FLOOR_H * 0.5, -hz + AO_GAP), 0.0, tex_floor, false)
	_ao_quad(root, "FloorW", Vector2(c.size.z, AO_FLOOR_H), Vector3(-hx + AO_GAP, y0 + AO_FLOOR_H * 0.5, 0.0), PI * 0.5, tex_floor, false)
	_ao_quad(root, "FloorE", Vector2(c.size.z, AO_FLOOR_H), Vector3(hx - AO_GAP, y0 + AO_FLOOR_H * 0.5, 0.0), -PI * 0.5, tex_floor, false)
	# Вертикальные углы: на северной стене и на боковых стенах у севера и юга (градиент от угла)
	var w := AO_CORNER_W
	_ao_quad(root, "CornerN_W", Vector2(w, h), Vector3(-hx + w * 0.5, y0 + h * 0.5, -hz + AO_GAP), 0.0, tex_corner, false)
	_ao_quad(root, "CornerN_E", Vector2(w, h), Vector3(hx - w * 0.5, y0 + h * 0.5, -hz + AO_GAP), 0.0, tex_corner, true)
	_ao_quad(root, "CornerW_N", Vector2(w, h), Vector3(-hx + AO_GAP, y0 + h * 0.5, -hz + w * 0.5), PI * 0.5, tex_corner, true)
	_ao_quad(root, "CornerW_S", Vector2(w, h), Vector3(-hx + AO_GAP, y0 + h * 0.5, hz - w * 0.5), PI * 0.5, tex_corner, false)
	_ao_quad(root, "CornerE_N", Vector2(w, h), Vector3(hx - AO_GAP, y0 + h * 0.5, -hz + w * 0.5), -PI * 0.5, tex_corner, false)
	_ao_quad(root, "CornerE_S", Vector2(w, h), Vector3(hx - AO_GAP, y0 + h * 0.5, hz - w * 0.5), -PI * 0.5, tex_corner, true)


## Градиентная текстура: тёмный край и прозрачный дальний конец. floor_strip: по вертикали (тёмный низ), иначе по горизонтали (тёмный левый край)
func _ao_tex(floor_strip: bool) -> GradientTexture2D:
	var g := Gradient.new()
	var dark := Color(AO_COLOR, AO_ALPHA)
	g.colors = PackedColorArray([dark, Color(AO_COLOR, AO_ALPHA * 0.35), Color(AO_COLOR, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 64
	t.height = 64
	t.fill_from = Vector2(0.0, 1.0) if floor_strip else Vector2(0.0, 0.0)
	t.fill_to = Vector2(0.0, 0.0) if floor_strip else Vector2(1.0, 0.0)
	return t


func _ao_quad(parent: Node, nm: String, size: Vector2, pos: Vector3, rot_y: float, tex: Texture2D, flip_h: bool) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = tex
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	if flip_h:
		m.uv1_scale = Vector3(-1.0, 1.0, 1.0)
		m.uv1_offset = Vector3(1.0, 0.0, 0.0)
	mi.material_override = m
	mi.name = nm
	mi.position = pos
	mi.rotation.y = rot_y
	mi.layers = _vis_layer()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## Кусок стены между x0..x1 и y0..y1 на z = cz
func _slab(nm: String, x0: float, x1: float, y0: float, y1: float, cz: float) -> void:
	if x1 - x0 < 0.01 or y1 - y0 < 0.01:
		return
	_walls.append(_box(visuals, nm, Vector3(x1 - x0, y1 - y0, config.wall_thickness),
			Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, cz), _wall_col,
			Global.active_layers(['room']), _vis_layer(), walls_cast_shadow))


# ==========================================
# Окно и небо
# ==========================================

## Рама с переплётом: отбрасывает тень на стол (в Observe)
func _build_window_frame() -> void:
	var c := config
	if c.window.is_empty():
		return
	var cz := -(c.size.z * 0.5 + c.wall_thickness * 0.5)
	var ox: float = c.window.x
	var ww: float = c.window.w
	var wh: float = c.window.h
	var s0: float = c.floor_y + c.window.sill
	var fb := 4.0
	var vis := _vis_layer()
	var col := Color(0.93, 0.93, 0.90)
	_walls.append(_box(visuals, "FrameTop", Vector3(ww, fb, 3.0), Vector3(ox, s0 + wh - fb * 0.5, cz), col, 0, vis, true))
	_walls.append(_box(visuals, "FrameBottom", Vector3(ww, fb, 3.0), Vector3(ox, s0 + fb * 0.5, cz), col, 0, vis, true))
	_walls.append(_box(visuals, "FrameLeft", Vector3(fb, wh, 3.0), Vector3(ox - ww * 0.5 + fb * 0.5, s0 + wh * 0.5, cz), col, 0, vis, true))
	_walls.append(_box(visuals, "FrameRight", Vector3(fb, wh, 3.0), Vector3(ox + ww * 0.5 - fb * 0.5, s0 + wh * 0.5, cz), col, 0, vis, true))
	_walls.append(_box(visuals, "MullionV", Vector3(3.0, wh, 2.0), Vector3(ox, s0 + wh * 0.5, cz), col, 0, vis, true))
	_walls.append(_box(visuals, "MullionH", Vector3(ww, 3.0, 2.0), Vector3(ox, s0 + wh * 0.55, cz), col, 0, vis, true))


## «Небо» за окном: плоскость с вертикальным градиентом, без освещения. Цвета меняет GFX (группа gfx_sky)
func _build_sky_card() -> void:
	var c := config
	if c.window.is_empty():
		return
	var g := Gradient.new()
	g.set_color(0, Color(0.45, 0.68, 0.95))
	g.set_color(1, Color(0.82, 0.92, 1.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	tex.width = 8
	tex.height = 128
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = tex
	var q := QuadMesh.new()
	q.size = Vector2(700.0, 350.0)
	var mi := MeshInstance3D.new()
	mi.name = "SkyCard"
	mi.mesh = q
	mi.material_override = m
	mi.layers = _vis_layer()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(c.window.x, c.floor_y + c.size.y * 0.35, -(c.size.z * 0.5) - 150.0)
	visuals.add_child(mi)
	mi.add_to_group(&"gfx_sky")


# ==========================================
# Хелперы
# ==========================================

## Только коллизия (без меша): внешний вид мебели строит RoomDecor
func _collider(parent: Node, nm: String, size: Vector3, center: Vector3, layers: int) -> void:
	var body := StaticBody3D.new()
	body.name = nm + "Collider"
	body.position = center
	body.collision_layer = layers
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	parent.add_child(body)


func _lamp_height() -> float:
	var l := get_tree().get_first_node_in_group(&"gfx_lamp") as Node3D
	return l.position.y if l else 120.0


func _vis_layer() -> int:
	return 1 << (Global.ROOM_VISUAL_LAYER - 1)


func _mat(color: Color) -> StandardMaterial3D:
	if not _mats.has(color):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.9
		_mats[color] = m
	return _mats[color]


## Коробка: меш + (если body_layers != 0) StaticBody3D на этих слоях. vis_layers: visual layers меша
func _box(parent: Node, nm: String, size: Vector3, center: Vector3, color: Color,
		body_layers: int, vis_layers: int, shadow: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color)
	mi.layers = vis_layers
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if body_layers == 0:
		mi.name = nm
		mi.position = center
		parent.add_child(mi)
		return mi
	var body := StaticBody3D.new()
	body.name = nm
	body.position = center
	body.collision_layer = body_layers
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	mi.name = "Mesh"
	body.add_child(mi)
	parent.add_child(body)
	return mi
