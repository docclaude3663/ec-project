class_name RoomAttic extends RoomDecor

########################
## Мансарда (RoomConfig.shape = &"attic"): оболочка, скос крыши и мебель из блоков (greybox).
########################
## Координаты комнаты в см: x с запада на восток, z с севера на юг, y от пола (_f добавляет уровень пола).
## Стены:
##  запад: окна с жалюзи и пейзажем, серая стена-акцент; диван, ковёр до середины комнаты, большой горшок у севера
##  север: фронтон с балками, телевизор по центру, стойка под ним
##  юг: дверь в нише глубиной 100 (восточнее центра), кирпичный простенок в четверть стены (западнее), стол с компьютером
##      и горшок в юго-западном углу
##  восток: крыша. Скос идёт от пола у стены (x = size.x / 2) до потолка на x = roof_top_x; потолок плоский только западнее.
##      У скоса верстак с полочками и стеллаж с моделями (их высоту ограничивает крыша)
## «Слева / справа» в описании автора = взгляд изнутри на стену (горшок справа от окон оказывается на севере, как на скринах).
## Свет: окна закрыты, только потолочные лампы дневного света (RoomConfig.lamps; источники ставит RoomBuilder, корпуса здесь).
## Все числа ниже правятся прямо здесь: это грубая прикидка, а не финальная расстановка.

const COL_PLASTER := Color(0.88, 0.86, 0.81)
const COL_WINDOW_WALL := Color(0.56, 0.55, 0.51)
const COL_BEAM := Color(0.78, 0.58, 0.34)
const COL_FRAME := Color(0.12, 0.13, 0.15)
const COL_FLOOR := Color(0.42, 0.31, 0.24)
const COL_SOFA := Color(0.30, 0.31, 0.34)
const COL_CARDBOARD := Color(0.72, 0.55, 0.35)

## Окна западной стены: центры по z, размер, высота низа от пола
const WIN_Z := [-62.0, 62.0]
const WIN_W := 104.0
const WIN_H := 150.0
const WIN_SILL := 65.0
## Ниша двери в южной стене (x0..x1 и глубина наружу), высота проёма
const NICHE_X0 := -20.0
const NICHE_X1 := 70.0
const NICHE_DEPTH := 100.0
const NICHE_H := 212.0
## Кирпичный простенок на южной стене: x0..x1, глубина выступа в комнату. Сверху его закрывает балка
const BRICK_X0 := -147.0
const BRICK_X1 := -20.0
const BRICK_D := 14.0
const BEAM_H := 18.0

## Кирпич процедурным шейдером (без текстур): ряды 7,5 см, кирпич 24 см вразбежку, швы гаснут вдали.
## Рисунок считается по мировым X и Y, поэтому годится для стен, перпендикулярных Z
const BRICK_SHADER := """
shader_type spatial;
uniform vec4 brick_a : source_color = vec4(0.60, 0.21, 0.14, 1.0);
uniform vec4 brick_b : source_color = vec4(0.80, 0.38, 0.24, 1.0);
uniform vec4 mortar : source_color = vec4(0.62, 0.58, 0.52, 1.0);
uniform float brick_w = 24.0;
uniform float brick_h = 7.5;
uniform float mortar_w = 0.9;
varying vec3 wp;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float row = floor(wp.y / brick_h);
	float off = mod(row, 2.0) * 0.5 * brick_w;
	float colm = floor((wp.x + off) / brick_w);
	float fy = wp.y / brick_h - row;
	float fx = (wp.x + off) / brick_w - colm;
	float gap = min(min(fy, 1.0 - fy) * brick_h, min(fx, 1.0 - fx) * brick_w);
	float m = 1.0 - smoothstep(0.0, mortar_w, gap);
	float fw = max(fwidth(wp.x), fwidth(wp.y));
	m *= 1.0 - smoothstep(0.4, 1.4, fw);
	vec3 c = mix(brick_a.rgb, brick_b.rgb, hash(vec2(row, colm)));
	c = mix(c, mortar.rgb, m);
	ALBEDO = c;
	ROUGHNESS = 0.95;
}
"""

## Части оболочки (стены, скос, ниша, рамы окон): RoomBuilder переключает им тень (в Observe стены отбрасывают тень)
var shell_parts: Array[MeshInstance3D] = []
## Материал пола комнаты: RoomBuilder передаёт его до build_shell, чтобы пол ниши совпал с полом комнаты
var floor_material: Material

var _hx := 260.0
var _hz := 210.0
var _h := 250.0
var _t := 10.0
var _top := 50.0
var _tube_mat: StandardMaterial3D
var _brick_shader: Shader


func _init(config: RoomConfig, vis_layer: int, lamp_height := 120.0) -> void:
	super(config, vis_layer, lamp_height)
	_hx = config.size.x * 0.5
	_hz = config.size.z * 0.5
	_h = config.size.y
	_t = config.wall_thickness
	_top = config.roof_top_x


func wall_color() -> Color:
	return COL_PLASTER


func floor_color() -> Color:
	return COL_FLOOR


## Высота скоса над полом на данном x: плоский потолок до roof_top_x, дальше спуск до нуля у восточной стены
func roof_height(x: float) -> float:
	if x <= _top:
		return _h
	return maxf(_h * (_hx - x) / (_hx - _top), 0.0)


# ==========================================
# Оболочка
# ==========================================

func build_shell(p: Node3D) -> void:
	_roof_slab(p)
	_wall_north(p)
	_wall_south(p)
	_wall_west(p)
	_door_niche(p)
	_brick_pier(p)
	_window_frames(p)
	_window_view(p)


## Скос крыши: плита вдоль всей комнаты, внутренняя грань от (roof_top_x, высота потолка) до пола у восточной стены
func _roof_slab(p: Node3D) -> void:
	var d := Vector2(_hx - _top, -_h)
	var ln := d.length()
	d /= ln
	var n_out := Vector2(-d.y, d.x) * _t   # наружу: вверх и на восток
	var a := Vector2(_top, _h)
	var b := Vector2(_hx, 0.0)
	_shell_prism(p, "Roof", [a, b, b + n_out, a + n_out], -_hz - _t, _hz + _t, COL_PLASTER)


## Северный фронтон: прямоугольник у запада, срезанный скосом справа
func _wall_north(p: Node3D) -> void:
	_shell_prism(p, "WallN", [Vector2(-_hx - _t, 0.0), Vector2(_hx, 0.0), Vector2(_top, _h), Vector2(-_hx - _t, _h)],
			-_hz - _t, -_hz, COL_PLASTER)


## Южная стена с проёмом ниши двери: слева (запад) глухая часть, над проёмом перемычка, справа (восток) клин под скосом
func _wall_south(p: Node3D) -> void:
	var z0 := _hz
	var z1 := _hz + _t
	var oh := minf(NICHE_H, roof_height(NICHE_X1) - 1.0)
	_shell_prism(p, "WallS_West", [Vector2(-_hx - _t, 0.0), Vector2(NICHE_X0, 0.0), Vector2(NICHE_X0, _h),
			Vector2(-_hx - _t, _h)], z0, z1, COL_PLASTER)
	_shell_prism(p, "WallS_Above", [Vector2(NICHE_X0, oh), Vector2(NICHE_X1, oh), Vector2(NICHE_X1, roof_height(NICHE_X1)),
			Vector2(_top, _h), Vector2(NICHE_X0, _h)], z0, z1, COL_PLASTER)
	_shell_prism(p, "WallS_East", [Vector2(NICHE_X1, 0.0), Vector2(_hx, 0.0), Vector2(NICHE_X1, roof_height(NICHE_X1))],
			z0, z1, COL_PLASTER)


## Западная стена с двумя окнами: низ, верх и простенки (серая стена-акцент)
func _wall_west(p: Node3D) -> void:
	var x0 := -_hx - _t
	var x1 := -_hx
	var top := WIN_SILL + WIN_H
	_shell_box(p, "WallW_Below", x0, x1, 0.0, WIN_SILL, -_hz, _hz, COL_WINDOW_WALL)
	_shell_box(p, "WallW_Above", x0, x1, top, _h, -_hz, _hz, COL_WINDOW_WALL)
	var edges: Array[float] = [-_hz]
	for zc in WIN_Z:
		var z: float = zc
		edges.append(z - WIN_W * 0.5)
		edges.append(z + WIN_W * 0.5)
	edges.append(_hz)
	# простенки: между краем стены и первым окном, между окнами, между вторым окном и краем
	for i in range(0, edges.size(), 2):
		_shell_box(p, "WallW_Pier%d" % int(i / 2.0), x0, x1, WIN_SILL, top, edges[i], edges[i + 1], COL_WINDOW_WALL)


## Ниша двери: коробка за южной стеной (боковые стены, потолок, пол, задняя стена) и дверь с наличником
func _door_niche(p: Node3D) -> void:
	var w := 8.0
	var z0 := _hz
	var z1 := _hz + NICHE_DEPTH
	_shell_vbox(p, "NicheWallW", NICHE_X0 - w, NICHE_X0, 0.0, NICHE_H + w, z0, z1 + w, COL_PLASTER)
	_shell_vbox(p, "NicheWallE", NICHE_X1, NICHE_X1 + w, 0.0, NICHE_H + w, z0, z1 + w, COL_PLASTER)
	_shell_vbox(p, "NicheCeiling", NICHE_X0 - w, NICHE_X1 + w, NICHE_H, NICHE_H + w, z0, z1 + w, COL_PLASTER)
	_shell_vbox(p, "NicheBack", NICHE_X0, NICHE_X1, 0.0, NICHE_H, z1, z1 + w, COL_PLASTER)
	var fl := _shell_vbox(p, "NicheFloor", NICHE_X0, NICHE_X1, -_t, 0.0, z0, z1, COL_FLOOR)
	if floor_material:
		fl.material_override = floor_material
	# Дверь на задней стене ниши: полотно, наличник, ручка
	var cx := (NICHE_X0 + NICHE_X1) * 0.5
	var dw := 80.0
	var dh := 200.0
	var zb := z1 - 2.0
	_box(p, Vector3(dw - 4.0, dh - 4.0, 3.0), _f(cx, (dh - 4.0) * 0.5, zb), PALETTE["white"], "paint", false)
	_box(p, Vector3(4.0, dh, 6.0), _f(cx - dw * 0.5, dh * 0.5, zb - 1.0), PALETTE["wood_light"], "wood", false)
	_box(p, Vector3(4.0, dh, 6.0), _f(cx + dw * 0.5, dh * 0.5, zb - 1.0), PALETTE["wood_light"], "wood", false)
	_box(p, Vector3(dw + 4.0, 4.0, 6.0), _f(cx, dh + 2.0, zb - 1.0), PALETTE["wood_light"], "wood", false)
	_box(p, Vector3(6.0, 1.5, 1.5), _f(cx + dw * 0.5 - 8.0, 100.0, zb - 3.0), PALETTE["grey"], "metal", false)


## Кирпичный простенок (четверть южной стены) от пола до балки под потолком
func _brick_pier(p: Node3D) -> void:
	var h := _h - BEAM_H
	var size := Vector3(BRICK_X1 - BRICK_X0, h, BRICK_D)
	var center := _f((BRICK_X0 + BRICK_X1) * 0.5, h * 0.5, _hz - BRICK_D * 0.5)
	var mi := _box(p, size, center, PALETTE["brown"], "paint", true)
	if _brick_shader == null:
		_brick_shader = Shader.new()
		_brick_shader.code = BRICK_SHADER
	var m := ShaderMaterial.new()
	m.shader = _brick_shader
	mi.material_override = m
	_collider(p, "BrickPier", size, center)
	# Балка над простенком, с небольшим выносом по сторонам
	var bw := BRICK_X1 - BRICK_X0 + 12.0
	_box(p, Vector3(bw, BEAM_H, BRICK_D + 4.0), _f((BRICK_X0 + BRICK_X1) * 0.5, _h - BEAM_H * 0.5, _hz - BRICK_D * 0.5 - 2.0),
			COL_BEAM, "wood", true)


## Рамы окон: тёмные, с перекладиной на 55% высоты (жалюзи закрывают верх)
func _window_frames(p: Node3D) -> void:
	var f := 5.0
	var depth := 8.0
	var x := -_hx - 2.0
	for zc in WIN_Z:
		var z: float = zc
		var cy := WIN_SILL + WIN_H * 0.5
		_shell_vis(_box(p, Vector3(depth, f, WIN_W), _f(x, WIN_SILL + WIN_H - f * 0.5, z), COL_FRAME, "metal", false))
		_shell_vis(_box(p, Vector3(depth, f, WIN_W), _f(x, WIN_SILL + f * 0.5, z), COL_FRAME, "metal", false))
		_shell_vis(_box(p, Vector3(depth, WIN_H, f), _f(x, cy, z - WIN_W * 0.5 + f * 0.5), COL_FRAME, "metal", false))
		_shell_vis(_box(p, Vector3(depth, WIN_H, f), _f(x, cy, z + WIN_W * 0.5 - f * 0.5), COL_FRAME, "metal", false))
		_shell_vis(_box(p, Vector3(depth - 2.0, 3.0, WIN_W), _f(x, WIN_SILL + WIN_H * 0.55, z), COL_FRAME, "metal", false))


## Вид из окон: небо (группа gfx_sky, цвета меняет GFX) и несколько крон деревьев. Это заглушка: потом фото-пейзаж
func _window_view(p: Node3D) -> void:
	var x_out := -_hx - _t
	var card := RoomDecor.make_sky_card(Vector2(420.0, 340.0), vis)
	card.position = _f(x_out - 170.0, 130.0, 0.0)
	card.rotation_degrees.y = 90.0   # лицом на восток, в комнату
	p.add_child(card)
	var greens := [Color(0.20, 0.38, 0.16), Color(0.30, 0.48, 0.20), Color(0.40, 0.55, 0.25), Color(0.55, 0.62, 0.28)]
	# [насколько дальше от стены, z, высота центра, радиус, цвет]
	var crowns := [[30, -110, 40, 45, 0], [45, -60, 80, 50, 1], [35, -20, 30, 55, 2], [55, 20, 95, 48, 0], [40, 65, 50, 52, 1],
			[30, 110, 85, 44, 2], [70, 0, 60, 70, 1], [60, -95, 110, 40, 3], [65, 90, 115, 40, 2]]
	var view := Node3D.new()
	view.name = "WindowView"
	p.add_child(view)
	for c in crowns:
		var sm := SphereMesh.new()
		var r: float = c[3]
		sm.radius = r
		sm.height = r * 2.0
		sm.radial_segments = 12
		sm.rings = 6
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = greens[c[4]]
		var mi := MeshInstance3D.new()
		mi.mesh = sm
		mi.material_override = mat
		mi.layers = vis
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = _f(x_out - float(c[0]), float(c[2]), float(c[1]))
		view.add_child(mi)


# ==========================================
# Мебель и декор
# ==========================================

func build(parent: Node3D) -> void:
	_beams(parent)
	_fixtures(parent)
	_sofa_and_rug(parent)
	_tv_wall(parent)
	_pc_corner(parent)
	_workbench(parent)
	_model_rack(parent)
	_plants(parent)
	tier2 = Node3D.new()
	tier2.name = "DecorT2"
	parent.add_child(tier2)
	_tier2_attic(tier2)
	tier3 = Node3D.new()
	tier3.name = "DecorT3"
	parent.add_child(tier3)
	_tier3_attic(tier3)


## Балки: ребра на скосе, прогон на стыке скоса и потолка, ферма на северной стене
func _beams(p: Node3D) -> void:
	var d := Vector2(_hx - _top, -_h)
	var ln := d.length()
	d /= ln
	var inward := Vector2(d.y, -d.x)   # в комнату: на запад и вниз
	var mid := (Vector2(_top, _h) + Vector2(_hx, 0.0)) * 0.5 + inward * 5.0
	var ang := rad_to_deg(atan2(d.y, d.x))
	for zr in [-150.0, -50.0, 50.0, 150.0]:
		_box(p, Vector3(ln, 10.0, 14.0), _f(mid.x, mid.y, zr), COL_BEAM, "wood", true, Vector3(0.0, 0.0, ang))
	# Прогон вдоль всей комнаты там, где скос встречает потолок
	_box(p, Vector3(16.0, 16.0, _hz * 2.0), _f(_top - 2.0, _h - 8.0, 0.0), COL_BEAM, "wood", true)
	# Ферма на северной стене: две стойки и перемычка (ТВ между ними)
	var zn := -_hz + 5.0
	_beam(p, Vector2(-170.0, 0.0), Vector2(-60.0, _h - 5.0), zn)
	_beam(p, Vector2(110.0, 40.0), Vector2(45.0, _h - 5.0), zn)
	_beam(p, Vector2(-114.0, 210.0), Vector2(83.0, 210.0), zn)


## Балка между двумя точками профиля XY (от пола), на заданной z. Сечение 12 × 10 см
func _beam(p: Node3D, a: Vector2, b: Vector2, z: float) -> void:
	var v := b - a
	_box(p, Vector3(v.length(), 12.0, 10.0), _f((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, z), COL_BEAM, "wood", true,
			Vector3(0.0, 0.0, rad_to_deg(atan2(v.y, v.x))))


## Корпуса светильников дневного света по RoomConfig.lamps: тёмный корпус и две светящиеся трубки
func _fixtures(p: Node3D) -> void:
	if _tube_mat == null:
		_tube_mat = StandardMaterial3D.new()
		_tube_mat.albedo_color = Color(0.96, 0.98, 1.0)
		_tube_mat.emission_enabled = true
		_tube_mat.emission = Color(0.92, 0.96, 1.0)
		_tube_mat.emission_energy_multiplier = 2.5
	for d in cfg.lamps:
		var ln: float = d.get("len", 120.0)
		var along_x: bool = String(d.get("axis", "z")) == "x"
		var y: float = d.get("y", _h - 6.0)
		var cx: float = d.x
		var cz: float = d.z
		var housing := Vector3(ln, 5.0, 14.0) if along_x else Vector3(14.0, 5.0, ln)
		_box(p, housing, _f(cx, y, cz), PALETTE["grey"], "metal", false)
		for s in [-3.2, 3.2]:
			var off: float = s
			var tube := Vector3(ln - 8.0, 1.8, 2.6) if along_x else Vector3(2.6, 1.8, ln - 8.0)
			var at := _f(cx, y - 3.0, cz + off) if along_x else _f(cx + off, y - 3.0, cz)
			var mi := _box(p, tube, at, Color.WHITE, "plastic", false)
			mi.material_override = _tube_mat


## Диван у окон (спинка к стене), ковёр с ромбами от дивана до середины комнаты
func _sofa_and_rug(p: Node3D) -> void:
	var sx := -_hx + 48.0
	_box(p, Vector3(92.0, 42.0, 230.0), _f(sx, 21.0, 0.0), COL_SOFA, "fabric")
	_box(p, Vector3(24.0, 48.0, 230.0), _f(sx - 34.0, 66.0, 0.0), COL_SOFA, "fabric")
	for sz in [-104.0, 104.0]:
		_box(p, Vector3(70.0, 22.0, 22.0), _f(sx + 7.0, 53.0, sz), COL_SOFA.darkened(0.1), "fabric")
	_box(p, Vector3(10.0, 30.0, 36.0), _f(sx - 17.0, 62.0, -85.0), Color(0.42, 0.43, 0.46), "fabric", true, Vector3(0.0, 8.0, -10.0))
	_box(p, Vector3(10.0, 30.0, 36.0), _f(sx - 17.0, 62.0, 70.0), Color(0.42, 0.43, 0.46), "fabric", true, Vector3(0.0, -8.0, -10.0))
	_collider(p, "Sofa", Vector3(92.0, 45.0, 230.0), _f(sx, 22.5, 0.0))

	# Ковёр: слои от края к центру, толщина растёт (без z-fighting), ромбы повёрнуты на 45°
	var cream := Color(0.86, 0.84, 0.78)
	var dark := Color(0.16, 0.16, 0.17)
	var rx := (-_hx + 94.0) * 0.5   # от переднего края дивана (-_hx + 94) до x = 0
	var layers := [[166.0, 230.0, 0.8, cream], [152.0, 216.0, 1.0, dark], [126.0, 190.0, 1.2, cream],
			[112.0, 176.0, 1.4, dark], [76.0, 140.0, 1.6, cream]]
	for l in layers:
		var h: float = l[2]
		_box(p, Vector3(l[0], h, l[1]), _f(rx, h * 0.5, 0.0), l[3], "fabric", false)
	_box(p, Vector3(64.0, 1.8, 64.0), _f(rx, 0.9, 0.0), dark, "fabric", false, Vector3(0.0, 45.0, 0.0))
	_box(p, Vector3(34.0, 2.0, 34.0), _f(rx, 1.0, 0.0), cream, "fabric", false, Vector3(0.0, 45.0, 0.0))


## Северная стена: ТВ по центру на стене, под ним низкая стойка
func _tv_wall(p: Node3D) -> void:
	var zw := -_hz
	_box(p, Vector3(125.0, 72.0, 4.0), _f(0.0, 128.0, zw + 2.5), PALETTE["dark"], "plastic", true)
	# Экран: градиент «закат», без освещения (яркое пятно в кадре)
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0.98, 0.55, 0.12), Color(0.80, 0.22, 0.10), Color(0.16, 0.06, 0.06)])
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	tex.width = 8
	tex.height = 64
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_texture = tex
	var screen := _box(p, Vector3(119.0, 66.0, 0.6), _f(0.0, 128.0, zw + 5.0), Color.WHITE, "plastic", false)
	screen.material_override = sm
	# Стойка: корпус тёмное дерево, белая столешница, ножки
	_box(p, Vector3(150.0, 38.0, 38.0), _f(0.0, 27.0, zw + 21.0), PALETTE["wood_dark"], "wood")
	_box(p, Vector3(154.0, 2.0, 40.0), _f(0.0, 47.0, zw + 21.0), PALETTE["white"], "paint")
	for sx in [-68.0, 68.0]:
		for sz in [-14.0, 14.0]:
			_box(p, Vector3(3.0, 8.0, 3.0), _f(sx, 4.0, zw + 21.0 + sz), PALETTE["wood_dark"], "wood", false)
	_collider(p, "TvStand", Vector3(154.0, 48.0, 40.0), _f(0.0, 24.0, zw + 21.0))


## Юго-западный угол: стол с компьютером и горшок
func _pc_corner(p: Node3D) -> void:
	var x0 := -222.0
	var x1 := -150.0
	var cx := (x0 + x1) * 0.5
	var zc := _hz - 30.0
	_box(p, Vector3(x1 - x0, 4.0, 60.0), _f(cx, 73.0, zc), PALETTE["wood_light"], "wood")
	_box(p, Vector3(3.0, 71.0, 56.0), _f(x0 + 1.5, 35.5, zc), PALETTE["wood_light"], "wood")
	_box(p, Vector3(3.0, 71.0, 56.0), _f(x1 - 1.5, 35.5, zc), PALETTE["wood_light"], "wood")
	_box(p, Vector3(x1 - x0 - 6.0, 30.0, 2.0), _f(cx, 52.0, zc + 28.0), PALETTE["wood_light"], "wood", false)
	# Монитор на ножке, клавиатура, системный блок под столом
	_box(p, Vector3(56.0, 33.0, 3.0), _f(cx, 94.0, zc + 16.0), PALETTE["dark"], "plastic")
	_box(p, Vector3(8.0, 14.0, 6.0), _f(cx, 82.0, zc + 16.0), PALETTE["dark"], "plastic", false)
	_box(p, Vector3(38.0, 1.5, 13.0), _f(cx, 75.8, zc - 2.0), PALETTE["dark"], "plastic", false)
	_box(p, Vector3(18.0, 40.0, 40.0), _f(x1 - 14.0, 24.0, zc + 6.0), PALETTE["dark"], "plastic")
	_collider(p, "PcDesk", Vector3(x1 - x0, 75.0, 60.0), _f(cx, 37.5, zc))


## Верстак у скоса (столешница 85 см, под крышей остаётся запас), над ним две полочки вдоль скоса.
## Ребро скоса свисает под плиту на ~15 см: восточный край стола (bx + 30) и полки проверены на зазор до ребра
func _workbench(p: Node3D) -> void:
	var bx := 144.0
	var bz := -115.0
	var blen := 150.0
	_box(p, Vector3(60.0, 4.0, blen), _f(bx, 83.0, bz), PALETTE["wood_light"], "wood")
	for sx in [-27.0, 27.0]:
		for sz in [-blen * 0.5 + 4.0, blen * 0.5 - 4.0]:
			_box(p, Vector3(5.0, 81.0, 5.0), _f(bx + sx, 40.5, bz + sz), PALETTE["dark"], "metal", false)
	_box(p, Vector3(56.0, 2.0, blen - 6.0), _f(bx, 25.0, bz), PALETTE["wood_dark"], "wood", false)
	# Полочки: у скоса высота потолка падает, поэтому верхняя уже и ближе к краю стола
	_box(p, Vector3(20.0, 3.0, 140.0), _f(130.0, 125.0, bz), PALETTE["wood_light"], "wood")
	_box(p, Vector3(12.0, 3.0, 140.0), _f(119.0, 141.0, bz), PALETTE["wood_light"], "wood")
	for dz in [-68.0, 68.0]:
		_box(p, Vector3(3.0, 57.0, 3.0), _f(115.5, 113.5, bz + dz), PALETTE["wood_dark"], "wood", false)
	_collider(p, "Workbench", Vector3(60.0, 85.0, blen), _f(bx, 42.5, bz))


## Низкий стеллаж-витрина с моделями у скоса: тёмная рамка и светлые полки (на скрине стекло, здесь без прозрачности). Модели в T2
func _model_rack(p: Node3D) -> void:
	var rx := 144.0
	var rz := 70.0
	for sx in [-13.5, 13.5]:
		for sz in [-58.5, 58.5]:
			_box(p, Vector3(3.0, 100.0, 3.0), _f(rx + sx, 50.0, rz + sz), PALETTE["dark"], "metal")
	for y in [1.5, 35.0, 68.0, 98.5]:
		_box(p, Vector3(30.0, 3.0, 120.0), _f(rx, y, rz), PALETTE["wood_light"], "wood")
	_collider(p, "ModelRack", Vector3(30.0, 100.0, 120.0), _f(rx, 50.0, rz))


## Большой горшок с деревом у северного края окон (T1), мелкий горшок в юго-западном углу (T2)
func _plants(p: Node3D) -> void:
	var px := -_hx + 28.0
	var pz := -150.0
	_cyl(p, 17.0, 36.0, _f(px, 18.0, pz), PALETTE["white"], "paint")
	_cyl(p, 2.2, 90.0, _f(px, 80.0, pz), PALETTE["brown"], "wood", true)
	var leaf := Color(0.16, 0.42, 0.20)
	for b in [[0.0, 150.0, 0.0, 26.0], [14.0, 128.0, 8.0, 22.0], [-14.0, 118.0, -6.0, 22.0], [6.0, 170.0, -8.0, 20.0],
			[-10.0, 140.0, 14.0, 20.0]]:
		_ball(p, b[3], _f(px + float(b[0]), float(b[1]), pz + float(b[2])), leaf, "fabric", true, Vector3(1.0, 0.8, 1.0))
	_collider(p, "FigPot", Vector3(36.0, 36.0, 36.0), _f(px, 18.0, pz))


func _tier2_attic(p: Node3D) -> void:
	# Жалюзи: рейки и верхний короб на каждом окне, опущены на верхние 70 см
	var slat := Color(0.86, 0.85, 0.82)
	var x := -_hx + 3.0
	for zc in WIN_Z:
		var z: float = zc
		var top := WIN_SILL + WIN_H
		_box(p, Vector3(5.0, 5.0, WIN_W + 4.0), _f(x, top + 2.0, z), slat, "paint", false)
		for i in 14:
			_box(p, Vector3(2.5, 1.0, WIN_W), _f(x, top - 4.0 - i * 5.0, z), slat, "paint", false)

	# Верстак: ящик с инструментом, банки на полке, лампа
	_box(p, Vector3(14.0, 8.0, 24.0), _f(146.0, 87.0, -165.0), PALETTE["red"], "metal")
	_box(p, Vector3(24.0, 1.5, 24.0), _f(154.0, 85.8, -90.0), PALETTE["green"], "plastic", false)
	for i in 5:
		_cyl(p, 4.0, 10.0, _f(126.0, 131.0, -178.0 + i * 28.0), PALETTE[["red", "blue", "yellow", "orange", "green"][i]], "paint")
	_box(p, Vector3(8.0, 4.0, 40.0), _f(119.0, 144.5, -115.0), PALETTE["grey"], "plastic")

	# Модели на полках стеллажа: коробки и фигурки разных цветов (детерминированно)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var keys := ["red", "blue", "yellow", "green", "orange", "purple", "white", "sky"]
	for y in [3.0, 36.5, 69.5]:
		var z := 16.0
		while z < 124.0:
			var w := rng.randf_range(9.0, 16.0)
			var hh := rng.randf_range(5.0, 12.0)
			_box(p, Vector3(rng.randf_range(12.0, 20.0), hh, w), _f(144.0, y + hh * 0.5, z + w * 0.5), PALETTE[keys[rng.randi() % keys.size()]], "plastic")
			z += w + 2.0

	# Картонные коробки у скоса на юге (высота ниже потолка у скоса)
	_box(p, Vector3(42.0, 30.0, 34.0), _f(150.0, 15.0, 165.0), COL_CARDBOARD, "paper")
	_box(p, Vector3(36.0, 24.0, 30.0), _f(152.0, 42.0, 163.0), COL_CARDBOARD.darkened(0.08), "paper", true, Vector3(0.0, 12.0, 0.0))
	_box(p, Vector3(40.0, 28.0, 32.0), _f(185.0, 14.0, 130.0), COL_CARDBOARD.darkened(0.04), "paper", true, Vector3(0.0, -8.0, 0.0))

	# Стул у компьютера
	var cx := -186.0
	_box(p, Vector3(40.0, 4.0, 40.0), _f(cx, 45.0, 138.0), PALETTE["dark"], "fabric")
	_box(p, Vector3(38.0, 40.0, 4.0), _f(cx, 68.0, 120.0), PALETTE["dark"], "fabric")
	_cyl(p, 2.0, 43.0, _f(cx, 22.0, 138.0), PALETTE["grey"], "metal")
	_cyl(p, 18.0, 3.0, _f(cx, 2.0, 138.0), PALETTE["grey"], "metal", false)

	# Мелкий горшок в юго-западном углу: «змеиный» цветок из тонких листьев
	var gx := -_hx + 16.0
	var gz := _hz - 16.0
	_cyl(p, 13.0, 28.0, _f(gx, 14.0, gz), PALETTE["white"], "paint")
	for i in 6:
		var a := float(i) * 1.05
		_box(p, Vector3(2.0, 62.0, 5.0), _f(gx + cos(a) * 4.0, 55.0, gz + sin(a) * 4.0), Color(0.18, 0.40, 0.20), "fabric", true,
				Vector3(sin(a) * 10.0, 0.0, cos(a) * 10.0))


func _tier3_attic(p: Node3D) -> void:
	# Кружка и тетрадь на столе компьютера, банка краски у верстака
	_small(_cyl(p, 3.0, 8.0, _f(-170.0, 79.0, _hz - 20.0), PALETTE["white"], "plastic"))
	_small(_box(p, Vector3(16.0, 1.2, 22.0), _f(-200.0, 75.6, _hz - 42.0), PALETTE["blue"], "paper"))
	_small(_cyl(p, 9.0, 18.0, _f(175.0, 9.0, -30.0), PALETTE["white"], "paint"))
	_small(_cyl(p, 9.0, 18.0, _f(176.0, 27.0, -30.0), PALETTE["white"], "paint"))


# ==========================================
# Примитивы оболочки
# ==========================================

## Только коллизия на слое room (без меша)
func _collider(parent: Node, nm: String, size: Vector3, center: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = nm + "Collider"
	body.position = center
	body.collision_layer = Global.active_layers(['room'])
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	parent.add_child(body)


## Часть оболочки: коробка по границам x0..x1, y0..y1 (от пола), z0..z1. С коллизией
func _shell_box(p: Node3D, nm: String, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, color: Color) -> void:
	_shell_prism(p, nm, [Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)], z0, z1, color)


## То же без коллизии (ниша, рамы): возвращает меш
func _shell_vbox(p: Node3D, nm: String, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, color: Color) -> MeshInstance3D:
	var mi := _box(p, Vector3(x1 - x0, y1 - y0, z1 - z0), _f((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5), color, "paint", false)
	mi.name = nm
	return _shell_vis(mi)


## Меш переводится на visual layer оболочки (SkyFill его не видит) и попадает в список частей с переключаемой тенью
func _shell_vis(mi: MeshInstance3D) -> MeshInstance3D:
	mi.layers = 1 << (Global.ROOM_SHELL_LAYER - 1)
	shell_parts.append(mi)
	return mi


func _shell_prism(p: Node3D, nm: String, pts: Array, z0: float, z1: float, color: Color) -> void:
	var mi := _prism(p, nm, pts, z0, z1, color, "paint", Global.active_layers(['room']))
	_shell_vis(mi)


## Призма: выпуклый многоугольник в плоскости XY (x, y от пола), выдавленный по z от z0 до z1.
## body_layers != 0: StaticBody3D с выпуклой коллизией. Вершины сразу в координатах комнаты
func _prism(parent: Node, nm: String, pts: Array, z0: float, z1: float, color: Color, role := "paint",
		body_layers := 0) -> MeshInstance3D:
	var poly := PackedVector2Array()
	for q in pts:
		poly.append(q)
	var area := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		area += a.x * b.y - b.x * a.y
	if area < 0.0:
		poly.reverse()   # против часовой при взгляде с +Z
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := poly.size()
	for i in range(1, n - 1):
		_tri(st, _v3(poly[0], z1), _v3(poly[i], z1), _v3(poly[i + 1], z1), Vector3(0.0, 0.0, 1.0))
		_tri(st, _v3(poly[0], z0), _v3(poly[i], z0), _v3(poly[i + 1], z0), Vector3(0.0, 0.0, -1.0))
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var e := b - a
		if e.length() < 0.001:
			continue
		var nn := Vector3(e.y, -e.x, 0.0).normalized()   # наружу для обхода против часовой
		_tri(st, _v3(a, z0), _v3(b, z0), _v3(b, z1), nn)
		_tri(st, _v3(a, z0), _v3(b, z1), _v3(a, z1), nn)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _m(role, color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if body_layers == 0:
		mi.name = nm
		parent.add_child(mi)
		return mi
	var body := StaticBody3D.new()
	body.name = nm
	body.collision_layer = body_layers
	body.collision_mask = 0
	var shape := ConvexPolygonShape3D.new()
	var pts3 := PackedVector3Array()
	for q in poly:
		pts3.append(_v3(q, z0))
		pts3.append(_v3(q, z1))
	shape.points = pts3
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	mi.name = "Mesh"
	body.add_child(mi)
	parent.add_child(body)
	return mi


func _v3(q: Vector2, z: float) -> Vector3:
	return Vector3(q.x, fy + q.y, z)


## Треугольник с нужной нормалью n. Godot считает лицевой стороной обход по часовой стрелке,
## а нормаль по правилу правой руки у такого треугольника смотрит от наблюдателя: при совпадении с n меняем порядок
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
	st.set_normal(n)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
