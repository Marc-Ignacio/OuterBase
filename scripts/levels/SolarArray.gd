@tool
extends Node2D

@onready var _status: Label = $Status


func _ready() -> void:
	if not Engine.is_editor_hint():
		EnergyEconomy.energy_generated.connect(_on_energy_generated)


func _draw() -> void:
	for x in [-34, 3]:
		draw_rect(Rect2(x + 14, 19, 4, 5), Color("#514e55"))
		draw_rect(Rect2(x + 7, 23, 18, 2), Color("#77707b"))
		draw_rect(Rect2(x, 0, 32, 20), Color("#272f41"))
		draw_rect(Rect2(x, 0, 32, 2), Color("#a4aab9"))
		for column in range(5):
			for row in range(2):
				var cell_color := Color("#537fac") if (column + row) % 2 == 0 else Color("#41648f")
				draw_rect(Rect2(x + 2 + column * 6, 3 + row * 8, 5, 7), cell_color)


func _on_energy_generated(amount: float, source: String) -> void:
	if source == "Paneles solares" and floori(amount) > 0:
		_status.text = "Última recarga · +%s" % EnergyEconomy.format_sols(floori(amount))
