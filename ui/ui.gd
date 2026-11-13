extends CanvasLayer
## Корень интерфейса (ATTN_17 §17.3.1, U8).
## Слои: этот CanvasLayer с Control `HUD` внутри, `Windows` (layer 20), `Toasts` (layer 30).
## Фоторежим и look_lab скрывают только HUD: окна и тосты остаются.

@onready var hud: Control = %HUD


func set_hud_visible(on: bool) -> void:
	hud.visible = on


func is_hud_visible() -> bool:
	return hud.visible
