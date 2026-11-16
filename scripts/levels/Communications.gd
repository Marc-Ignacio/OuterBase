extends Node2D

signal status_changed(status: String, can_report: bool)
signal report_result(message: String, success: bool)
signal report_confirmed()
signal link_failed()

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
	DayManager.day_started.connect(_on_day_started)
	_flare_timer.timeout.connect(func():
		if _link == Link.UNSTABLE:
			_set_link(Link.ONLINE))
	_report_timer.timeout.connect(_confirm_report)
	_feedback_timer.timeout.connect(_report_message.hide)
	_set_link(Link.ONLINE)


func publish_status() -> void:
	_set_link(_link)


func set_terminal_open(open: bool) -> void:
	$HUD.visible = not open


func interaction_caption() -> String:
	if _link == Link.OFFLINE:
		return "E · Restart radio"
	return "E · Send message"


func interact() -> String:
	if _link == Link.OFFLINE:
		_set_link(Link.ONLINE)
		TaskManager.complete_task(TaskManager.TASK_REPAIR_COMMUNICATIONS)
		return "Radio restored"
	return send_report()


func send_report() -> String:
	if _link == Link.OFFLINE:
		return _show_report_message("Restart the radio in the command center", false)
	if _link == Link.UNSTABLE:
		return _show_report_message("Weak signal · Wait for it to return", false)
	if not _report_timer.is_stopped():
		return "Sending to Earth…"
	_report_timer.start(REPORT_SECONDS)
	publish_status()
	_show_report_message("Sending to Earth…", true)
	_feedback_timer.stop()
	return "Sending to Earth…"


func _confirm_report() -> void:
	publish_status()
	if not DayManager.is_day_completed:
		_show_report_message("Message confirmed · Simulated round trip", true)
		report_confirmed.emit()


func _on_day_started(_day: int) -> void:
	_flare_timer.paused = false
	_report_timer.stop()
	_feedback_timer.stop()
	_report_message.hide()
	publish_status()


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
			"Restart radio", "Press E at the COM panel on the north wall.",
			"Command center · COM panel")
		_set_link(Link.OFFLINE)
		link_failed.emit()


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
		_show_report_message("Message interrupted · Try again when the radio is back", false)
	var status := "Online"
	var color := Color("#6aefa7")
	match value:
		Link.UNSTABLE:
			status = "Radio signal weak"
			color = Color("#ffda75")
		Link.OFFLINE:
			status = "Offline"
			color = Color("#ff927d")
	_display.text = "● COM" if value == Link.ONLINE else "⚠ COM"
	_display.modulate = color
	_update_alert()
	if value == Link.ONLINE and not _report_timer.is_stopped():
		status = "Sending to Earth…"
	status_changed.emit(status, value == Link.ONLINE and _report_timer.is_stopped())


func _update_alert() -> void:
	var warning := ""
	var color := Color("#ffda75")
	if _link == Link.UNSTABLE:
		warning = "Solar flare"
	elif _storm_seen and EventManager.get_exit_restriction_name() == "SUSPENDIDA":
		color = Color("#ff927d")
		var protection := "Enter the shelter by the O₂ tank"
		if EventManager.is_player_sheltered():
			protection = "In shelter"
		elif EventManager.is_player_in_shielded_work_zone():
			protection = "Shielded zone · Command center"
		warning = "Solar storm · Get to safety\n%s" % protection
	elif _link == Link.OFFLINE:
		warning = "Radio offline · Restart it in the command center"
	_alert.visible = not warning.is_empty()
	if _message.text != warning:
		_message.text = warning
	_message.modulate = color
