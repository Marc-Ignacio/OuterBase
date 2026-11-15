extends Node2D

signal crop_status_changed(status: String)
signal ration_harvested()

const GROW_SECONDS := 6.0
const GROWN_POT := preload("res://assets/sprites/macetaconcosoverde.png")

@onready var _timer: Timer = $GrowthTimer
@onready var _progress: ProgressBar = $Progress
@onready var _ready_light: ColorRect = $ReadyLight
@onready var _status: Label = $Status
@onready var _bed_left: Sprite2D = $BedLeft
@onready var _bed_right: Sprite2D = $BedRight
@onready var _empty_pot := _bed_left.texture

var _harvest_ready := false


func _ready() -> void:
	_timer.timeout.connect(_on_crop_ready)
	reset_crop()


func interaction_caption() -> String:
	if TaskManager.is_task_active(TaskManager.TASK_WATER_PLANTS):
		return "E · Regar cultivos"
	if _harvest_ready:
		return "E · Cosechar"
	return "E · Sembrar" if _timer.is_stopped() else "Cultivo en curso"


func interact(use_drinking_water: Callable = Callable()) -> String:
	if TaskManager.is_task_active(TaskManager.TASK_WATER_PLANTS):
		if TaskManager.complete_task(TaskManager.TASK_WATER_PLANTS, use_drinking_water):
			return "Cultivos regados"
		return "Falta agua de riego\nRecicla agua en la Terminal y vuelve"
	if _harvest_ready:
		reset_crop()
		ration_harvested.emit()
		return "Cosecha · +1 ración"
	if not _timer.is_stopped():
		return "Cultivo en curso"
	var cost := AstronautNeeds.GROW_ENERGY_COST
	if not EnergyEconomy.try_spend_energy(cost, "Invernadero"):
		return EnergyEconomy.format_shortfall(cost)
	_timer.start(GROW_SECONDS)
	_progress.value = 0
	_progress.show()
	set_process(true)
	_set_status("Cultivando…")
	return "Cultivo iniciado"


func _process(_delta: float) -> void:
	_progress.value = 1.0 - _timer.time_left / GROW_SECONDS


func _on_crop_ready() -> void:
	_harvest_ready = true
	_bed_left.texture = GROWN_POT
	_bed_right.texture = GROWN_POT
	_ready_light.color = Color("#66f38a")
	_progress.hide()
	set_process(false)
	_set_status("Cosecha lista")


func reset_crop() -> void:
	_timer.stop()
	_harvest_ready = false
	_bed_left.texture = _empty_pot
	_bed_right.texture = _empty_pot
	_ready_light.color = Color("#335244")
	_progress.hide()
	set_process(false)
	_set_status("Ve al invernadero")


func _set_status(value: String) -> void:
	_status.text = "Sembrar · %s" % EnergyEconomy.format_sols(ceili(AstronautNeeds.GROW_ENERGY_COST)) if value == "Ve al invernadero" else value
	crop_status_changed.emit(value)
