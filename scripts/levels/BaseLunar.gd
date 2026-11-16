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
@onready var terminal_prompt: Label = $TerminalPrompt
@onready var greenhouse: Node2D = $Greenhouse
@onready var communications: Node2D = $Communications
@onready var surface_camera: Camera2D = $Player/Camera2D
@onready var shelter_camera: Camera2D = $Refugio/Camera2D
@onready var shelter_arrival: Marker2D = $Refugio/Llegada

## Segundos de calendario por segundo de misión en la demo.
@export_range(0.1, 10.0, 0.01) var demo_solar_calendar_rate := 3.67

const DEVICE_TERMINAL := "BottomWallCommandCenter"
const DEVICE_GREENHOUSE := "Invernadero"
const DEVICE_WATER := "Tanque H₂O"
const DEVICE_OXYGEN := "Tanque O₂"
const DEVICE_COMMUNICATIONS := "Panel COM"
const REFUGE_ZONE := "Esclusa"
const DEVICE_SHELTER_EXIT := "Escalera del refugio"
const COMMAND_SHIELD_ZONE := "Zona de trabajo del centro de mando"
const SHIELD_COST := 30
const DEMO_TIME_MULTIPLIER := 2.0
const WATER_LEAK_SECOND := 25.0 * DEMO_TIME_MULTIPLIER
const DEVICE_LABELS := {
	DEVICE_TERMINAL: "Terminal",
	DEVICE_GREENHOUSE: "Greenhouse",
	DEVICE_WATER: "H₂O tank",
	DEVICE_OXYGEN: "O₂ tank",
	DEVICE_COMMUNICATIONS: "COM panel",
	REFUGE_ZONE: "Enter shelter",
	DEVICE_SHELTER_EXIT: "Return to base",
}

var _in_terminal_area: bool = false
var _nearby_devices: Dictionary = {}
var _prompt_device := ""
var _prompt_feedback := ""
var _shelter_return_position := Vector2.ZERO
const DEMO_DAY_SECONDS := 110.0 * DEMO_TIME_MULTIPLIER
var _water_repaired_today := false
var _water_restored := false
var _report_confirmed := false
var _trained_today := false
var _filter_pending := false
var _water_leak_triggered := false
var _day_succeeded := false
var _shield_deployed := false
var _in_command_shield_zone := false
@onready var _shield_panels: Node2D = $CommandShieldPanels
var _refuge_seconds := 0.0
var _last_day_remaining := 0.0

# ==============================================================================
# CICLO DE VIDA
# ==============================================================================

func _ready() -> void:
	# Godot agrega (DEBUG) al asignar Window.title en una ejecución de prueba.
	DisplayServer.window_set_title(str(ProjectSettings.get_setting("application/config/name")))
	if player and spawn_marker:
		player.global_position = spawn_marker.global_position
		
	# El punto de inicio está en el centro de mando, fuera del refugio blindado.
	player.leave_shelter_for_work_zone()
		
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
	get_viewport().size_changed.connect(_fit_shelter_camera)
	_fit_shelter_camera()
	_connect_life_support()
	communications.status_changed.connect(terminal_screen.update_communications)
	terminal_toggled.connect(communications.set_terminal_open)
	communications.report_result.connect(terminal_screen.show_life_support_result)
	communications.report_result.connect(func(message: String, _success: bool):
		if _prompt_device == DEVICE_COMMUNICATIONS:
			_prompt_feedback = message)
	terminal_screen.report_requested.connect(communications.send_report)
	communications.report_confirmed.connect(func():
		_report_confirmed = true
		_update_daily_objectives())
	communications.link_failed.connect(func():
		_report_confirmed = false
		_update_daily_objectives())
	communications.publish_status()
	terminal_screen.setup_command_shield(SHIELD_COST)
	terminal_screen.shield_requested.connect(_deploy_command_shield)
	EventManager.exit_restriction_changed.connect(_on_shield_restriction_changed)
	EventManager.solar_calendar_restarted.connect(_reset_command_shield)
	_update_command_shield()
	DayManager.set_day_duration(DEMO_DAY_SECONDS)
	EventManager.solar_calendar_rate = demo_solar_calendar_rate
	DayManager.auto_advance_next_day = false
	DayManager.start_day(1)


func _connect_life_support() -> void:
	var needs := player.needs_component
	if not needs:
		return
	terminal_screen.setup_life_support(AstronautNeeds.RECYCLE_ENERGY_COST)
	TaskManager.use_scheduled_filter_maintenance()
	terminal_screen.eat_requested.connect(needs.eat_ration)
	terminal_screen.drink_requested.connect(needs.drink_water)
	greenhouse.ration_harvested.connect(needs.harvest_ration)
	greenhouse.crop_status_changed.connect(terminal_screen.update_crop_status)
	terminal_screen.recycle_requested.connect(needs.recycle_water)
	needs.needs_updated.connect(terminal_screen.update_life_support_needs)
	needs.supplies_updated.connect(terminal_screen.update_life_support_supplies)
	needs.supply_action_finished.connect(terminal_screen.show_life_support_result)
	terminal_screen.train_requested.connect(TaskManager.advance_daily_training)
	terminal_toggled.connect(TaskManager.set_training_panel_open)
	TaskManager.task_completed.connect(_on_life_support_task_changed)
	TaskManager.new_task_assigned.connect(func(id: StringName, _urgent: bool):
		_on_life_support_task_changed(id))
	TaskManager.training_progress_changed.connect(terminal_screen.update_training_progress)
	TaskManager.training_result.connect(terminal_screen.show_life_support_result)
	terminal_screen.finish_day_requested.connect(DayManager.finish_day)
	terminal_screen.next_day_requested.connect(_start_next_day)
	terminal_screen.retry_day_requested.connect(_retry_demo)
	DayManager.day_survived.connect(_show_day_result)
	DayManager.day_started.connect(_reset_daily_objectives)
	DayManager.day_time_updated.connect(_schedule_water_leak)
	DayManager.day_time_updated.connect(_track_refuge_time)
	ResourceManager.resource_updated.connect(func(resource: StringName, _amount: float):
		if resource == ResourceManager.RES_OXYGEN:
			_update_oxygen_tank())
	ResourceManager.oxygen_leak_changed.connect(func(_active: bool): _update_oxygen_tank())
	needs.water_recycled.connect(func():
		if _water_repaired_today and not DayManager.is_day_completed:
			_water_restored = true
			_update_daily_objectives())
	_on_life_support_task_changed(TaskManager.TASK_CLEAN_O2_FILTERS)
	_update_oxygen_tank()
	TaskManager.enable_daily_training()
	needs.enable_mission_life_support(DEMO_TIME_MULTIPLIER)


func _on_life_support_task_changed(id: StringName) -> void:
	if id == TaskManager.TASK_CLEAN_O2_FILTERS:
		_filter_pending = TaskManager.is_task_active(id)
		if _water_leak_triggered and not _filter_pending:
			_water_repaired_today = true
		if _filter_pending and _prompt_device == DEVICE_WATER:
			_prompt_feedback = ""
		terminal_screen.update_filter_status(_filter_pending)
		_update_daily_objectives()
	elif id == TaskManager.TASK_DAILY_TRAINING and not TaskManager.is_task_active(id):
		_trained_today = true
		_update_daily_objectives()


func _schedule_water_leak(remaining: float, duration: float) -> void:
	if not _water_leak_triggered and duration - remaining >= WATER_LEAK_SECOND:
		_water_leak_triggered = true
		TaskManager.assign_water_tank_maintenance()


func _update_oxygen_tank() -> void:
	terminal_screen.update_oxygen_tank(ResourceManager.has_oxygen_leak(),
		ResourceManager.get_resource(ResourceManager.RES_OXYGEN))


func _reset_daily_objectives(day: int) -> void:
	_refuge_seconds = 0.0
	_last_day_remaining = DayManager.get_time_remaining()
	_water_leak_triggered = false
	_water_repaired_today = false
	_water_restored = false
	_report_confirmed = false
	_trained_today = false
	_day_succeeded = false
	terminal_screen.show_open_day(day)
	_update_daily_objectives()


func _track_refuge_time(remaining: float, _duration: float) -> void:
	if player.is_in_shelter() and EventManager.get_exit_restriction_name() == "SUSPENDIDA":
		_refuge_seconds += maxf(0.0, _last_day_remaining - remaining)
	_last_day_remaining = remaining


func _deploy_command_shield() -> void:
	if _shield_deployed or not _in_command_shield_zone or DayManager.is_day_completed:
		return
	if EventManager.get_exit_restriction_name() != "SUSPENDIDA":
		return
	if not EnergyEconomy.try_spend_energy(SHIELD_COST, "Motor de blindaje"):
		terminal_screen.show_life_support_result(EnergyEconomy.format_shortfall(SHIELD_COST), false)
		return
	_shield_deployed = true
	_update_command_shield()
	terminal_screen.show_life_support_result("Shielded zone · Command center", true)


func _on_shield_restriction_changed(state: String, _reason: String) -> void:
	if state != "SUSPENDIDA":
		_shield_deployed = false
	_update_command_shield()


func _reset_command_shield() -> void:
	_shield_deployed = false
	_update_command_shield()


func _update_command_shield() -> void:
	EventManager.set_player_in_shielded_work_zone(_shield_deployed and _in_command_shield_zone)
	_shield_panels.visible = _shield_deployed
	terminal_screen.update_command_shield(
		EventManager.get_exit_restriction_name() == "SUSPENDIDA", _shield_deployed)


func _update_daily_objectives() -> void:
	terminal_screen.update_daily_objectives(_water_restored, _water_repaired_today, _report_confirmed)


func _show_day_result() -> void:
	var pending := PackedStringArray()
	if not _water_restored:
		pending.append("recycle drinking water" if _water_repaired_today else
			"fix the H₂O tank and recycle water")
	if not _report_confirmed:
		pending.append("get a reply from Earth")
	_day_succeeded = pending.is_empty()
	terminal_screen.show_closed_day(pending, _refuge_seconds, _trained_today)
	open_terminal()


func _start_next_day() -> void:
	if DayManager.is_day_completed and _day_succeeded:
		DayManager.start_day(DayManager.current_day + 1, true)


func _retry_demo() -> void:
	if not DayManager.is_day_completed or _day_succeeded:
		return
	_water_leak_triggered = false
	TaskManager.reset_demo_tasks()
	_on_life_support_task_changed(TaskManager.TASK_CLEAN_O2_FILTERS)
	ResourceManager.reset_reserves()
	EnergyEconomy.reset_battery()
	BaseFSM.change_state(BaseFSM.BaseState.NORMAL)
	if player.is_in_shelter():
		_leave_underground()
	player.leave_shelter_for_work_zone()
	player.needs_component.reset_mission_supplies()
	greenhouse.reset_crop()
	close_terminal()
	player.global_position = spawn_marker.global_position
	player.reset_physics_interpolation()
	DayManager.start_day(1)


func _connect_terminal_events() -> void:
	if terminal_screen:
		terminal_screen.terminal_opened.connect(_on_terminal_opened)
		terminal_screen.terminal_closed.connect(_on_terminal_closed)


func _connect_interaction_areas() -> void:
	var zones = [
		["InvernaderoArea", "Invernadero"],
		["SoporteVitalArea", "Soporte Vital"],
		["ReactoresArea", "Módulo de Reactores"],
		["WaterTankArea", DEVICE_WATER],
		["OxygenTankArea", DEVICE_OXYGEN],
		["CommunicationsArea", DEVICE_COMMUNICATIONS],
		["AirlockArea", REFUGE_ZONE],
		["CommandShieldArea", COMMAND_SHIELD_ZONE],
		["BottomWallCommandCenter", "BottomWallCommandCenter"]
	]
	
	for zone_data in zones:
		var node_name: String = zone_data[0]
		var zone_name: String = zone_data[1]
		_connect_interaction_area(get_node("InteractionZones/" + node_name), zone_name)
	_connect_interaction_area($Refugio/Escalera, DEVICE_SHELTER_EXIT)


func _connect_interaction_area(area: Area2D, zone_name: String) -> void:
	area.body_entered.connect(func(body):
		if body == player:
			_handle_zone_entered(zone_name, area)
	)
	area.body_exited.connect(func(body):
		if body == player:
			_handle_zone_exited(zone_name)
	)


func _handle_zone_entered(zone_name: String, area: Area2D) -> void:
	if zone_name == COMMAND_SHIELD_ZONE:
		_in_command_shield_zone = true
		_update_command_shield()
	if DEVICE_LABELS.has(zone_name):
		_nearby_devices[zone_name] = area.get_node("CollisionShape2D")
	if zone_name == DEVICE_TERMINAL:
		_in_terminal_area = true
	player_entered_zone.emit(zone_name)


func _handle_zone_exited(zone_name: String) -> void:
	if zone_name == COMMAND_SHIELD_ZONE:
		_in_command_shield_zone = false
		_update_command_shield()
	_nearby_devices.erase(zone_name)
	if zone_name == DEVICE_TERMINAL:
		_in_terminal_area = false
		if terminal_screen and terminal_screen.is_open():
			terminal_screen.close()
	player_exited_zone.emit(zone_name)


func _nearest_device() -> String:
	var nearest := ""
	var distance := INF
	for device: String in _nearby_devices:
		if player.is_in_shelter() != (device == DEVICE_SHELTER_EXIT):
			continue
		var marker: Node2D = _nearby_devices[device]
		var candidate := player.global_position.distance_squared_to(marker.global_position)
		if candidate < distance:
			nearest = device
			distance = candidate
	return nearest


func _fit_shelter_camera() -> void:
	var viewport_size := get_viewport_rect().size
	var room_zoom := minf(viewport_size.x / 168.0, viewport_size.y / 114.0)
	shelter_camera.zoom = Vector2.ONE * maxf(1.0, floorf(room_zoom))


func _enter_underground() -> void:
	_shelter_return_position = player.global_position
	player.global_position = shelter_arrival.global_position
	player.reset_physics_interpolation()
	player.enter_shelter()
	$LunarSurface.hide()
	shelter_camera.enabled = true
	shelter_camera.make_current()
	shelter_camera.force_update_scroll()


func _leave_underground() -> void:
	player.global_position = _shelter_return_position
	player.reset_physics_interpolation()
	player.leave_shelter_for_work_zone()
	$LunarSurface.show()
	surface_camera.make_current()
	surface_camera.force_update_scroll()
	shelter_camera.enabled = false


func _process(_delta: float) -> void:
	var device := _nearest_device()
	if device != _prompt_device:
		_prompt_device = device
		_prompt_feedback = ""
	terminal_prompt.visible = not device.is_empty() and not terminal_screen.is_open()
	if terminal_prompt.visible:
		var marker: Node2D = _nearby_devices[device]
		var message := "E · %s" % DEVICE_LABELS[device]
		if device == DEVICE_WATER and _filter_pending:
			message = "⚠ E · Fix H₂O tank (%s)" % EnergyEconomy.format_sols(ceili(AstronautNeeds.FILTER_ENERGY_COST))
		elif device == DEVICE_OXYGEN and ResourceManager.has_oxygen_leak():
			message = "⚠ E · Fix O₂ tank (%s)" % EnergyEconomy.format_sols(ceili(AstronautNeeds.FILTER_ENERGY_COST))
		elif device == DEVICE_COMMUNICATIONS:
			message = communications.interaction_caption()
		elif device == DEVICE_GREENHOUSE:
			message = greenhouse.interaction_caption()
		if not _prompt_feedback.is_empty():
			message += "\n" + _prompt_feedback
		terminal_prompt.text = message
		terminal_prompt.global_position = marker.global_position + Vector2(-terminal_prompt.size.x * 0.5, -24)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or event.keycode != KEY_E:
		return
	if terminal_screen.is_open():
		close_terminal()
		get_viewport().set_input_as_handled()
		return
	var device := _nearest_device()
	match device:
		DEVICE_TERMINAL:
			open_terminal()
		DEVICE_GREENHOUSE:
			_prompt_feedback = greenhouse.interact(player.needs_component.take_drinking_water)
		DEVICE_WATER:
			_prompt_feedback = player.needs_component.repair_water_tank()
		DEVICE_OXYGEN:
			_prompt_feedback = player.needs_component.inspect_or_repair_oxygen_tank()
		DEVICE_COMMUNICATIONS:
			_prompt_feedback = communications.interact()
		REFUGE_ZONE:
			_enter_underground()
		DEVICE_SHELTER_EXIT:
			_leave_underground()
		_:
			return
	station_interacted.emit(device)
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
