# res://scripts/utils/test_scene_runner.gd
extends Node

var survived_emitted: bool = false
var depleted_system: String = ""
var minigame_won: bool = false

func _ready() -> void:
	print("==================================================")
	print("--- TEST DE AUTOLOADS Y SISTEMAS CENTRALES ---")
	print("==================================================")
	
	# 1. Singletons globales
	print("[1] Verificando singletons globales:")
	print("    BaseFSM:         ", BaseFSM != null)
	print("    ResourceManager: ", ResourceManager != null)
	print("    EventManager:    ", EventManager != null)
	print("    TaskManager:     ", TaskManager != null)
	print("    DayManager:      ", DayManager != null)
	print("    EnergyEconomy:   ", EnergyEconomy != null)
	
	# 2. BaseFSM
	print("[2] Probando BaseFSM...")
	assert(BaseFSM.current_state == BaseFSM.BaseState.NORMAL)
	
	# 3. DayManager
	print("[3] Probando DayManager...")
	DayManager.day_survived.connect(self._on_day_survived)
	DayManager.start_day()
	DayManager.time_remaining = 0.2
	DayManager._process(0.3)
	assert(survived_emitted, "day_survived() debió ser emitida")
	
	# 4. EnergyEconomy
	print("[4] Probando EnergyEconomy...")
	EnergyEconomy.spend_energy(50.0, "Soporte Vital")
	EnergyEconomy.energy_depleted.connect(self._on_energy_depleted)
	var remaining = EnergyEconomy.get_current_watts()
	EnergyEconomy.spend_energy(remaining + 10.0, "Escudos de Radiación")
	assert(EnergyEconomy.get_current_watts() == 0.0)
	assert(depleted_system == "Escudos de Radiación")
	
	# 5. TreadmillMinigame
	print("[5] Probando TreadmillMinigame...")
	var minigame_scene = load("res://scenes/ui/TreadmillMinigame.tscn")
	var minigame = minigame_scene.instantiate()
	add_child(minigame)
	
	minigame.exercise_completed.connect(self._on_exercise_completed)
	
	# Simular pulsaciones alternadas para subir la barra a la zona verde
	print("    Simulando zancadas rítmicas alternadas [LEFT -> RIGHT -> LEFT]...")
	minigame._handle_footstep(minigame.FootStep.LEFT)
	minigame._handle_footstep(minigame.FootStep.RIGHT)
	minigame._handle_footstep(minigame.FootStep.LEFT)
	minigame._handle_footstep(minigame.FootStep.RIGHT)
	
	print("    Esfuerzo alcanzado: ", minigame.current_effort)
	assert(minigame.current_effort >= minigame.green_zone_min, "Debe alcanzar la zona verde")
	
	# Simular mantenimiento en zona verde hasta completar
	minigame.workout_progress = 95.0
	minigame._process(0.5)
	
	assert(minigame_won, "exercise_completed() debió ser emitida al alcanzar el 100%")
	
	print("==================================================")
	print(">>> TODOS LOS SISTEMAS Y MINIJUEGO FUNCIONAN 100% <<<")
	print("==================================================")
	get_tree().quit(0)


func _on_day_survived() -> void:
	survived_emitted = true


func _on_energy_depleted(sys: String) -> void:
	depleted_system = sys


func _on_exercise_completed() -> void:
	minigame_won = true
	print("    >>> SEÑAL exercise_completed() RECIBIDA EXITOSAMENTE <<<")
