extends ColorRect

const UMBRAL := 30
const VELOCIDAD_NORMAL := 180.0
const FACTOR_MOVIMIENTO_LENTO := 0.6
const FLECHAS := [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]
const MARGEN_ASTRONAUTA := Vector2(15, 19)
const COLOR_SACIEDAD := Color("#ffbb70")
const COLOR_HIDRATACION := Color("#65ccef")
const COLOR_ALERTA := Color("#ff8580")
const COLOR_LISTO := Color("#86e8b1")

var _saciedad := 75
var _hidratacion := 75
var _velocidad := VELOCIDAD_NORMAL

@onready var _panel: PanelContainer = $Center/Panel
@onready var _contenido: VBoxContainer = $Center/Panel/Padding/Content
@onready var _barra_saciedad: ProgressBar = _contenido.get_node("Satiety/Bar")
@onready var _barra_hidratacion: ProgressBar = _contenido.get_node("Hydration/Bar")
@onready var _valor_saciedad: Label = _contenido.get_node("Satiety/Heading/Value")
@onready var _valor_hidratacion: Label = _contenido.get_node("Hydration/Heading/Value")
@onready var _estado: Label = _contenido.get_node("Status")
@onready var _arena: ColorRect = _contenido.get_node("Movement/Arena")
@onready var _astronauta: Node2D = _arena.get_node("Astronaut")


func _ready() -> void:
	get_viewport().size_changed.connect(_ajustar_al_viewport)
	_ajustar_al_viewport()
	_astronauta.draw.connect(_dibujar_astronauta)
	_panel.add_theme_stylebox_override("panel", _estilo(Color("#172538"), Color("#344a63"), 16))
	for barra in [_barra_saciedad, _barra_hidratacion]:
		barra.add_theme_stylebox_override("background", _estilo(Color("#263a50"), Color.TRANSPARENT, 6))
	var acciones: HBoxContainer = _contenido.get_node("Actions")
	acciones.get_node("Advance").pressed.connect(_avanzar_tiempo)
	acciones.get_node("Eat").pressed.connect(_comer)
	acciones.get_node("Drink").pressed.connect(_beber)
	for boton in acciones.get_children():
		boton.add_theme_stylebox_override("normal", _estilo(Color("#223a54"), Color("#46637e"), 8))
		boton.add_theme_stylebox_override("hover", _estilo(Color("#2e5070"), Color("#74a0bf"), 8))
		boton.add_theme_stylebox_override("pressed", _estilo(Color("#142d45"), Color("#74a0bf"), 8))
	_actualizar()


func _input(evento: InputEvent) -> void:
	if evento is InputEventKey and evento.physical_keycode in FLECHAS:
		# Las flechas mueven al astronauta incluso con un botón enfocado.
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	var direccion := Vector2(
		int(Input.is_physical_key_pressed(KEY_RIGHT)) - int(Input.is_physical_key_pressed(KEY_LEFT)),
		int(Input.is_physical_key_pressed(KEY_DOWN)) - int(Input.is_physical_key_pressed(KEY_UP))
	)
	var destino := _astronauta.position + direccion.normalized() * _velocidad * delta
	_astronauta.position = destino.clamp(MARGEN_ASTRONAUTA, _arena.size - MARGEN_ASTRONAUTA)


func _dibujar_astronauta() -> void:
	var traje := Color("#e3edf7")
	_astronauta.draw_rect(Rect2(-12, -2, 24, 12), Color("#8aa4bb"))
	_astronauta.draw_rect(Rect2(-8, -2, 16, 13), traje)
	_astronauta.draw_rect(Rect2(-8, 10, 6, 7), traje)
	_astronauta.draw_rect(Rect2(2, 10, 6, 7), traje)
	_astronauta.draw_circle(Vector2(0, -8), 9, traje, true, -1.0, true)
	_astronauta.draw_circle(Vector2(1, -8), 6, Color("#427eaa"), true, -1.0, true)
	_astronauta.draw_circle(Vector2(3, -10), 2, COLOR_HIDRATACION)


func _ajustar_al_viewport() -> void:
	size = get_viewport_rect().size
	$Center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _avanzar_tiempo() -> void:
	_saciedad = maxi(0, _saciedad - 10)
	_hidratacion = maxi(0, _hidratacion - 15)
	_actualizar()


func _comer() -> void:
	_saciedad = mini(100, _saciedad + 30)
	_actualizar()


func _beber() -> void:
	_hidratacion = mini(100, _hidratacion + 30)
	_actualizar()


func _actualizar() -> void:
	_actualizar_barra(_barra_saciedad, _valor_saciedad, _saciedad, COLOR_SACIEDAD)
	_actualizar_barra(_barra_hidratacion, _valor_hidratacion, _hidratacion, COLOR_HIDRATACION)
	var necesidades: PackedStringArray = []
	if _saciedad <= UMBRAL:
		necesidades.append("comer")
	if _hidratacion <= UMBRAL:
		necesidades.append("beber")
	_velocidad = VELOCIDAD_NORMAL if necesidades.is_empty() else VELOCIDAD_NORMAL * FACTOR_MOVIMIENTO_LENTO
	if necesidades.is_empty():
		_estado.text = "Listo para trabajar"
		_estado.add_theme_color_override("font_color", COLOR_LISTO)
	else:
		_estado.text = "Movimiento lento · Necesita " + " y ".join(necesidades)
		_estado.add_theme_color_override("font_color", COLOR_ALERTA)


func _actualizar_barra(barra: ProgressBar, etiqueta: Label, valor: int, color_normal: Color) -> void:
	var acento := COLOR_ALERTA if valor <= UMBRAL else color_normal
	barra.value = valor
	etiqueta.text = "%d / 100" % valor
	etiqueta.add_theme_color_override("font_color", acento)
	barra.add_theme_stylebox_override("fill", _estilo(acento, Color.TRANSPARENT, 6))


func _estilo(fondo: Color, borde: Color, radio: int) -> StyleBoxFlat:
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = fondo
	estilo.border_color = borde
	estilo.set_border_width_all(1)
	estilo.set_corner_radius_all(radio)
	return estilo
