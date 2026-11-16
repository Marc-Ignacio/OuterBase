extends Control

const MISSION_SCENE := "res://scenes/levels/BaseLunar.tscn"

@onready var home: VBoxContainer = $Center/Card/Margin/Home
@onready var credits: VBoxContainer = $Center/Card/Margin/Credits
@onready var start_button: Button = $Center/Card/Margin/Home/Start
@onready var credits_button: Button = $Center/Card/Margin/Home/CreditsButton
@onready var back_button: Button = $Center/Card/Margin/Credits/Back
@onready var sources: RichTextLabel = $Center/Card/Margin/Credits/Sources
@onready var error_label: Label = $Center/Card/Margin/Home/StartError


func _ready() -> void:
	start_button.pressed.connect(_start_mission)
	credits_button.pressed.connect(_open_credits)
	back_button.pressed.connect(_close_credits)
	sources.meta_clicked.connect(_open_source)
	start_button.grab_focus()


func _start_mission() -> void:
	start_button.disabled = true
	if get_tree().change_scene_to_file(MISSION_SCENE) != OK:
		error_label.show()
		start_button.disabled = false
		start_button.grab_focus()


func _open_credits() -> void:
	home.hide()
	credits.show()
	sources.scroll_to_line(0)
	back_button.grab_focus()


func _close_credits() -> void:
	credits.hide()
	home.show()
	credits_button.grab_focus()


func _open_source(url: Variant) -> void:
	OS.shell_open(str(url))
