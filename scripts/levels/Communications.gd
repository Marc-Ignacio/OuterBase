extends Node2D

signal status_changed(status: String, can_report: bool)
signal report_result(message: String, success: bool)

enum Link { ONLINE, UNSTABLE, OFFLINE }

const FLARE_EPISODE := "2024-10-03T12:08:00-FLR-001"
const STORM_EPISODE := "2024-10-09T05:05:00-SEP-001"
const FLARE_SECONDS := 5.0
const REPORT_SECONDS := 2.6

var _link := Link.ONLINE
var _flare_seen := false
var _storm_seen := false

@onready var _display: Label = $PanelStatus
@onready var _alert: PanelContainer = $HUD/Alert
@onready var _message: Label = $HUD/Alert/Message
@onready var _flare_timer: Timer = $FlareTimer
@onready var _report_timer: Timer = $ReportTimer
@onready var _feedback_timer: Timer = $FeedbackTimer
@onready var _report_message: Label = $HUD/ReportMessage


func _ready() -> void:
	EventManager.solar_milestone_reached.connect(_on_solar_milestone)
	EventManager.solar_calendar_restarted.connect(_reset)
	EventManager.exit_restriction_changed.connect(func(_state: String, _reason: String): _update_alert())
	EventManager.radiation_exposure_updated.connect(func(_flux: float, _dose: float, _rate: float): _update_alert())
	EventManager.shelter_order_issued.connect(func(_order: String, _safe: bool, _remaining: float): _update_alert())
	DayManager.day_paused.connect(func(paused: bool): _flare_timer.paused = paused)
	DayManager.day_started.connect(func(_day: int): _flare_timer.paused = false)
	_flare_timer.timeout.connect(func():
		if _link == Link.UNSTABLE:
			_set_link(Link.ONLINE))
	_report_timer.timeout.connect(_confirm_report)
	_feedback_timer.timeout.connect(_report_message.hide)
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
	if _link == Link.OFFLINE:
		return _show_report_message("Reinicia el equipo en el centro de mando", false)
	if _link == Link.UNSTABLE:
		return _show_report_message("Enlace inestable · Espera la recuperación", false)
	if not _report_timer.is_stopped():
		return "Enviando a Tierra…"
	_report_timer.start(REPORT_SECONDS)
	publish_status()
	_show_report_message("Enviando a Tierra…", true)
	_feedback_timer.stop()
	return "Enviando a Tierra…"


func _confirm_report() -> void:
	publish_status()
	_show_report_message("Confirmación recibida · Ida y vuelta simuladas", true)


func _show_report_message(message: String, success: bool) -> String:
	_report_message.text = message
	_report_message.show()
	_feedback_timer.start(3.0)
	report_result.emit(message, success)
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
	_report_timer.stop()
	_feedback_timer.stop()
	_report_message.hide()
	_flare_seen = false
	_storm_seen = false
	_set_link(Link.ONLINE)


func _set_link(value: Link) -> void:
	_link = value
	if value != Link.ONLINE and not _report_timer.is_stopped():
		_report_timer.stop()
		_show_report_message("Envío interrumpido · Inténtalo al recuperar el enlace", false)
	var status := "Operativas"
	var color := Color("#6aefa7")
	match value:
		Link.UNSTABLE:
			status = "Enlace inestable"
			color = Color("#ffda75")
		Link.OFFLINE:
			status = "Bloqueadas"
			color = Color("#ff927d")
	_display.text = "● COM" if value == Link.ONLINE else "⚠ COM"
	_display.modulate = color
	_update_alert()
	if value == Link.ONLINE and not _report_timer.is_stopped():
		status = "Enviando a Tierra…"
	status_changed.emit(status, value == Link.ONLINE and _report_timer.is_stopped())


func _update_alert() -> void:
	var warning := ""
	var color := Color("#ffda75")
	if _link == Link.UNSTABLE:
		warning = "Llamarada solar"
	elif _storm_seen and EventManager.get_exit_restriction_name() == "SUSPENDIDA":
		color = Color("#ff927d")
		var protection := "En refugio" if EventManager.is_player_sheltered() else (
			"Refugio · Baja desde el centro de mando")
		warning = "Tormenta de partículas · Busca protección\n%s · Dosis simulada: %.4f mSv/s" % [
			protection, EventManager.get_simulated_dose_rate()]
	elif _link == Link.OFFLINE:
		warning = "COM averiado · Reinicia el panel del centro de mando"
	_alert.visible = not warning.is_empty()
	if _message.text != warning:
		_message.text = warning
	_message.modulate = color
