@tool
extends Node2D

const JOINT := Color("#3c3434")
const BEVEL := Color("#e1d6c6")
const SHADOW := Color("#675b58")
const PANEL_COLORS := [Color("#b2a49a"), Color("#a59991"), Color("#c0b0a3")]
const RIVET := Color("#776b67")


func _draw() -> void:
	# Extensiones superiores de las caras existentes, en píxeles de la escena.
	_draw_panels(Rect2(32, -2, 112, 12), 28, 0)
	_draw_panels(Rect2(329, -2, 112, 12), 28, 1)
	_draw_panels(Rect2(161, 43, 151, 11), 25, 2)
	_draw_panels(Rect2(190, 235, 123, 10), 25, 0)
	_draw_corner(441, 1)
	_draw_corner(32, -1)

	# Tramos de faldón entre aberturas, sin cruzar la entrada inferior.
	_draw_panels(Rect2(36, 193, 105, 7), 26, 1)
	_draw_panels(Rect2(332, 193, 53, 7), 26, 0)
	_draw_panels(Rect2(195, 340, 117, 7), 29, 2)
	_draw_panels(Rect2(369, 340, 69, 7), 23, 1)


func _draw_panels(bounds: Rect2, panel_width: int, variation: int) -> void:
	draw_rect(bounds, JOINT)
	var panel_number := variation
	for offset in range(1, int(bounds.size.x) - 1, panel_width):
		var span := minf(panel_width - 1, bounds.size.x - offset - 1)
		if span < 2.0:
			continue
		var origin := bounds.position + Vector2(offset, 0)
		draw_rect(Rect2(origin, Vector2(span, bounds.size.y)), PANEL_COLORS[panel_number % 3])
		draw_rect(Rect2(origin, Vector2(span, 2)), BEVEL)
		draw_rect(Rect2(origin + Vector2(0, bounds.size.y - 3), Vector2(span, 2)), SHADOW)
		if span >= 18 and bounds.size.y >= 10:
			draw_rect(Rect2(origin + Vector2(3, 4), Vector2(2, 2)), RIVET)
			draw_rect(Rect2(origin + Vector2(span - 5, 4), Vector2(2, 2)), RIVET)
			if panel_number % 4 == 1 and bounds.size.y >= 12:
				var grille := origin + Vector2(floorf(span / 2.0) - 4, bounds.size.y - 8)
				draw_rect(Rect2(grille, Vector2(8, 4)), SHADOW)
				for slot in range(1, 8, 2):
					draw_rect(Rect2(grille + Vector2(slot, 1), Vector2(1, 2)), JOINT)
		panel_number += 1


func _draw_corner(inner_x: int, direction: int) -> void:
	var edge := Vector2(inner_x, -2)
	var outer := Vector2(direction * 30, 30)
	draw_colored_polygon(PackedVector2Array([
		edge, edge + outer, edge + outer + Vector2(0, 11), edge + Vector2(0, 11),
	]), PANEL_COLORS[1])
	draw_line(edge, edge + outer, BEVEL, 2.0)
	draw_line(edge + Vector2(0, 9), edge + outer + Vector2(0, 9), SHADOW, 2.0)
