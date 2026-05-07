class_name CookingPot
extends Node3D
## Stores cookable pickups, advances them through cook and burn states,
## and serves batches once the recipe size is filled.

signal item_inserted(item: RigidBody3D)
signal recipe_completed(items: Array)

enum ItemStage {
	RAW,
	COOKED,
	BURNED,
}

const SLOT_ANGLE_STEP := 2.39996323
const SLOT_BASE_RADIUS := 0.42
const SLOT_RADIUS_STEP := 0.16
const SLOT_HEIGHT_STEP := 0.18
const BOB_SPEED := 7.5
const BOB_AMPLITUDE_RAW := 0.8
const BOB_AMPLITUDE_COOKED := 0.5
const BOB_AMPLITUDE_BURNED := 0.2
const ANIMATION_INTERVAL := 0.5
const CAULDRON_HAPPY_TEXTURE_FRAMES: Array[Texture2D] = [
	preload("res://assets/Art/Interactables/CauldronHappy.png"),
	preload("res://assets/Art/Interactables/CauldronBoiling.png"),
]
const CAULDRON_SAD_TEXTURE_FRAMES: Array[Texture2D] = [
	preload("res://assets/Art/Interactables/CauldronSad.png"),
	preload("res://assets/Art/Interactables/Cauldron_sad.png"),
]

enum CauldronMood {
	HAPPY,
	SAD,
}

@export_range(1, 12, 1) var recipe_size: int = 3
@export var interaction_radius: float = 1.75
@export var serve_duration: float = 0.35

@onready var interaction_area: Area3D = $InteractionArea
@onready var contents_root: Node3D = $ContentsRoot
@onready var serve_anchor: Marker3D = $ServeAnchor
@onready var sprite_3d: Sprite3D = $Sprite3D
@onready var texture_swap_timer: Timer = $TextureSwapTimer

@onready var audio_manager: AudioStreamPlayer3D = $"../Camera3D/AudioManager"

var _entries: Array[PotItemEntry] = []
var _is_serving: bool = false
var _sprite_material: ShaderMaterial
var _texture_frame_index: int = 0
var _cauldron_mood: CauldronMood = CauldronMood.HAPPY
var _current_texture_frames: Array[Texture2D] = CAULDRON_HAPPY_TEXTURE_FRAMES


func _ready() -> void:
	add_to_group("cooking_pot")

	if (
			interaction_area == null
			or contents_root == null
			or serve_anchor == null
			or sprite_3d == null
			or texture_swap_timer == null
	):
		push_error("CookingPot is missing required child nodes.")
		return

	_setup_texture_animation()
	interaction_area.body_entered.connect(_on_interaction_area_body_entered)
	if not Global.cooking_pot_meal_scored.is_connected(_on_cooking_pot_meal_scored):
		Global.cooking_pot_meal_scored.connect(_on_cooking_pot_meal_scored)
	call_deferred("_collect_overlapping_items")


func _process(_delta: float) -> void:
	if _is_serving:
		return

	_update_item_visuals()
	_update_item_stages()


func try_interact(held_item: RigidBody3D, hand_position: Vector3) -> bool:
	if _is_serving:
		return false

	if held_item != null and is_instance_valid(held_item):
		return _try_accept_held_item(held_item, hand_position)

	return _try_accept_touching_item(hand_position)


func _try_accept_held_item(item: RigidBody3D, hand_position: Vector3) -> bool:
	if not _can_accept_item(item):
		return false

	if interaction_area.global_position.distance_to(hand_position) > interaction_radius:
		return false

	return _accept_item(item)


func _try_accept_touching_item(hand_position: Vector3) -> bool:
	if interaction_area.global_position.distance_to(hand_position) > interaction_radius:
		return false

	return _collect_overlapping_items()


func _can_accept_item(item: RigidBody3D) -> bool:
	if item == null or not is_instance_valid(item):
		return false
	if not item.is_in_group("pickup"):
		return false
	if not _is_cookable_item(item):
		return false
	if _has_item(item):
		return false

	return true


func _is_cookable_item(item: RigidBody3D) -> bool:
	if item.has_method("is_cookable"):
		return item.call("is_cookable")

	if not item.has_method("get_cooks_into"):
		return false

	return item.call("get_cooks_into") != null


func _has_item(item: RigidBody3D) -> bool:
	for entry in _entries:
		if entry.item == item and is_instance_valid(entry.item):
			return true

	return false


func _accept_item(item: RigidBody3D) -> bool:
	if _is_serving:
		return false
	
	if audio_manager:
		audio_manager.play_sound("Audio3D_Cook_Start")
		
	var entry := PotItemEntry.new(
		item,
		_get_time_seconds()
	)
	_entries.append(entry)

	item.reparent(contents_root, true)
	if item.has_method("set_in_pot"):
		item.call("set_in_pot", true)
	if item.has_method("set_held"):
		item.call("set_held", false)

	item.linear_velocity = Vector3.ZERO
	item.angular_velocity = Vector3.ZERO

	_layout_items()
	item_inserted.emit(item)
	Global.cooking_pot_item_inserted.emit(self, item)
	Global.cooking_item_consumed.emit(self, item)

	if _entries.size() >= recipe_size:
		_begin_serving()

	return true


func _on_interaction_area_body_entered(body: Node) -> void:
	if _is_serving:
		return

	var pickup := body as RigidBody3D
	if pickup == null:
		return

	_collect_item(pickup)


func _collect_overlapping_items() -> bool:
	var collected_any := false

	for body in interaction_area.get_overlapping_bodies():
		var pickup := body as RigidBody3D
		if pickup == null:
			continue

		collected_any = _collect_item(pickup) or collected_any

	return collected_any


func _collect_item(item: RigidBody3D) -> bool:
	if not _can_accept_item(item):
		return false

	return _accept_item(item)


func _update_item_stages() -> void:
	var now := _get_time_seconds()

	for index in range(_entries.size() - 1, -1, -1):
		var entry: PotItemEntry = _entries[index]
		if entry == null or entry.item == null or not is_instance_valid(entry.item):
			_entries.remove_at(index)
			continue

		var cook_time := _get_item_cook_time(entry.item)
		if cook_time <= 0.0:
			continue

		if now - entry.stage_started_at >= cook_time:
			_advance_entry_to_next_stage(entry, now)


func _advance_entry_to_next_stage(entry: PotItemEntry, now: float) -> void:
	if entry.item == null or not is_instance_valid(entry.item):
		return

	if entry.stage == ItemStage.BURNED:
		return

	var next_scene := _get_next_scene(entry.item)
	if next_scene == null:
		return

	var next_stage := ItemStage.COOKED if entry.stage == ItemStage.RAW else ItemStage.BURNED
	_replace_entry_item(entry, next_scene, next_stage, now)


func _replace_entry_item(
		entry: PotItemEntry,
		item_scene: PackedScene,
		new_stage: ItemStage,
		now: float
) -> void:
	if entry.item == null or not is_instance_valid(entry.item):
		return

	var old_item := entry.item
	var old_transform := old_item.global_transform
	var slot_index := _entries.find(entry)

	var new_item := item_scene.instantiate() as RigidBody3D
	if new_item == null:
		return

	contents_root.add_child(new_item)
	new_item.global_transform = old_transform

	if new_item.has_method("set_in_pot"):
		new_item.call("set_in_pot", true)
	if new_item.has_method("set_held"):
		new_item.call("set_held", false)

	old_item.queue_free()
	entry.item = new_item
	entry.stage = new_stage
	entry.stage_started_at = now

	if slot_index >= 0:
		new_item.position = _get_slot_position(slot_index)


func _layout_items() -> void:
	for index in range(_entries.size()):
		var entry: PotItemEntry = _entries[index]
		if entry == null or entry.item == null or not is_instance_valid(entry.item):
			continue

		entry.item.position = _get_slot_position(index)


func _update_item_visuals() -> void:
	var now := _get_time_seconds()

	for index in range(_entries.size()):
		var entry: PotItemEntry = _entries[index]
		if entry == null or entry.item == null or not is_instance_valid(entry.item):
			continue

		var base_position := _get_slot_position(index)
		var bob_offset := _get_bob_offset(entry, index, now)
		entry.item.position = base_position + bob_offset


func _get_slot_position(index: int) -> Vector3:
	var angle := float(index) * SLOT_ANGLE_STEP
	var radius := SLOT_BASE_RADIUS + sqrt(float(index)) * SLOT_RADIUS_STEP
	var height: float = floorf(float(index) / 6.0) * SLOT_HEIGHT_STEP

	return Vector3(cos(angle) * radius, height, sin(angle) * radius)


func _get_bob_offset(entry: PotItemEntry, index: int, now: float) -> Vector3:
	var amplitude := _get_bob_amplitude(entry.stage)
	if amplitude <= 0.0:
		return Vector3.ZERO

	var phase := float(index) * 1.7 + entry.inserted_at * 0.01
	var bob := sin(now * BOB_SPEED + phase) * amplitude

	return Vector3(0.0, bob, 0.0)


func _get_bob_amplitude(stage: ItemStage) -> float:
	match stage:
		ItemStage.RAW:
			return BOB_AMPLITUDE_RAW
		ItemStage.COOKED:
			return BOB_AMPLITUDE_COOKED
		ItemStage.BURNED:
			return BOB_AMPLITUDE_BURNED

	return 0.0


func _get_next_scene(item: RigidBody3D) -> PackedScene:
	if item.has_method("get_cooks_into"):
		return item.call("get_cooks_into")

	return null


func _get_item_cook_time(item: RigidBody3D) -> float:
	if item != null and item.has_method("get_cook_time"):
		return float(item.call("get_cook_time"))

	return 3.0


func _get_time_seconds() -> float:
	return Time.get_ticks_msec() * 0.001


func _setup_texture_animation() -> void:
	var material := sprite_3d.material_override as ShaderMaterial
	if material == null:
		push_error("CookingPot sprite is missing the billboard shader material.")
		return

	_sprite_material = material.duplicate() as ShaderMaterial
	if _sprite_material == null:
		push_error("CookingPot sprite material could not be duplicated.")
		return

	sprite_3d.material_override = _sprite_material
	texture_swap_timer.wait_time = ANIMATION_INTERVAL

	var timeout_callable := Callable(self, "_on_texture_swap_timer_timeout")
	if not texture_swap_timer.timeout.is_connected(timeout_callable):
		texture_swap_timer.timeout.connect(timeout_callable)

	_set_cauldron_mood(CauldronMood.HAPPY)
	texture_swap_timer.start()


func _on_texture_swap_timer_timeout() -> void:
	if _current_texture_frames.is_empty():
		return

	_texture_frame_index = (_texture_frame_index + 1) % _current_texture_frames.size()
	_apply_texture_frame(_texture_frame_index)


func _on_cooking_pot_meal_scored(judged_pot: Node, score_delta: int) -> void:
	if judged_pot != self:
		return

	if score_delta <= 0:
		_set_cauldron_mood(CauldronMood.SAD)
		return

	_set_cauldron_mood(CauldronMood.HAPPY)


func _set_cauldron_mood(new_mood: CauldronMood) -> void:
	if _cauldron_mood == new_mood:
		_texture_frame_index = 0
		_apply_texture_frame(_texture_frame_index)
		texture_swap_timer.start()
		return

	_cauldron_mood = new_mood
	_current_texture_frames = (
		CAULDRON_SAD_TEXTURE_FRAMES
		if new_mood == CauldronMood.SAD
		else CAULDRON_HAPPY_TEXTURE_FRAMES
	)
	_texture_frame_index = 0
	_apply_texture_frame(_texture_frame_index)
	texture_swap_timer.start()


func _apply_texture_frame(frame_index: int) -> void:
	if sprite_3d == null or _sprite_material == null:
		return

	if frame_index < 0 or frame_index >= _current_texture_frames.size():
		return

	var frame_texture := _current_texture_frames[frame_index]
	sprite_3d.texture = frame_texture
	_sprite_material.set_shader_parameter("billboard_texture", frame_texture)


func _begin_serving() -> void:
	if _is_serving or _entries.is_empty():
		return

	_is_serving = true

	for entry in _entries:
		if entry.stage == ItemStage.RAW:
			_advance_entry_to_next_stage(entry, _get_time_seconds())

	var served_items: Array[RigidBody3D] = []
	for entry in _entries:
		if entry.item != null and is_instance_valid(entry.item):
			served_items.append(entry.item)

	_entries.clear()

	for index in range(served_items.size()):
		_tween_served_item(served_items[index], index)

	await get_tree().create_timer(serve_duration).timeout

	recipe_completed.emit(served_items)
	Global.cooking_pot_recipe_completed.emit(self, served_items)

	for item in served_items:
		if is_instance_valid(item):
			item.queue_free()

	_is_serving = false


func _tween_served_item(item: RigidBody3D, index: int) -> void:
	if item == null or not is_instance_valid(item):
		return

	var offset := Vector3(float(index) * 0.08, 0.0, 0.0)
	var target_position := serve_anchor.global_position + offset
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(item, "global_position", target_position, serve_duration)


class PotItemEntry:
	var item: RigidBody3D
	var inserted_at: float = 0.0
	var stage_started_at: float = 0.0
	var stage: ItemStage = ItemStage.RAW

	func _init(
			new_item: RigidBody3D,
			new_time: float
	) -> void:
		item = new_item
		inserted_at = new_time
		stage_started_at = new_time
