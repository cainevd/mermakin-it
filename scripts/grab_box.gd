class_name ItemPileSpawner
extends Node3D
## Spawns a physical pile of pickup items in a local area and refills it over time.

const SPAWN_INTERVAL_MIN := 5.0
const SPAWN_INTERVAL_MAX := 15.0

@onready var audio_manager: AudioStreamPlayer3D = $"../Camera3D/AudioManager"
@export var item_scene: PackedScene
@export_range(1, 64, 1) var target_count: int = 3
@export_range(0.0, 10.0, 0.1) var spawn_radius: float = 1.25
@export_range(0.0, 5.0, 0.1) var spawn_height: float = 0.75
@export_range(0.0, 20.0, 0.1) var launch_impulse: float = 2.5
@export_range(0.0, 20.0, 0.1) var spin_impulse: float = 1.0

@onready var timer: Timer = $Timer
@onready var spawn_point: Marker3D = $DisplayArea/SpawnPoint

var _spawn_group: String = ""
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# Use a unique runtime group per spawner instance so counts never bleed across spawners.
	_spawn_group = "item_pile_%s" % str(get_instance_id())

	timer.one_shot = true
	timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	timer.timeout.connect(_on_timer_timeout)

	_rng.randomize()
	if not Global.cooking_item_consumed.is_connected(_on_cooking_item_consumed):
		Global.cooking_item_consumed.connect(_on_cooking_item_consumed)
	_sync_spawn_timer(true)


func _on_timer_timeout() -> void:
	if _get_spawned_item_count() < target_count:
		_spawn_item()

	_sync_spawn_timer()


func _spawn_item() -> void:
	if item_scene == null:
		push_warning("ItemPileSpawner is missing an item_scene.")
		return

	var item := item_scene.instantiate() as RigidBody3D
	if item == null:
		push_warning("ItemPileSpawner expected a RigidBody3D item scene.")
		return

	var world_root := get_tree().current_scene
	if world_root == null:
		world_root = get_tree().root

	world_root.add_child(item)
	if item_scene.resource_path == "res://scenes/items/krab.tscn":
		audio_manager.play_sound("Audio3D_food_Crab")
	if item_scene.resource_path == "res://scenes/items/coconut.tscn":
		audio_manager.play_sound("Audio3D_food_Coconut")
	if item_scene.resource_path == "res://scenes/items/urchin.tscn":
		audio_manager.play_sound("Audio3D_food_Urchin")
	if item_scene.resource_path == "res://scenes/items/baby_mermaid.tscn":
		audio_manager.play_sound("Audio3D_food_Baby")

	item.add_to_group("pickup")
	item.add_to_group(_spawn_group)
	item.global_position = _get_spawn_position()
	item.linear_velocity = Vector3.ZERO
	item.angular_velocity = Vector3.ZERO
	item.sleeping = false

	_apply_spawn_motion(item)


func _get_spawn_position() -> Vector3:
	var angle := _rng.randf_range(0.0, TAU)
	var distance := sqrt(_rng.randf()) * spawn_radius
	var offset := Vector3(
		cos(angle) * distance,
		_rng.randf_range(0.0, spawn_height),
		sin(angle) * distance,
	)

	return spawn_point.global_position + offset


func _apply_spawn_motion(item: RigidBody3D) -> void:
	var horizontal := item.global_position - spawn_point.global_position
	horizontal.y = 0.0

	if horizontal.length_squared() < 0.0001:
		horizontal = Vector3.RIGHT

	var impulse := horizontal.normalized() * launch_impulse
	impulse.y = launch_impulse
	item.apply_central_impulse(impulse)

	var spin := Vector3(
		_rng.randf_range(-spin_impulse, spin_impulse),
		_rng.randf_range(-spin_impulse, spin_impulse),
		_rng.randf_range(-spin_impulse, spin_impulse),
	)
	item.apply_torque_impulse(spin)


func _get_spawned_item_count() -> int:
	var spawned_items := get_tree().get_nodes_in_group(_spawn_group)
	var count := 0

	for node in spawned_items:
		var pickup := node as RigidBody3D
		if pickup == null or not is_instance_valid(pickup):
			continue

		if not pickup.is_in_group("pickup"):
			continue

		count += 1

	return count


func _sync_spawn_timer(initial_delay: bool = false) -> void:
	if item_scene == null:
		timer.stop()
		return

	if _get_spawned_item_count() >= target_count:
		timer.stop()
		return

	if timer.is_stopped():
		timer.wait_time = _get_spawn_wait_time(initial_delay)
		timer.start()


func _get_spawn_wait_time(initial_delay: bool = false) -> float:
	if initial_delay:
		return SPAWN_INTERVAL_MIN

	return _rng.randf_range(SPAWN_INTERVAL_MIN, SPAWN_INTERVAL_MAX)


func _on_cooking_item_consumed(_source: Node, item: RigidBody3D) -> void:
	if item == null or not is_instance_valid(item):
		return

	if not item.is_in_group(_spawn_group):
		return

	_sync_spawn_timer()
