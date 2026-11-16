# res://scripts/ui/TableroAvisosSolares.gd
class_name TableroAvisosSolares
extends Control

## TableroAvisosSolares.gd - Interfaz gráfica del Tablero de Clima Espacial (NASA / NOAA)
## Muestra los avisos históricos, estado de salida/refugio, flujo observado en pfu
## y la exposición a radiación simulada del astronauta.
## Comunicación 100% desacoplada a través de Señales (EventManager y DayManager).

# ==============================================================================
# NODOS INTERNOS DE LA UI
# ==============================================================================

@onready var mission_time_label: Label = $MainPanel/MarginContainer/VBoxContainer/HeaderContainer/MissionTimeLabel
@onready var status_badge_label: Label = $MainPanel/MarginContainer/VBoxContainer/HeaderContainer/StatusBadgeLabel

@onready var order_banner_container: PanelContainer = $MainPanel/MarginContainer/VBoxContainer/OrderBannerContainer
@onready var order_text_label: Label = $MainPanel/MarginContainer/VBoxContainer/OrderBannerContainer/MarginContainer/VBoxContainer/OrderTextLabel
@onready var order_detail_label: Label = $MainPanel/MarginContainer/VBoxContainer/OrderBannerContainer/MarginContainer/VBoxContainer/OrderDetailLabel

@onready var flux_value_label: Label = $MainPanel/MarginContainer/VBoxContainer/MetersContainer/FluxBox/FluxValueLabel
@onready var dose_value_label: Label = $MainPanel/MarginContainer/VBoxContainer/MetersContainer/DoseBox/DoseValueLabel
@onready var shelter_status_label: Label = $MainPanel/MarginContainer/VBoxContainer/MetersContainer/ShelterBox/ShelterStatusLabel

@onready var notices_container: VBoxContainer = $MainPanel/MarginContainer/VBoxContainer/NoticesScroll/NoticesVBox

@onready var enter_shelter_button: Button = $MainPanel/MarginContainer/VBoxContainer/ActionsContainer/EnterShelterButton
@onready var exit_exterior_button: Button = $MainPanel/MarginContainer/VBoxContainer/ActionsContainer/ExitExteriorButton

# Mapeo de tarjetas de avisos por id_episodio para actualizaciones en tiempo real
var _notice_cards: Dictionary = {}

# ==============================================================================
# CICLO DE VIDA
# ==============================================================================

func _ready() -> void:
	# Conexión con EventManager
	if has_node("/root/EventManager"):
		var em = get_node("/root/EventManager")
		em.solar_notice_posted.connect(_on_solar_notice_posted)
		em.solar_notice_updated.connect(_on_solar_notice_updated)
		em.exit_restriction_changed.connect(_on_exit_restriction_changed)
		em.shelter_order_issued.connect(_on_shelter_order_issued)
		em.radiation_exposure_updated.connect(_on_radiation_exposure_updated)
		em.solar_calendar_restarted.connect(_on_solar_calendar_restarted)
		
		# Cargar estado inicial
		_update_status_badge(em.get_exit_restriction_name())
		_update_shelter_display(em.is_player_sheltered())
		
		# Si ya existen avisos cargados
		for notice in em.get_active_notices():
			_on_solar_notice_posted(notice)
	
	# Conexión con DayManager para el reloj de misión
	if has_node("/root/DayManager"):
		var dm = get_node("/root/DayManager")
		dm.day_time_updated.connect(_on_day_time_updated)
	
	# Botones de acción manual
	if enter_shelter_button:
		enter_shelter_button.pressed.connect(_on_enter_shelter_pressed)
	if exit_exterior_button:
		exit_exterior_button.pressed.connect(_on_exit_exterior_pressed)
		
	# Inicialmente ocultar banner de orden si no hay alerta
	if order_banner_container:
		order_banner_container.visible = false

# ==============================================================================
# RECEPCIÓN DE SEÑALES DEL CLIMA ESPACIAL
# ==============================================================================

func _on_day_time_updated(time_remaining: float, total_time: float) -> void:
	if mission_time_label:
		var elapsed_secs: int = int(round(total_time - time_remaining))
		var total_secs: int = int(round(total_time))
		mission_time_label.text = "T+ %02d:%02d / %02d:%02d" % [
			elapsed_secs / 60, elapsed_secs % 60,
			total_secs / 60, total_secs % 60
		]


func _on_solar_notice_posted(notice: Dictionary) -> void:
	var ep_id: String = notice.get("id_episodio", "")
	if _notice_cards.has(ep_id):
		_on_solar_notice_updated(notice)
		return
	
	var card := _build_notice_card(notice)
	notices_container.add_child(card)
	_notice_cards[ep_id] = card


func _on_solar_notice_updated(notice: Dictionary) -> void:
	var ep_id: String = notice.get("id_episodio", "")
	if not _notice_cards.has(ep_id):
		_on_solar_notice_posted(notice)
		return
	
	var card: PanelContainer = _notice_cards[ep_id]
	_update_card_ui(card, notice)


func _on_exit_restriction_changed(new_state: String, _reason: String) -> void:
	_update_status_badge(new_state)


func _on_shelter_order_issued(order_text: String, is_sheltered: bool, time_to_shelter: float) -> void:
	_update_shelter_display(is_sheltered)
	
	if order_banner_container:
		if order_text.is_empty():
			order_banner_container.visible = false
		else:
			order_banner_container.visible = true
			if order_text_label:
				order_text_label.text = order_text
			if order_detail_label:
				if not is_sheltered and time_to_shelter > 0.0:
					order_detail_label.text = "Time to reach shelter: %.1f s" % time_to_shelter
				elif is_sheltered:
					order_detail_label.text = "You are in the shelter. Stay inside."
				else:
					order_detail_label.text = "Exit is limited. Radiation risk is higher outside."


func _on_radiation_exposure_updated(flux_pfu: float, dose_msv: float, dose_rate_msv_s: float) -> void:
	if flux_value_label:
		flux_value_label.text = "%.1f pfu" % flux_pfu
	if dose_value_label:
		dose_value_label.text = "%.2f mSv (%.3f mSv/s)" % [dose_msv, dose_rate_msv_s]


func _on_solar_calendar_restarted() -> void:
	for child in notices_container.get_children():
		child.queue_free()
	_notice_cards.clear()
	
	if order_banner_container:
		order_banner_container.visible = false
	if flux_value_label:
		flux_value_label.text = "0.0 pfu"
	if dose_value_label:
		dose_value_label.text = "0.00 mSv (0.000 mSv/s)"
	_update_status_badge("PERMITIDA")
	_update_shelter_display(true)

# ==============================================================================
# CONSTRUCCIÓN Y ACTUALIZACIÓN VISUAL DE TARJETAS DE AVISOS
# ==============================================================================

func _build_notice_card(notice: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "Card_" + notice.get("id_episodio", "unknown").replace(":", "_").replace("-", "_")
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	margin.add_child(vbox)
	
	var title_lbl := Label.new()
	title_lbl.name = "TitleLabel"
	vbox.add_child(title_lbl)
	
	var msg_lbl := Label.new()
	msg_lbl.name = "MsgLabel"
	msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(msg_lbl)
	
	var meta_lbl := Label.new()
	meta_lbl.name = "MetaLabel"
	meta_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75, 0.9))
	vbox.add_child(meta_lbl)
	
	_update_card_ui(panel, notice)
	return panel


func _update_card_ui(panel: PanelContainer, notice: Dictionary) -> void:
	var vbox: VBoxContainer = panel.get_node_or_null("MarginContainer/VBox")
	if not vbox:
		return
		
	var title_lbl: Label = vbox.get_node_or_null("TitleLabel")
	var msg_lbl: Label = vbox.get_node_or_null("MsgLabel")
	var meta_lbl: Label = vbox.get_node_or_null("MetaLabel")
	
	if title_lbl:
		title_lbl.text = notice.get("titulo", "Sun alert")
	if msg_lbl:
		msg_lbl.text = notice.get("mensaje", "")
	if meta_lbl:
		var flux_info := ""
		if notice.get("flujo_pfu", 0.0) > 0.0:
			flux_info = " | Proton flux: %d pfu" % int(notice["flujo_pfu"])
		elif notice.get("umbral_pfu", 0) > 0:
			flux_info = " | Threshold: %d pfu" % int(notice["umbral_pfu"])
			
		meta_lbl.text = "Source: %s [%s] | UTC date: %s%s\nURL: %s" % [
			notice.get("fuente", "NASA/NOAA"),
			notice.get("id_fuente", notice.get("id_episodio", "")),
			notice.get("fecha_utc", "N/A"),
			flux_info,
			notice.get("url_fuente", "N/A")
		]

# ==============================================================================
# HELPERS DE ESTADO
# ==============================================================================

func _update_status_badge(state: String) -> void:
	if not status_badge_label:
		return
	status_badge_label.text = EventManager.get_exit_restriction_label(state)
	match state:
		"PERMITIDA":
			status_badge_label.add_theme_color_override("font_color", Color(0.2, 0.85, 0.3))
		"VIGILANCIA":
			status_badge_label.add_theme_color_override("font_color", Color(0.9, 0.75, 0.2))
		"SUSPENDIDA":
			status_badge_label.add_theme_color_override("font_color", Color(0.95, 0.25, 0.2))
		"RESTRINGIDA":
			status_badge_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.15))
		_:
			status_badge_label.add_theme_color_override("font_color", Color.WHITE)


func _update_shelter_display(is_sheltered: bool) -> void:
	if not shelter_status_label:
		return
	if is_sheltered:
		shelter_status_label.text = "In shelter (protected)"
		shelter_status_label.add_theme_color_override("font_color", Color(0.2, 0.85, 0.3))
	else:
		shelter_status_label.text = "Outside (exposed)"
		shelter_status_label.add_theme_color_override("font_color", Color(0.95, 0.25, 0.2))

# ==============================================================================
# ACCIONES DE BOTONES
# ==============================================================================

func _on_enter_shelter_pressed() -> void:
	if has_node("/root/EventManager"):
		get_node("/root/EventManager").intentar_entrar_refugio()


func _on_exit_exterior_pressed() -> void:
	if has_node("/root/EventManager"):
		get_node("/root/EventManager").intentar_salir()
