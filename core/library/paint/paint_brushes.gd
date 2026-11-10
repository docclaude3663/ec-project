class_name PaintBrushes extends RefCounted

# XX claude-library (новый файл)
########################
## PaintBrushes. Пресеты инструментов кисти (ATTN_22 §22.7.2.1, шаг C2.1)
########################
## Инструмент это набор параметров штампа, а не отдельный код: новый инструмент из списка автора добавляется записью.
## size: доля наибольшего габарита меша; hardness: доля радиуса, где штамп полный (0 мягкий, как у аэрографа);
## flow: плотность одного штампа; accumulate: пока кнопка удержана на месте, штамп повторяется каждый кадр (набор краски);
## erase: штамп стирает краску слоя вместо нанесения.

const ORDER := ["brush", "airbrush", "eraser"]
const PRESETS := {
	"brush": {"name": "Кисть", "size": 0.04, "hardness": 0.8, "flow": 1.0, "accumulate": false, "erase": false},
	"airbrush": {"name": "Аэрограф", "size": 0.09, "hardness": 0.0, "flow": 0.12, "accumulate": true, "erase": false},
	"eraser": {"name": "Ластик", "size": 0.06, "hardness": 0.5, "flow": 1.0, "accumulate": false, "erase": true},
}


static func preset(id: String) -> Dictionary:
	return (PRESETS.get(id, PRESETS["brush"]) as Dictionary).duplicate()
