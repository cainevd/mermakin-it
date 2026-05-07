class_name Starter3D
extends Node3D
## Owns the gameplay-to-win transition and in-game pause flow for the starter scene.

const YOU_WIN_SCENE_PATH := "res://scenes/you_win.tscn"
const STARTUP_FADE_DURATION := 0.5
const FADE_OUT_DURATION := 0.5

@onready var fade_rect: ColorRect = $FadeLayer/FadeRect
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var audio_manager: AudioStreamPlayer3D = $Camera3D/AudioManager



var _is_transitioning: bool = false
var _can_pause: bool = false


func _ready() -> void:
	if not Global.you_win_requested.is_connected(_on_you_win_requested):
		Global.you_win_requested.connect(_on_you_win_requested)

	if pause_menu != null:
		if not pause_menu.pause_requested.is_connected(
				_on_pause_menu_pause_requested):
			pause_menu.pause_requested.connect(_on_pause_menu_pause_requested)
		if not pause_menu.resume_requested.is_connected(
				_on_pause_menu_resume_requested):
			pause_menu.resume_requested.connect(_on_pause_menu_resume_requested)
		if not pause_menu.restart_requested.is_connected(
				_on_pause_menu_restart_requested):
			pause_menu.restart_requested.connect(_on_pause_menu_restart_requested)
		pause_menu.close_menu()

	if fade_rect != null:
		fade_rect.color = Color.WHITE
		fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

		await _fade_from_white()

	_can_pause = true



func _on_you_win_requested() -> void:
	if _is_transitioning:
		return

	_is_transitioning = true
	await _fade_to_black()
	_switch_to_you_win_scene()


func _fade_from_white() -> void:
	if fade_rect == null:
		return

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(
		fade_rect,
		"color",
		Color(1.0, 1.0, 1.0, 0.0),
		STARTUP_FADE_DURATION
	)
	await tween.finished


func _fade_to_black() -> void:
	if fade_rect == null:
		return

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(fade_rect, "color", Color.BLACK, FADE_OUT_DURATION)
	await tween.finished


func _switch_to_you_win_scene() -> void:
	var change_error := get_tree().change_scene_to_file(YOU_WIN_SCENE_PATH)
	if change_error != OK:
		push_error("Failed to change to the You Win scene.")


func _on_pause_menu_pause_requested() -> void:
	if not _can_pause or _is_transitioning or get_tree().paused:
		return

	if pause_menu != null:
		pause_menu.open_menu()

	get_tree().paused = true


func _on_pause_menu_resume_requested() -> void:
	if pause_menu != null:
		pause_menu.close_menu()

	get_tree().paused = false


func _on_pause_menu_restart_requested() -> void:
	if pause_menu != null:
		pause_menu.close_menu()

	get_tree().paused = false

	var error := get_tree().reload_current_scene()
	if error != OK:
		push_error("Failed to restart the starter 3D scene.")
