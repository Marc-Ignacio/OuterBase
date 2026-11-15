# res://managers/TaskManager.gd
extends Node

## TaskManager.gd - Administrador de Tareas y Sistema de Tablet (Autoload: TaskManager)
## Gestiona tareas rutinarias (mantenimiento de base) y misiones críticas de emergencia.
## Diseñado para desacoplar completamente la lógica espacial de la UI de la Tablet (Programador 3)
## y de los disparadores físicos en el mapa top-down 2D.

# ==============================================================================
# SEÑALES (CONTRATO FORMAL CON LA UI / TABLET)
# ==============================================================================

## Emitida cuando se asigna una nueva tarea a la Tablet del jugador.
signal new_task_assigned(task_id: StringName, is_urgent: bool)

## Emitida cuando el jugador completa satisfactoriamente una tarea.
signal task_completed(task_id: StringName)

## Emitida cuando una tarea de emergencia expira sin ser completada.
signal task_failed(task_id: StringName)

## Emitida para actualizar el temporizador de una tarea urgente a la UI.
signal task_timer_updated(task_id: StringName, time_remaining: float, total_time: float)

# ==============================================================================
# DEFINICIÓN DE CLASE DE DATOS PARA TAREAS
# ==============================================================================

class BaseTask extends RefCounted:
	var id: StringName
	var title: String
	var description: String
	var target_location: String  ## Módulo físico donde el astronauta debe interactuar
	var is_urgent: bool = false
	var time_limit: float = 0.0  ## 0.0 = sin límite de tiempo
	var time_remaining: float = 0.0
	var water_cost: float = 0.0
	var energy_cost: float = 0.0
	
	func _init(p_id: StringName, p_title: String, p_desc: String, p_location: String, p_urgent: bool = false, p_time: float = 0.0) -> void:
		id = p_id
		title = p_title
		description = p_desc
		target_location = p_location
		is_urgent = p_urgent
		time_limit = p_time
		time_remaining = p_time
	
	func to_dict() -> Dictionary:
		return {
			"id": id,
			"title": title,
			"description": description,
			"target_location": target_location,
			"is_urgent": is_urgent,
			"time_limit": time_limit,
			"time_remaining": time_remaining
		}

# ==============================================================================
# IDS CONSTANTES DE TAREAS
# ==============================================================================

const TASK_WATER_PLANTS: StringName = &"water_plants"
const TASK_CLEAN_O2_FILTERS: StringName = &"clean_oxygen_filters"
const TASK_DIVERT_SHIELDS: StringName = &"divert_power_to_shields"

# ==============================================================================
# PARÁMETROS DE GAME DESIGN (@export)
# ==============================================================================

@export_group("Tiempo de Misiones de Emergencia")
## Segundos que tiene el jugador para desviar energía a escudos antes del fallo sistemático.
@export_range(10.0, 60.0, 1.0) var divert_shields_timeout: float = 25.0

@export_group("Costos y Recompensas de Mantenimiento")
## Agua extra requerida para regar el invernadero.
@export var water_plants_cost: float = 20.0
## Duración en segundos del bonus de producción del invernadero tras regarlo.
@export var greenhouse_bonus_duration: float = 30.0

## Duración en segundos del bonus de soporte vital tras limpiar filtros de O2.
@export var o2_filter_bonus_duration: float = 40.0

# ==============================================================================
# ALMACENAMIENTO INTERNO DE TAREAS ACTIVAS
# ==============================================================================

## Diccionario con pares { task_id (StringName): BaseTask }
var _active_tasks: Dictionary = {}

# Temporizadores de beneficios de mantenimiento
var _greenhouse_buff_time: float = 0.0
var _o2_buff_time: float = 0.0

# ==============================================================================
# CICLO DE VIDA
# ==============================================================================

func _ready() -> void:
	# Conectar con EventManager directamente
	_connect_to_event_manager()
	
	# Asignar tareas rutinarias iniciales para el jugador
	_create_initial_routine_tasks()


func _process(delta: float) -> void:
	var tasks_to_fail: Array[StringName] = []
	
	for task_id: StringName in _active_tasks.keys():
		var task: BaseTask = _active_tasks[task_id]
		if task.time_limit > 0.0:
			task.time_remaining -= delta
			task_timer_updated.emit(task.id, max(0.0, task.time_remaining), task.time_limit)
			
			if task.time_remaining <= 0.0:
				tasks_to_fail.append(task_id)
	
	for failed_id: StringName in tasks_to_fail:
		_handle_task_failure(failed_id)
		
	# Manejo de bonificadores temporales
	if _greenhouse_buff_time > 0.0:
		_greenhouse_buff_time -= delta
		if _greenhouse_buff_time <= 0.0 and has_node("/root/ResourceManager"):
			get_node("/root/ResourceManager").set_greenhouse_bonus(1.0)
			
	if _o2_buff_time > 0.0:
		_o2_buff_time -= delta
		if _o2_buff_time <= 0.0 and has_node("/root/ResourceManager"):
			get_node("/root/ResourceManager").set_life_support_bonus(1.0)

# ==============================================================================
# INTEGRACIÓN DESACOPLADA CON EVENTMANAGER Y BASEFSM
# ==============================================================================

func _connect_to_event_manager() -> void:
	if has_node("/root/EventManager"):
		var em: Node = get_node("/root/EventManager")
		if em.has_signal("event_started") and not em.is_connected("event_started", Callable(self, "_on_event_started")):
			em.connect("event_started", Callable(self, "_on_event_started"))


func _on_event_started(event_type: StringName) -> void:
	if event_type == &"solar_flare":
		assign_emergency_solar_flare_task()

# ==============================================================================
# CREACIÓN Y ASIGNACIÓN DE TAREAS
# ==============================================================================

func _create_initial_routine_tasks() -> void:
	assign_routine_task(
		TASK_WATER_PLANTS,
		"Regar Cultivos Hidropónicos",
		"Acude al Invernadero y suministra agua a los cultivos para maximizar la cosecha.",
		"Invernadero"
	)
	
	assign_routine_task(
		TASK_CLEAN_O2_FILTERS,
		"Limpiar Filtros de Oxígeno",
		"Limpia los filtros en el Módulo de Soporte Vital para mejorar la pureza del aire.",
		"Soporte Vital"
	)


## Asigna una tarea rutinaria (no urgente).
func assign_routine_task(id: StringName, title: String, description: String, location: String) -> void:
	if _active_tasks.has(id):
		return
		
	var task := BaseTask.new(id, title, description, location, false, 0.0)
	if id == TASK_WATER_PLANTS:
		task.water_cost = water_plants_cost
		
	_active_tasks[id] = task
	new_task_assigned.emit(id, false)


## Tarea Crítica activada ante Llamarada Solar: Desviar Energía a Escudos.
func assign_emergency_solar_flare_task() -> void:
	if _active_tasks.has(TASK_DIVERT_SHIELDS):
		return
		
	var task := BaseTask.new(
		TASK_DIVERT_SHIELDS,
		"EMERGENCIA: Desviar Energía a Escudos",
		"¡Radiación entrante! Corre al Módulo de Reactores y desvía la energía a los escudos magnéticos.",
		"Módulo de Reactores",
		true,
		divert_shields_timeout
	)
	
	_active_tasks[TASK_DIVERT_SHIELDS] = task
	new_task_assigned.emit(TASK_DIVERT_SHIELDS, true)

# ==============================================================================
# FINALIZACIÓN Y RESOLUCIÓN DE TAREAS
# ==============================================================================

## Invocado cuando el astronauta interactúa con la estación física correspondiente en el mapa.
## Retorna true si la tarea fue completada con éxito.
func complete_task(task_id: StringName) -> bool:
	if not _active_tasks.has(task_id):
		return false
	
	var task: BaseTask = _active_tasks[task_id]
	
	# Verificar si requiere costo de recursos
	if task.water_cost > 0.0 and has_node("/root/ResourceManager"):
		var rm: Node = get_node("/root/ResourceManager")
		if not rm.consume_resource(rm.RES_WATER, task.water_cost):
			return false
	
	# Efectos específicos al completar
	match task_id:
		TASK_WATER_PLANTS:
			_greenhouse_buff_time = greenhouse_bonus_duration
			if has_node("/root/ResourceManager"):
				get_node("/root/ResourceManager").set_greenhouse_bonus(1.3)
				
		TASK_CLEAN_O2_FILTERS:
			_o2_buff_time = o2_filter_bonus_duration
			if has_node("/root/ResourceManager"):
				get_node("/root/ResourceManager").set_life_support_bonus(1.25)
				
		TASK_DIVERT_SHIELDS:
			# Escudos levantados a tiempo -> mitigar y transicionar a RECUPERACION
			if has_node("/root/EventManager"):
				var em: Node = get_node("/root/EventManager")
				if em.has_method("end_active_event"):
					em.end_active_event()
			elif has_node("/root/BaseFSM"):
				var fsm: Node = get_node("/root/BaseFSM")
				if fsm.has_method("change_state"):
					fsm.change_state(BaseFSM.BaseState.RECUPERACION)
	
	_active_tasks.erase(task_id)
	task_completed.emit(task_id)
	return true


func _handle_task_failure(task_id: StringName) -> void:
	if not _active_tasks.has(task_id):
		return
	
	_active_tasks.erase(task_id)
	task_failed.emit(task_id)
	
	if task_id == TASK_DIVERT_SHIELDS:
		if has_node("/root/BaseFSM"):
			var fsm: Node = get_node("/root/BaseFSM")
			if fsm.has_method("change_state"):
				fsm.change_state(BaseFSM.BaseState.FALLO_SISTEMATICO)

# ==============================================================================
# MÉTODOS DE CONSULTA (PARA LA TABLET / UI DEL PROGRAMADOR 3)
# ==============================================================================

## Retorna un array con diccionarios de todas las tareas activas para renderizar en la Tablet.
func get_active_tasks_data() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for task: BaseTask in _active_tasks.values():
		list.append(task.to_dict())
	return list


## Verifica si una tarea específica está activa.
func is_task_active(task_id: StringName) -> bool:
	return _active_tasks.has(task_id)


## Obtiene la tarea por ID.
func get_task(task_id: StringName) -> BaseTask:
	return _active_tasks.get(task_id, null)
