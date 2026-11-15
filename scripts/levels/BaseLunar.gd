# res://scripts/levels/BaseLunar.gd
class_name BaseLunar
extends Node2D

## BaseLunar.gd - Controlador de la Estación Lunar
## Administra la disposición de los módulos (Dormitorio/Soporte Vital, Pasillo/Esclusa,
## Centro de Mando/Reactores), las colisiones perimetrales que confinan al astronauta
## y los disparadores de interacción (Invernadero, Soporte Vital, Reactores, Esclusa
## y Terminal de Centro de Mando en BottomWallCommandCenter).

# ==============================================================================
# SEÑALES (DESACOPLADAS PARA TAREAS Y UI)
# ==============================================================================

signal station_interacted(station_name: String)
signal player_entered_zone(zone_name: String)
signal player_exited_zone(zone_name: String)
signal terminal_toggled(is_open: bool)

# ==============================================================================
# REFERENCIAS INTERNAS
# ==============================================================================

@onready var player: PlayerController = $Player
@onready var spawn_marker: Marker2D = $SpawnPoint
@onready var terminal_screen: TerminalScreen = $TerminalScreen
@onready var terminal_prompt: Control = $TerminalPrompt

var _in_terminal_area: bool = false

# ==============================================================================
# CICLO DE VIDA
# ==============================================================================

func _ready() -> void:
	if player and spawn_marker:
		player.global_position = spawn_marker.global_position
		
	# Asegurar que el astronauta inicie protegido en el refugio
	if has_node("/root/EventManager"):
		get_node("/root/EventManager").set_player_sheltered(true)
		
	# Sincronizar límites de cámara para seguir al jugador vertical y horizontalmente en la base
	if player and player.has_node("Camera2D"):
		var cam: Camera2D = player.get_node("Camera2D")
		cam.limit_left = -20
		cam.limit_top = -20
		cam.limit_right = 500
		cam.limit_bottom = 450
		cam.position_smoothing_enabled = false
		cam.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
		
	_connect_terminal_events()
	_connect_interaction_areas()
	_connect_life_support()


func _connect_life_support() -> void:
	var needs := player.needs_component
	if not needs:
		return
	terminal_screen.setup_life_support(AstronautNeeds.GROW_ENERGY_COST, AstronautNeeds.RECYCLE_ENERGY_COST)
	terminal_screen.eat_requested.connect(needs.eat_ration)
	terminal_screen.drink_requested.connect(needs.drink_water)
	terminal_screen.grow_requested.connect(needs.grow_ration)
	terminal_screen.recycle_requested.connect(needs.recycle_water)
	needs.needs_updated.connect(terminal_screen.update_life_support_needs)
	needs.supplies_updated.connect(terminal_screen.update_life_support_supplies)
	needs.supply_action_finished.connect(terminal_screen.show_life_support_result)
	needs.enable_mission_life_support()


func _connect_terminal_events() -> void:
	if terminal_screen:
		terminal_screen.terminal_opened.connect(_on_terminal_opened)
		terminal_screen.terminal_closed.connect(_on_terminal_closed)


func _connect_interaction_areas() -> void:
	var zones = [
		["InvernaderoArea", "Invernadero"],
		["SoporteVitalArea", "Soporte Vital"],
		["ReactoresArea", "Módulo de Reactores"],
		["AirlockArea", "Esclusa"],
		["BottomWallCommandCenter", "BottomWallCommandCenter"]
	]
	
	for zone_data in zones:
		var node_name: String = zone_data[0]
		var zone_name: String = zone_data[1]
		var area: Area2D = get_node_or_null("InteractionZones/" + node_name)
		if area:
			area.body_entered.connect(func(body):
				if body is PlayerController or body.name == "Player":
					_handle_zone_entered(zone_name)
			)
			area.body_exited.connect(func(body):
				if body is PlayerController or body.name == "Player":
					_handle_zone_exited(zone_name)
			)


func _handle_zone_entered(zone_name: String) -> void:
	if zone_name == "BottomWallCommandCenter":
		_in_terminal_area = true
		if terminal_prompt:
			terminal_prompt.visible = true
	player_entered_zone.emit(zone_name)


func _handle_zone_exited(zone_name: String) -> void:
	if zone_name == "BottomWallCommandCenter":
		_in_terminal_area = false
		if terminal_prompt:
			terminal_prompt.visible = false
		if terminal_screen and terminal_screen.is_open():
			terminal_screen.close()
	player_exited_zone.emit(zone_name)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			if _in_terminal_area:
				toggle_terminal()
				get_viewport().set_input_as_handled()
			elif terminal_screen and terminal_screen.is_open():
				terminal_screen.close()
				get_viewport().set_input_as_handled()


func _on_terminal_opened() -> void:
	if player:
		player.can_move = false
	terminal_toggled.emit(true)


func _on_terminal_closed() -> void:
	if player:
		player.can_move = true
	terminal_toggled.emit(false)

# ==============================================================================
# MÉTODOS PÚBLICOS DE TERMINAL
# ==============================================================================

## Abre la terminal del Centro de Mando
func open_terminal() -> void:
	if terminal_screen:
		terminal_screen.open()


## Cierra la terminal del Centro de Mando
func close_terminal() -> void:
	if terminal_screen:
		terminal_screen.close()


## Alterna la apertura/cierre de la terminal
func toggle_terminal() -> void:
	if terminal_screen:
		terminal_screen.toggle()


## Indica si la terminal está abierta actualmente
func is_terminal_open() -> bool:
	if terminal_screen:
		return terminal_screen.is_open()
	return false


## Retorna verdadero si el jugador está posicionado dentro del área de la terminal
func is_player_at_terminal() -> bool:
	return _in_terminal_area


## Retorna la posición del jugador en la base lunar
func get_player_position() -> Vector2:
	if player:
		return player.global_position
	return Vector2.ZERO
