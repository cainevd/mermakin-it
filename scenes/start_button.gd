extends TextureButton
@onready var audio_manager: AudioStreamPlayer3D = $"../../../AudioManager"


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if texture_pressed:
		audio_manager.play_sound("Audio3D_Button")
