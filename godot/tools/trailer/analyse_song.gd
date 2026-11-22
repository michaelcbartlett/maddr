extends SceneTree
## Trailer tooling: plays the song through Godot's movie writer and logs per-frame energy (overall + bass) so the
## trailer can be cut on the beat. Run with --write-movie (any throwaway path) --fixed-fps 30.
const SONG := "C:/Users/micha/Downloads/mashed with deep perfection.mp3"
var player: AudioStreamPlayer
var frame := 0
var rows := PackedStringArray()
var length := 0.0

func _initialize() -> void:
	var stream := AudioStreamMP3.new(); stream.data = FileAccess.get_file_as_bytes(SONG)
	length = stream.get_length()
	AudioServer.add_bus_effect(0, AudioEffectSpectrumAnalyzer.new(), 0)
	player = AudioStreamPlayer.new(); player.stream = stream; root.add_child(player)
	print("SONG LENGTH ", length)

func _process(_dt: float) -> bool:
	if frame == 0: player.play()
	var fx: AudioEffectSpectrumAnalyzerInstance = AudioServer.get_bus_effect_instance(0, 0)
	var bass := fx.get_magnitude_for_frequency_range(30, 160).length()
	var mid := fx.get_magnitude_for_frequency_range(160, 2000).length()
	var high := fx.get_magnitude_for_frequency_range(2000, 12000).length()
	rows.append("%d,%.4f,%.6f,%.6f,%.6f" % [frame, frame / 30.0, bass, mid, high])
	frame += 1
	if frame / 30.0 > length + 0.5:
		var f := FileAccess.open("res://test-results/song_energy.csv", FileAccess.WRITE)
		f.store_string("frame,t,bass,mid,high\n" + "\n".join(rows)); f.close()
		print("FRAMES ", frame)
		return true
	return false
