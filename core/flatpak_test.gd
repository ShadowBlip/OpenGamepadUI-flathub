extends Control

const Flatpak := preload("res://plugins/flathub/core/flatpak.gd")

var flatpak := Flatpak.new()

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	#flatpak.system_wide = true
	add_child(flatpak)
	print(await flatpak.list())

	await flatpak.install("org.tuxemon.Tuxemon")
