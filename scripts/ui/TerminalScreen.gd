# res://scripts/ui/TerminalScreen.gd
class_name TerminalScreen
extends CanvasLayer

## TerminalScreen.gd - Terminal interactiva retro del Centro de Mando
## Desplegada al presionar [E] frente a la consola en BottomWallCommandCenter.
## Muestra el registro de misiones (TaskManager) y la telemetría de eventos
## espaciales y radiación solar histórica (EventManager / NASA DONKI / SWPC).
## Diseñado con estética de fósforo verde monocromático y marco CRT (Screen.png).

# ==============================================================================
# SEÑALES
# ==============================================================================

signal terminal_opened()
signal terminal_closed()
signal eat_requested()
signal drink_requested()
signal grow_requested()
signal recycle_requested()

# ==============================================================================
# CONSTANTES DE ESTILO RETRO CRT
# ==============================================================================

const COLOR_PHOSPHOR_GREEN: Color = Color(0.0, 1.0, 0.4, 1.0)       # #00ff66
const COLOR_PHOSPHOR_DIM: Color = Color(0.15, 0.65, 0.3, 1.0)        # #26a64d
const COLOR_PHOSPHOR_BRIGHT: Color = Color(0.5, 1.0, 0.7, 1.0)     # #80ffb3
const COLOR_ALERT_YELLOW: Color = Color(1.0, 0.85, 0.1, 1.0)        # #ffd91a
const COLOR_ALERT_RED: Color = Color(1.0, 0.25, 0.25, 1.0)          # #ff4040
const COLOR_CRT_BG: Color = Color(0.05, 0.15, 0.0, 1.0)             # #0d2700

# ==============================================================================
# REFERENCIAS A NODOS
# ==============================================================================

@onready var screen_frame: NinePatchRect = $ScreenFrame
@onready var mission_clock_label: Label = $ScreenFrame/MarginContainer/VBox/Header/ClockLabel
@onready var header_title_label: Label = $ScreenFrame/MarginContainer/VBox/Header/TitleLabel
@onready var status_badge_label: Label = $ScreenFrame/MarginContainer/VBox/Header/StatusBadgeLabel

@onready var missions_vbox: VBoxContainer = $ScreenFrame/MarginContainer/VBox/MainSplit/MissionsColumn/MissionsScroll/MissionsVBox
@onready var telemetry_label: Label = $ScreenFrame/MarginContainer/VBox/MainSplit/EventsColumn/TelemetryBox/TelemetryLabel
@onready var notices_vbox: VBoxContainer = $ScreenFrame/MarginContainer/VBox/MainSplit/EventsColumn/NoticesScroll/NoticesVBox
@onready var footer_hint_label: Label = $ScreenFrame/MarginContainer/VBox/Footer/FooterHintLabel

# Fuente tipográfica retro monoespaciada
var _terminal_font: SystemFont
var _is_open: bool = false
var _satiety_bar: ProgressBar
var _hydration_bar: ProgressBar
var _rations_label: Label
var _water_label: Label
var _life_support_result: Label
var _rations: int
var _drinking_water: int

# ==============================================================================
# CICLO DE VIDA
# ==============================================================================

func _ready() -> void:
	visible = false
	_setup_fonts()
	_connect_managers()
	refresh()


func _setup_fonts() -> void:
	_terminal_font = SystemFont.new()
	_terminal_font.font_names = PackedStringArray([
		"Monospace", "Courier New", "Courier", "DejaVu Sans Mono", "Liberation Mono", "Consolas"
	])


func setup_life_support(grow_cost: float, recycle_cost: float) -> void:
	var body: VBoxContainer = $ScreenFrame/MarginContainer/VBox
	var section := VBoxContainer.new()
	section.name = "LifeSupport"
	body.add_child(section)
	body.move_child(section, body.get_node("HSeparator2").get_index())
	section.add_child(_create_styled_label("=== [ SOPORTE VITAL ] ===", COLOR_PHOSPHOR_BRIGHT, 12))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	section.add_child(columns)

	var food := VBoxContainer.new()
	food.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(food)
	_rations_label = _create_styled_label("", COLOR_PHOSPHOR_GREEN, 12)
	food.add_child(_rations_label)
	_satiety_bar = _add_needs_bar(food)
	_add_supply_buttons(food, "Comer", eat_requested, "Cultivar", grow_cost, grow_requested)

	var water := VBoxContainer.new()
	water.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(water)
	_water_label = _create_styled_label("", COLOR_PHOSPHOR_GREEN, 12)
	water.add_child(_water_label)
	_hydration_bar = _add_needs_bar(water)
	_add_supply_buttons(water, "Beber", drink_requested, "Reciclar agua", recycle_cost, recycle_requested)

	_life_support_result = _create_styled_label(" ", COLOR_PHOSPHOR_GREEN, 11)
	section.add_child(_life_support_result)


func _add_needs_bar(column: VBoxContainer) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size.y = 15
	bar.show_percentage = false
	var background := StyleBoxFlat.new()
	background.bg_color = Color("#153420")
	bar.add_theme_stylebox_override("background", background)
	column.add_child(bar)
	return bar


func _add_supply_buttons(column: VBoxContainer, consume_text: String, consume: Signal,
		produce_text: String, cost: float, produce: Signal) -> void:
	var row := HBoxContainer.new()
	column.add_child(row)
	_add_supply_button(row, consume_text, consume)
	_add_supply_button(row, "%s (%.0f W)" % [produce_text, cost], produce)


func _add_supply_button(row: HBoxContainer, caption: String, requested: Signal) -> void:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 26
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_override("font", _terminal_font)
	button.add_theme_font_size_override("font_size", 12)
	for state in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#0d2818") if state == "normal" else Color("#20452b")
		style.border_color = COLOR_PHOSPHOR_DIM
		style.set_border_width_all(1)
		style.set_content_margin_all(4)
		button.add_theme_stylebox_override(state, style)
		button.add_theme_color_override("font_color" if state == "normal" else
			"font_%s_color" % state, COLOR_PHOSPHOR_BRIGHT)
	button.pressed.connect(func(): requested.emit())
	row.add_child(button)


func update_life_support_needs(satiety: float, hydration: float, _bone_density: float) -> void:
	_update_needs_bar(_satiety_bar, satiety)
	_update_needs_bar(_hydration_bar, hydration)
	_update_life_support_labels()


func update_life_support_supplies(rations: int, drinking_water: int) -> void:
	_rations = rations
	_drinking_water = drinking_water
	_update_life_support_labels()


func _update_life_support_labels() -> void:
	_rations_label.text = "🍴 Saciedad %.0f/100  ·  Raciones %d" % [_satiety_bar.value, _rations]
	_water_label.text = "💧 Hidratación %.0f/100  ·  Agua potable %d" % [_hydration_bar.value, _drinking_water]


func _update_needs_bar(bar: ProgressBar, current: float) -> void:
	bar.value = current
	var fill := StyleBoxFlat.new()
	fill.bg_color = COLOR_ALERT_YELLOW if current <= AstronautNeeds.MISSION_THRESHOLD else COLOR_PHOSPHOR_GREEN
	bar.add_theme_stylebox_override("fill", fill)


func show_life_support_result(message: String, success: bool) -> void:
	_life_support_result.text = message
	_life_support_result.modulate = COLOR_PHOSPHOR_BRIGHT if success else COLOR_ALERT_YELLOW


func _connect_managers() -> void:
	if has_node("/root/TaskManager"):
		var tm = get_node("/root/TaskManager")
		if tm.has_signal("new_task_assigned"):
			tm.new_task_assigned.connect(func(_id, _urgent): if _is_open: _populate_tasks())
		if tm.has_signal("task_completed"):
			tm.task_completed.connect(func(_id): if _is_open: _populate_tasks())
		if tm.has_signal("task_failed"):
			tm.task_failed.connect(func(_id): if _is_open: _populate_tasks())
		if tm.has_signal("task_timer_updated"):
			tm.task_timer_updated.connect(func(_id, _rem, _tot): if _is_open: _populate_tasks())
			
	if has_node("/root/EventManager"):
		var em = get_node("/root/EventManager")
		if em.has_signal("solar_notice_posted"):
			em.solar_notice_posted.connect(func(_n): if _is_open: _populate_events())
		if em.has_signal("solar_notice_updated"):
			em.solar_notice_updated.connect(func(_n): if _is_open: _populate_events())
		if em.has_signal("exit_restriction_changed"):
			em.exit_restriction_changed.connect(func(_st, _re): if _is_open: _populate_events())
		if em.has_signal("shelter_order_issued"):
			em.shelter_order_issued.connect(func(_ord, _shel, _time): if _is_open: _populate_events())
		if em.has_signal("radiation_exposure_updated"):
			em.radiation_exposure_updated.connect(func(_fl, _do, _rt): if _is_open: _populate_events())
		if em.has_signal("solar_calendar_restarted"):
			em.solar_calendar_restarted.connect(func(): if _is_open: _populate_events())
			
	if has_node("/root/DayManager"):
		var dm = get_node("/root/DayManager")
		if dm.has_signal("day_time_updated"):
			dm.day_time_updated.connect(_on_day_time_updated)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
		
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E or event.keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()

# ==============================================================================
# APERTURA Y CIERRE
# ==============================================================================

## Abre la terminal e inicializa su contenido
func open() -> void:
	_is_open = true
	visible = true
	refresh()
	terminal_opened.emit()


## Cierra la terminal
func close() -> void:
	_is_open = false
	visible = false
	terminal_closed.emit()


## Alterna el estado abierto/cerrado de la terminal
func toggle() -> void:
	if _is_open:
		close()
	else:
		open()


## Retorna verdadero si la terminal está desplegada en pantalla
func is_open() -> bool:
	return _is_open

# ==============================================================================
# RENDERIZADO Y POBLACIÓN DE DATOS (MISIONES Y EVENTOS)
# ==============================================================================

## Refresca todos los paneles de la terminal con datos de los gestores
func refresh() -> void:
	_update_header()
	_populate_tasks()
	_populate_events()


func _update_header() -> void:
	if not header_title_label:
		return
	header_title_label.text = "> OUTERBASE TERMINAL OS v2.6 // CENTRO DE MANDO"
	
	var em_status: String = "EN LÍNEA"
	if has_node("/root/EventManager"):
		var em = get_node("/root/EventManager")
		em_status = em.get_exit_restriction_name()
	if status_badge_label:
		status_badge_label.text = "[ESTADO: %s]" % em_status
		if em_status == "SUSPENDIDA":
			status_badge_label.modulate = COLOR_ALERT_RED
		elif em_status == "RESTRINGIDA" or em_status == "VIGILANCIA":
			status_badge_label.modulate = COLOR_ALERT_YELLOW
		else:
			status_badge_label.modulate = COLOR_PHOSPHOR_GREEN


func _populate_tasks() -> void:
	if not missions_vbox:
		return
		
	# Limpiar elementos anteriores
	for child in missions_vbox.get_children():
		child.queue_free()
		
	var tasks: Array[Dictionary] = []
	if has_node("/root/TaskManager"):
		var tm = get_node("/root/TaskManager")
		tasks = tm.get_active_tasks_data()
		
	if tasks.is_empty():
		var empty_lbl = _create_styled_label(
			"> [OK] No hay misiones críticas pendientes.\n" +
			"> Sistemas de la estación operando nominalmente.\n" +
			"> Esperando directivas de misión...",
			COLOR_PHOSPHOR_DIM,
			11
		)
		missions_vbox.add_child(empty_lbl)
		return
		
	for task in tasks:
		var task_panel = _create_task_entry(task)
		missions_vbox.add_child(task_panel)


func _create_task_entry(task: Dictionary) -> PanelContainer:
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.08, 0.02, 0.8)
	style.border_color = COLOR_ALERT_YELLOW if task.get("is_urgent", false) else COLOR_PHOSPHOR_DIM
	style.set_border_width_all(1)
	style.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	
	var is_urgent: bool = task.get("is_urgent", false)
	var title_prefix = "[!] URGENTE: " if is_urgent else "[*] TAREA: "
	var title_text = title_prefix + str(task.get("title", "Tarea sin nombre"))
	var title_color = COLOR_ALERT_YELLOW if is_urgent else COLOR_PHOSPHOR_BRIGHT
	var title_lbl = _create_styled_label(title_text, title_color, 12, true)
	vbox.add_child(title_lbl)
	
	var loc_text = "> Ubicación: %s | ID: %s" % [str(task.get("target_location", "General")), str(task.get("id", ""))]
	var loc_lbl = _create_styled_label(loc_text, COLOR_PHOSPHOR_GREEN, 10)
	vbox.add_child(loc_lbl)
	
	var desc_text = "> %s" % str(task.get("description", ""))
	var desc_lbl = _create_styled_label(desc_text, COLOR_PHOSPHOR_DIM, 10)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc_lbl)
	
	var time_limit: float = float(task.get("time_limit", 0.0))
	if time_limit > 0.0:
		var time_rem: float = float(task.get("time_remaining", 0.0))
		var time_text = "> Tiempo límite: %.1fs / %.1fs" % [time_rem, time_limit]
		var time_lbl = _create_styled_label(time_text, COLOR_ALERT_RED if time_rem < 10.0 else COLOR_ALERT_YELLOW, 10, true)
		vbox.add_child(time_lbl)
		
	panel.add_child(vbox)
	return panel


func _populate_events() -> void:
	_update_telemetry()
	
	if not notices_vbox:
		return
		
	for child in notices_vbox.get_children():
		child.queue_free()
		
	var notices: Array[Dictionary] = []
	if has_node("/root/EventManager"):
		var em = get_node("/root/EventManager")
		notices = em.get_active_notices()
		
	if notices.is_empty():
		var empty_lbl = _create_styled_label(
			"> [RADAR SOLAR] Sin avisos de fulguraciones activas.\n" +
			"> Escáner DONKI / SWPC en escucha pasiva...\n" +
			"> Fondo de radiación espacial: NOMINAL.",
			COLOR_PHOSPHOR_DIM,
			11
		)
		notices_vbox.add_child(empty_lbl)
		return
		
	for notice in notices:
		var notice_panel = _create_notice_entry(notice)
		notices_vbox.add_child(notice_panel)


func _update_telemetry() -> void:
	if not telemetry_label:
		return
		
	var flux_pfu: float = 0.0
	var dose_msv: float = 0.0
	var order_text: String = "Salida permitida"
	var exit_state: String = "PERMITIDA"
	var is_sheltered: bool = true
	
	if has_node("/root/EventManager"):
		var em = get_node("/root/EventManager")
		flux_pfu = em.get_current_flux_pfu()
		dose_msv = em.get_accumulated_simulated_dose_msv()
		exit_state = em.get_exit_restriction_name()
		is_sheltered = em.is_player_sheltered()
		
	var shelter_desc = "DENTRO DEL REFUGIO [SEGURO]" if is_sheltered else "EN EXTERIOR (EVA) [EXPUESTO]"
	
	var telemetry_text = (
		"┌─ TELEMETRÍA AMBIENTAL & RADIACIÓN ──────────┐\n" +
		"│ ESTADO SALIDA : %-28s│\n" +
		"│ ASTRONAUTA    : %-28s│\n" +
		"│ FLUJO PROTONES: %-28s│\n" +
		"│ DOSIS SIMULADA: %-28s│\n" +
		"└─────────────────────────────────────────────┘"
	) % [
		exit_state,
		shelter_desc,
		"%.1f pfu (SWPC)" % flux_pfu,
		"%.4f mSv" % dose_msv
	]
	
	telemetry_label.text = telemetry_text
	telemetry_label.add_theme_font_override("font", _terminal_font)
	telemetry_label.add_theme_font_size_override("font_size", 10)
	
	if exit_state == "SUSPENDIDA":
		telemetry_label.modulate = COLOR_ALERT_RED
	elif exit_state == "RESTRINGIDA" or exit_state == "VIGILANCIA":
		telemetry_label.modulate = COLOR_ALERT_YELLOW
	else:
		telemetry_label.modulate = COLOR_PHOSPHOR_GREEN


func _create_notice_entry(notice: Dictionary) -> PanelContainer:
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.08, 0.02, 0.8)
	style.border_color = COLOR_ALERT_YELLOW if str(notice.get("estado_salida", "")) != "PERMITIDA" else COLOR_PHOSPHOR_DIM
	style.set_border_width_all(1)
	style.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	
	var title = str(notice.get("titulo", "Aviso Solar"))
	var title_lbl = _create_styled_label("[AVISO] " + title, COLOR_ALERT_YELLOW, 11, true)
	vbox.add_child(title_lbl)
	
	var meta_text = "> Hito: %s | Ep: %s | UTC: %s" % [
		str(notice.get("tipo_hito", "N/A")),
		str(notice.get("id_episodio", "N/A")),
		str(notice.get("fecha_utc", "N/A"))
	]
	var meta_lbl = _create_styled_label(meta_text, COLOR_PHOSPHOR_DIM, 9)
	vbox.add_child(meta_lbl)
	
	var fuente_text = "> Fuente: %s | Nivel: %s | Flujo: %.1f pfu" % [
		str(notice.get("fuente", "NASA/DONKI")),
		str(notice.get("nivel", notice.get("clase", "N/A"))),
		float(notice.get("flujo_pfu", 0.0))
	]
	var fuente_lbl = _create_styled_label(fuente_text, COLOR_PHOSPHOR_GREEN, 9)
	vbox.add_child(fuente_lbl)
	
	var msg_text = "> %s" % str(notice.get("mensaje", ""))
	var msg_lbl = _create_styled_label(msg_text, COLOR_PHOSPHOR_BRIGHT, 10)
	msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(msg_lbl)
	
	panel.add_child(vbox)
	return panel


func _create_styled_label(text: String, color: Color, font_size: int = 11, is_bold: bool = false) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_override("font", _terminal_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.modulate = color
	return label


func _on_day_time_updated(current_seconds: float, _total_day: float) -> void:
	if not mission_clock_label or not _is_open:
		return
	var minutes: int = int(current_seconds) / 60
	var seconds: int = int(current_seconds) % 60
	mission_clock_label.text = "T+ %02d:%02d UTC" % [minutes, seconds]
