extends Node2D

signal status_changed(status: String, can_report: bool)
signal report_result(message: String, success: bool)

enum Link { ONLINE, UNSTABLE, OFFLINE }

const FLARE_EPISODE := "2024-10-03T12:08:00-FLR-001"
const STORM_EPISODE := "2024-10-09T05:05:00-SEP-001"
const FLARE_SECONDS := 5.0

var _link := Link.ONLINE
var _flare_seen := false
var _storm_seen := false

@onready var _display: Label = $PanelStatus
@onready var _alert: PanelContainer = $HUD/Alert
@onready var _message: Label = $HUD/Alert/Message
@onready var _flare_timer: Timer = $FlareTimer


func _ready() -> void:
	EventManager.solar_milestone_reached.connect(_on_solar_milestone)
	EventManager.solar_calendar_restarted.connect(_reset)
	DayManager.day_paused.connect(func(paused: bool): _flare_timer.paused = paused)
	DayManager.day_started.connect(func(_day: int): _flare_timer.paused = false)
	_flare_timer.timeout.connect(func():
		if _link == Link.UNSTABLE:
			_set_link(Link.ONLINE))
	_set_link(Link.ONLINE)


func publish_status() -> void:
	_set_link(_link)


func interaction_caption() -> String:
	if _link == Link.OFFLINE:
		return "E · Reiniciar comunicaciones"
	return "E · Enviar reporte"


func interact() -> String:
	if _link == Link.OFFLINE:
		_set_link(Link.ONLINE)
		TaskManager.complete_task(TaskManager.TASK_REPAIR_COMMUNICATIONS)
		return "Comunicaciones restablecidas"
	return send_report()


func send_report() -> String:
	var message := "Reporte enviado"
	if _link == Link.OFFLINE:
		message = "Reinicia el equipo en el centro de mando"
	elif _link == Link.UNSTABLE:
		message = "Enlace inestable · Espera la recuperación"
	report_result.emit(message, _link == Link.ONLINE)
	return message


func _on_solar_milestone(hito: Dictionary) -> void:
	var episode: String = hito.get("id_episodio", "")
	var kind: String = hito.get("tipo_hito", "")
	if episode == FLARE_EPISODE and kind == "inicio" and not _flare_seen:
		_flare_seen = true
		_flare_timer.start(FLARE_SECONDS)
		_set_link(Link.UNSTABLE)
	elif episode == STORM_EPISODE and kind == "umbral" and hito.get("nivel") == "S3" and not _storm_seen:
		_storm_seen = true
		_flare_timer.stop()
		TaskManager.assign_routine_task(TaskManager.TASK_REPAIR_COMMUNICATIONS,
			"Reiniciar comunicaciones", "Pulsa E junto al panel COM de la pared superior.",
			"Centro de mando · Panel COM")
		_set_link(Link.OFFLINE)


func _reset() -> void:
	_flare_timer.stop()
	_flare_seen = false
	_storm_seen = false
	_set_link(Link.ONLINE)


func _set_link(value: Link) -> void:
	_link = value
	var status := "Operativas"
	var color := Color("#6aefa7")
	var warning := ""
	match value:
		Link.UNSTABLE:
			status = "Enlace inestable"
			warning = "Llamarada solar"
			color = Color("#ffda75")
		Link.OFFLINE:
			status = "Bloqueadas"
			warning = "Tormenta de partículas · Revisa comunicaciones"
			color = Color("#ff927d")
	_display.text = "● COM" if value == Link.ONLINE else "⚠ COM"
	_display.modulate = color
	_alert.visible = not warning.is_empty()
	_message.text = warning
	_message.modulate = color
	status_changed.emit(status, value == Link.ONLINE)
