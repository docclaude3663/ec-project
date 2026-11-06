class_name EnvironmentRoot extends Node3D

########################
## EnvironmentRoot. Владелец света и окружения (TDD §14.3).
########################
## Создает то, чего еще нет в сцене: WorldEnvironment, солнце, лампу над столом, ReflectionProbe комнаты,
## и ставит их в группы gfx_env / gfx_sun / gfx_lamp / gfx_probe, по которым их находит GFX.
## Если в главной сцене уже есть свой WorldEnvironment или DirectionalLight3D:
##  - либо добавьте их в соответствующую группу (Node > Groups), тогда EnvironmentRoot их не дублирует;
##  - либо удалите их, пусть создаст EnvironmentRoot.
## Угол и цвет солнца задает Time (S4), здесь только стартовые значения.

@export var room_center := Vector3(0.0, 75.0, 0.0)
@export var probe_size := Vector3(500.0, 260.0, 400.0)
@export var lamp_height := 120.0


func _ready() -> void:
	if Global.fast_debug:
		return   # свет и окружение остаются как в сцене
	_ensure_env()
	_ensure_sun()
	_ensure_lamp()
	_ensure_sky_fill()
	_ensure_probe()


func _has(group: StringName) -> bool:
	return get_tree().get_first_node_in_group(group) != null


func _ensure_env() -> void:
	if _has(&"gfx_env"):
		return
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment = e
	add_child(we)
	we.add_to_group(&"gfx_env")


func _ensure_sun() -> void:
	if _has(&"gfx_sun"):
		return
	var l := DirectionalLight3D.new()
	l.name = "Sun"
	l.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	l.light_energy = 1.0
	l.shadow_enabled = true
	l.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	l.directional_shadow_max_distance = 300.0
	add_child(l)
	l.add_to_group(&"gfx_sun")


## Лампа над столом. Мир в сантиметрах (1 м = 100 ед.), а затухание света Godot идёт как 1/расстояние (decay 1):
## на высоте 120 нужна энергия порядка 150-250, а не 6-12. До S4 временная: включает ее только Look с lamp_energy > 0
func _ensure_lamp() -> void:
	if _has(&"gfx_lamp"):
		return
	var l := SpotLight3D.new()
	l.name = "TableLamp"
	l.position = Vector3(0.0, lamp_height, 0.0)
	l.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	l.light_color = Color(1.0, 0.82, 0.6)
	l.light_energy = 0.0
	l.spot_range = 700.0
	l.shadow_bias = 0.6          # мир в см: стандартные 0,03–0,1 дают полосы (shadow acne) на стенах в ночных кадрах
	l.shadow_normal_bias = 3.0
	l.spot_angle = 65.0
	l.shadow_enabled = true
	l.visible = false
	add_child(l)
	l.add_to_group(&"gfx_lamp")


## Заполняющий направленный свет «небо»: рассеянный свет из окна. light_shadow_caster_mask без слоя оболочки комнаты (Global.ROOM_SHELL_LAYER):
## стены, потолок, шторы и подоконник не отбрасывают для него тень (освещает он всё), а пол, мебель и стол получают мягкие тени
## предметов вне пятна окна. light_cull_mask здесь не нужен: на тени он не влияет, а fps просаживает. Энергию, цвет и высоту задаёт GFX по Time и Look
func _ensure_sky_fill() -> void:
	if _has(&"gfx_sky_fill"):
		return
	var l := DirectionalLight3D.new()
	l.name = "SkyFill"
	l.rotation_degrees = Vector3(-65.0, 0.0, 0.0)
	l.light_color = Color(0.72, 0.84, 1.0)
	l.light_energy = 0.0
	l.shadow_caster_mask = 0xFFFFF & ~(1 << (Global.ROOM_SHELL_LAYER - 1))
	l.shadow_enabled = true
	l.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	l.directional_shadow_max_distance = 700.0
	l.visible = false
	add_child(l)
	l.add_to_group(&"gfx_sky_fill")


## Один статичный probe над столом: дешевый пластиковый блик. Обновляется один раз
func _ensure_probe() -> void:
	if _has(&"gfx_probe"):
		return
	var p := ReflectionProbe.new()
	p.name = "RoomProbe"
	p.position = room_center
	p.size = probe_size
	p.interior = true
	p.box_projection = true
	p.update_mode = ReflectionProbe.UPDATE_ONCE
	p.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	add_child(p)
	p.add_to_group(&"gfx_probe")
