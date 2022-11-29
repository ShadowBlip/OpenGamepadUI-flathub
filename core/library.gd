extends Library

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	super()
	print("Flatpak Library loaded")


# Return a list of installed flatpak applications
func get_library_launch_items() -> Array:
	var output: Array = []
	var code = OS.execute("flatpak", ["list", "--app", "--columns=application"], output)
	
	var installed: Array = []
	for out in output:
		var lines: Array = out.split("\n")
		for line in lines:
			if line == "":
				continue
			var appId: String = line
			var library_item: LibraryLaunchItem = LibraryLaunchItem.new()
			library_item.name = appId
			library_item.provider_app_id = appId
			library_item.installed = true
			library_item.command = "/usr/bin/flatpak"
			library_item.args = PackedStringArray([
				"run",
				appId,
			])
			installed.push_back(library_item)

	return installed
