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
		return "E · Water the plants"
	if _harvest_ready:
		return "E · Harvest"
	return "E · Plant seeds" if _timer.is_stopped() else "Plants growing"


func interact(use_drinking_water: Callable = Callable()) -> String:
	if TaskManager.is_task_active(TaskManager.TASK_WATER_PLANTS):
		if TaskManager.complete_task(TaskManager.TASK_WATER_PLANTS, use_drinking_water):
			return "Plants watered"
		return "Need water.\nRecycle water at the Terminal and come back."
	if _harvest_ready:
		reset_crop()
		ration_harvested.emit()
		return "Harvest · +1 meal"
	if not _timer.is_stopped():
		return "Plants growing"
	var cost := AstronautNeeds.GROW_ENERGY_COST
	if not EnergyEconomy.try_spend_energy(cost, "Invernadero"):
		return EnergyEconomy.format_shortfall(cost)
	_timer.start(GROW_SECONDS)
	_progress.value = 0
	_progress.show()
	set_process(true)
	_set_status("Cultivando…")
	return "Seeds planted"


func _process(_delta: float) -> void:
	_progress.value = 1.0 - _timer.time_left / GROW_SECONDS


func _on_crop_ready() -> void:
	_harvest_ready = true
	_bed_left.texture = GROWN_POT
	_bed_right.texture = GROWN_POT
	_ready_light.color = Color("#66f38a")
	_progress.hide()
	set_process(false)
	_set_status("Ready to harvest")


func reset_crop() -> void:
	_timer.stop()
	_harvest_ready = false
	_bed_left.texture = _empty_pot
	_bed_right.texture = _empty_pot
	_ready_light.color = Color("#335244")
	_progress.hide()
	set_process(false)
	_set_status("Go to the greenhouse")


func _set_status(value: String) -> void:
	_status.text = "Plant seeds · %s" % EnergyEconomy.format_sols(ceili(AstronautNeeds.GROW_ENERGY_COST)) if value == "Go to the greenhouse" else value
	crop_status_changed.emit(value)
