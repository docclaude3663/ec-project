class_name ConfirmDialog extends ModalWindow

# U10 (ATTN_17 §17.3.1): новый файл
## Вопрос «да или отмена». Использование: `if await confirm.ask("Заголовок", "Текст", "Да", "Отмена"): ...`
## Esc и «Отмена» дают false.

signal answered(ok: bool)

@onready var _message: Label = %Message
@onready var _ok: Button = %OkButton
@onready var _cancel: Button = %CancelButton


func _ready() -> void:
	visible = false
	_ok.pressed.connect(_answer.bind(true))
	_cancel.pressed.connect(_answer.bind(false))


func ask(title_text: String, message: String, ok_text: String = "Да", cancel_text: String = "Отмена") -> bool:
	_message.text = message
	_ok.text = ok_text
	_cancel.text = cancel_text
	open(title_text)
	_cancel.grab_focus()   # Enter по умолчанию отменяет: вопросы про потерю данных
	return await answered


func _answer(ok: bool) -> void:
	if not visible:
		return
	close()
	answered.emit(ok)


func _on_cancel() -> void:
	_answer(false)
