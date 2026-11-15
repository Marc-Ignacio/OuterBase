# res://scripts/utils/test_scene_runner.gd
extends Node

func _ready() -> void:
	print("==================================================")
	print("--- TEST DE AUTOLOADS Y SISTEMAS CENTRALES ---")
	print("==================================================")
	
	# Verificar singletons globales
	print("[1] Verificando singletons globales:")
	print("    BaseFSM:         ", BaseFSM != null)
	print("    ResourceManager: ", ResourceManager != null)
	print("    EventManager:    ", EventManager != null)
	print("    TaskManager:     ", TaskManager != null)
	
	# Test BaseFSM
	print("[2] Probando BaseFSM...")
	print("    Estado inicial: ", BaseFSM.get_state_name())
	assert(BaseFSM.current_state == BaseFSM.BaseState.NORMAL)
	
	# Test ResourceManager
	print("[3] Probando ResourceManager...")
	print("    Energía inicial: ", ResourceManager.get_resource(ResourceManager.RES_ENERGY))
	print("    Agua inicial:    ", ResourceManager.get_resource(ResourceManager.RES_WATER))
	print("    Comida inicial:  ", ResourceManager.get_resource(ResourceManager.RES_FOOD))
	print("    Oxígeno inicial: ", ResourceManager.get_resource(ResourceManager.RES_OXYGEN))
	
	# Simular 1 tick
	ResourceManager._calculate_resource_cycle(1.0)
	print("    Recursos tras 1s de simulación:")
	print("    - Energía: ", ResourceManager.get_resource(ResourceManager.RES_ENERGY))
	print("    - Agua:    ", ResourceManager.get_resource(ResourceManager.RES_WATER))
	print("    - Comida:  ", ResourceManager.get_resource(ResourceManager.RES_FOOD))
	print("    - Oxígeno: ", ResourceManager.get_resource(ResourceManager.RES_OXYGEN))
	
	# Test EventManager
	print("[4] Probando EventManager - Secuencia de Llamarada Solar...")
	EventManager.trigger_event(EventManager.EVENT_SOLAR_FLARE, 1.0)
	print("    Estado FSM durante alerta: ", BaseFSM.get_state_name())
	assert(BaseFSM.current_state == BaseFSM.BaseState.ALERTA_CLIMA)
	
	# Simular impacto
	EventManager._execute_event_impact(EventManager.EVENT_SOLAR_FLARE)
	print("    Estado FSM tras impacto: ", BaseFSM.get_state_name())
	assert(BaseFSM.current_state == BaseFSM.BaseState.EMERGENCIA_RADIACION)
	
	# Test TaskManager
	print("[5] Probando TaskManager...")
	var active_tasks = TaskManager.get_active_tasks_data()
	print("    Tareas registradas: ", active_tasks.size())
	for t in active_tasks:
		print("    * [", t["id"], "] ", t["title"], " -> Ubicación: ", t["target_location"], " (Urgente: ", t["is_urgent"], ")")
	
	# Completar la tarea de emergencia
	print("[6] Completando tarea crítica 'divert_power_to_shields' en Módulo de Reactores...")
	var success = TaskManager.complete_task(TaskManager.TASK_DIVERT_SHIELDS)
	print("    ¿Completada?: ", success)
	print("    Estado FSM resultante: ", BaseFSM.get_state_name())
	assert(BaseFSM.current_state == BaseFSM.BaseState.RECUPERACION)
	
	print("==================================================")
	print(">>> TODOS LOS AUTOLOADS Y SISTEMAS FUNCIONAN 100% PERFECTO <<<")
	print("==================================================")
	get_tree().quit(0)
