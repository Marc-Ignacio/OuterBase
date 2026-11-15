# res://scripts/core/Player.gd
class_name PlayerController
extends CharacterBody2D

## Player.gd - Controlador Top-Down 2D del Astronauta
## Recibe señales desacopladas de AstronautNeeds para ajustar su velocidad dinámicamente.
## Si las necesidades básicas están bajas, el movimiento se percibe lento y pesado.

# ==============================================================================
# PARÁMETROS DE GAME DESIGN (@export)
# ==============================================================================

@export_group("Movimiento")
## Velocidad base del astronauta en píxeles por segundo cuando está 100% sano.
@export var base_speed: float = 180.0

# ==============================================================================
# REFERENCIAS Y ESTADO
# ==============================================================================

@export var needs_component: AstronautNeeds

var speed_multiplier: float = 1.0

# ==============================================================================
# CICLO DE VIDA
# ==============================================================================

func _ready() -> void:
	# Buscar el componente como hijo si no fue asignado en el Inspector
	if not needs_component:
		needs_component = get_node_or_null("AstronautNeeds")
	
	if needs_component:
		needs_component.speed_multiplier_changed.connect(_on_speed_multiplier_changed)
		speed_multiplier = needs_component.get_speed_multiplier()


func _physics_process(_delta: float) -> void:
	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	
	# La velocidad se escala con el multiplicador calculado por el estado biológico
	var current_speed: float = base_speed * speed_multiplier
	velocity = direction * current_speed
	
	move_and_slide()

# ==============================================================================
# RECEPCIÓN DE SEÑALES
# ==============================================================================

func _on_speed_multiplier_changed(new_multiplier: float) -> void:
	speed_multiplier = new_multiplier
