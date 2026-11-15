# res://managers/EventManager.gd
extends Node

## EventManager.gd - Generador de Eventos Dinámicos y Clima Espacial (Autoload: EventManager)
## Administra eventos programados y aleatorios basados en pesos de probabilidad.
## Especializado en la secuencia de Llamarada Solar y preparado para conectarse
## con la API de la NASA desarrollada por el Programador 2.

# ==============================================================================
# SEÑALES (DESACOPLADAS PARA UI Y OTROS MANAGERS)
# ==============================================================================

## Emitida cuando se detecta un evento entrante con anticipación.
## event_data contiene: { "type": StringName, "title": String, "warning_duration": float, "severity": int }
signal event_warning_received(event_data: Dictionary)

## Emitida cuando el evento impacta o comienza activamente.
signal event_started(event_type: StringName)

## Emitida cuando el evento concluye o ha sido mitigado.
signal event_ended(event_type: StringName)

# ==============================================================================
# TIPOS DE EVENTOS CONSTANTES
# ==============================================================================

const EVENT_SOLAR_FLARE: StringName = &"solar_flare"
const EVENT_MICROMETEORITES: StringName = &"micrometeorites"
const EVENT_OXYGEN_LEAK: StringName = &"oxygen_leak"

# ==============================================================================
# PARÁMETROS DE GAME DESIGN (@export)
# ==============================================================================

@export_group("Generación Automática de Eventos")
## Determina si el sistema genera eventos periódicos automáticamente.
@export var auto_generate_events: bool = true

## Tiempo mínimo en segundos entre eventos.
@export_range(20.0, 300.0, 5.0) var min_time_between_events: float = 60.0

## Tiempo máximo en segundos entre eventos.
@export_range(40.0, 600.0, 5.0) var max_time_between_events: float = 120.0

@export_group("Pesos de Probabilidad")
## Peso de probabilidad para Llamarada Solar.
@export_range(1, 100, 1) var weight_solar_flare: int = 60
## Peso de probabilidad para Micrometeoritos.
@export_range(1, 100, 1) var weight_micrometeorites: int = 25
## Peso de probabilidad para Fuga de Oxígeno.
@export_range(1, 100, 1) var weight_oxygen_leak: int = 15

@export_group("Llamarada Solar (Solar Flare)")
## Segundos de preaviso antes de que la radiación impacte la base.
@export_range(5.0, 60.0, 1.0) var solar_flare_warning_duration: float = 15.0

## Duración en segundos de la fase activa de radiación si no es mitigada por tareas.
@export_range(10.0, 120.0, 2.0) var solar_flare_active_duration: float = 30.0

# ==============================================================================
# ESTADO INTERNO
# ==============================================================================

var _event_timer: Timer
var _active_event: StringName = &""
var _warning_active: bool = false
var _event_phase_timer: float = 0.0

# ==============================================================================
# CICLO DE VIDA
# ==============================================================================

func _ready() -> void:
	_event_timer = Timer.new()
	_event_timer.name = "EventSchedulerTimer"
	_event_timer.one_shot = true
	_event_timer.timeout.connect(_on_scheduler_timeout)
	add_child(_event_timer)
	
	if auto_generate_events:
		_schedule_next_event()


func _process(delta: float) -> void:
	if _warning_active:
		_event_phase_timer -= delta
		if _event_phase_timer <= 0.0:
			_execute_event_impact(_active_event)
	elif _active_event != &"":
		_event_phase_timer -= delta
		if _event_phase_timer <= 0.0:
			end_active_event()

# ==============================================================================
# PROGRAMACIÓN Y SELECCIÓN DE EVENTOS
# ==============================================================================

func _schedule_next_event() -> void:
	var next_time: float = randf_range(min_time_between_events, max_time_between_events)
	_event_timer.start(next_time)


func _on_scheduler_timeout() -> void:
	if _active_event != &"" or _warning_active:
		_schedule_next_event()
		return
	
	var chosen_event: StringName = _choose_random_event()
	trigger_event(chosen_event)


func _choose_random_event() -> StringName:
	var total_weight: int = weight_solar_flare + weight_micrometeorites + weight_oxygen_leak
	var roll: int = randi_range(1, total_weight)
	
	if roll <= weight_solar_flare:
		return EVENT_SOLAR_FLARE
	elif roll <= weight_solar_flare + weight_micrometeorites:
		return EVENT_MICROMETEORITES
	else:
		return EVENT_OXYGEN_LEAK

# ==============================================================================
# DETONACIÓN DE EVENTOS (PÚBLICO: ACCESIBLE PARA PROGRAMADOR 2 / NASA API)
# ==============================================================================

## Detona un evento específico. Puede ser invocado por el Programador 2 con datos de la NASA.
func trigger_event(event_type: StringName, custom_warning_time: float = -1.0) -> void:
	if _active_event != &"" or _warning_active:
		return
	
	_active_event = event_type
	var warning_time: float = custom_warning_time if custom_warning_time > 0.0 else solar_flare_warning_duration
	
	match event_type:
		EVENT_SOLAR_FLARE:
			_start_solar_flare_sequence(warning_time)
		EVENT_MICROMETEORITES:
			_start_generic_event(event_type, "Alerta: Lluvia de Micrometeoritos en trayectoria", 10.0, 20.0)
		EVENT_OXYGEN_LEAK:
			_start_generic_event(event_type, "Peligro: Despresurización y fuga en soporte vital", 8.0, 25.0)
		_:
			_start_generic_event(event_type, "Alerta espacial no clasificada", 10.0, 20.0)


func _start_solar_flare_sequence(warning_time: float) -> void:
	_warning_active = true
	_event_phase_timer = warning_time
	
	if has_node("/root/BaseFSM"):
		var fsm: Node = get_node("/root/BaseFSM")
		if fsm.has_method("change_state"):
			fsm.change_state(BaseFSM.BaseState.ALERTA_CLIMA)
	
	var warning_data: Dictionary = {
		"type": EVENT_SOLAR_FLARE,
		"title": "LLAMARADA SOLAR DETECTADA",
		"description": "Una eyección de masa coronal se aproxima. Se prevé interferencia y radiación crítica.",
		"warning_duration": warning_time,
		"severity": 3
	}
	
	event_warning_received.emit(warning_data)


func _start_generic_event(event_type: StringName, title: String, warning_time: float, active_time: float) -> void:
	_warning_active = true
	_event_phase_timer = warning_time
	
	if has_node("/root/BaseFSM"):
		var fsm: Node = get_node("/root/BaseFSM")
		if fsm.has_method("change_state"):
			fsm.change_state(BaseFSM.BaseState.ALERTA_CLIMA)
			
	var warning_data: Dictionary = {
		"type": event_type,
		"title": title,
		"warning_duration": warning_time,
		"active_duration": active_time,
		"severity": 2
	}
	
	event_warning_received.emit(warning_data)


func _execute_event_impact(event_type: StringName) -> void:
	_warning_active = false
	
	match event_type:
		EVENT_SOLAR_FLARE:
			_event_phase_timer = solar_flare_active_duration
			if has_node("/root/BaseFSM"):
				var fsm: Node = get_node("/root/BaseFSM")
				if fsm.has_method("change_state"):
					fsm.change_state(BaseFSM.BaseState.EMERGENCIA_RADIACION)
		_:
			_event_phase_timer = 20.0
	
	event_started.emit(event_type)


## Finaliza el evento activo y transiciona la base a fase de recuperación.
func end_active_event() -> void:
	if _active_event == &"":
		return
		
	var finished_event: StringName = _active_event
	_active_event = &""
	_warning_active = false
	_event_phase_timer = 0.0
	
	if has_node("/root/BaseFSM"):
		var fsm: Node = get_node("/root/BaseFSM")
		if fsm.has_method("change_state"):
			fsm.change_state(BaseFSM.BaseState.RECUPERACION)
	
	event_ended.emit(finished_event)
	
	if auto_generate_events:
		_schedule_next_event()


## Consulta el evento activo actual (o &"" si no hay ninguno).
func get_active_event() -> StringName:
	return _active_event


## Indica si actualmente hay una advertencia previa activa antes del impacto.
func is_warning_phase() -> bool:
	return _warning_active
