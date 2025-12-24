extends Node

## Should be emitted when a library item is installed
signal install_completed(app_id: String, success: bool)
## Should be emitted when a library item install is progressing
signal install_progressed(app_id: String, percent_completed: float)

## Flatpaks can be installed as a user or system-wide
enum Context {
	User,
	System,
	Other,
}

## Whether or not to operate flatpak commands system-wide or user-wide
var logger := Log.get_logger("Flatpak", Log.LEVEL.INFO)

## Returns true if flatpak is detected on the system
static func is_installed() -> bool:
	var bin := get_bin()
	return not bin.is_empty()


## Get the abolsute path to the flatpak binary
static func get_bin() -> String:
	var output: Array
	if OS.execute("which", ["flatpak"], output) != OK:
		return ""
	if output.is_empty():
		return ""
	var stdout := output[0] as String

	return stdout.strip_edges()


## Ensures that flatpak has a valid installation
func setup(context: Context = Context.User) -> void:
	await _exec(context, ["repair"])
	await _exec(context, ["remote-add", "--if-not-exists", "flathub", "https://flathub.org/repo/flathub.flatpakrepo"])


## Install the given flatpak from flathub
func install(app_id: String, context: Context = Context.User, remote: String = "flathub") -> int:
	return await _install_or_update(app_id, context, remote, "install")


## Update the given flatpak from flathub
func update(app_id: String, context: Context = Context.User, remote: String = "flathub") -> int:
	return await _install_or_update(app_id, context, remote, "update")


## Uninstall the given flatpak
func uninstall(app_id: String, context: Context = Context.User) -> int:
	var out := await _exec(context, ["uninstall", "-y", app_id])
	return out.code


## Install the given flatpak from flathub
func _install_or_update(app_id: String, context: Context = Context.User, remote: String = "flathub", verb: String = "install") -> int:
	var args := [verb, "-y", remote, app_id]
	if context == Context.User:
		args.push_front("--user")
	
	# Create an interactive process so we can track install progress
	logger.debug("Starting interactive process: flatpak " + " ".join(args))
	var proc := Pty.new()
	if proc.exec("flatpak", PackedStringArray(args)) != OK:
		logger.error("Unable to start flatpak as interactive process")
		return ERR_CANT_FORK
	add_child(proc)

	# Look for the percent completed in the output
	var on_line_written := func(line: String):
		line = line.replace("\t", " ")
		var parts := line.split(" ", false)
		for part in parts:
			if not "%" in part:
				continue
			var percent_str := part.replace("%", "")
			if not percent_str.is_valid_float():
				continue
			var percent := percent_str.to_float() / 100
			
			# Fire a signal to indicate install progress
			logger.debug(app_id + " install progress: " + str(percent))
			install_progressed.emit(app_id, percent)
			
		logger.debug("stdout: " + line)
	proc.line_written.connect(on_line_written)

	var result: Array = await proc.finished
	var exit_code := result[0] as int

	install_completed.emit(app_id, exit_code == OK)
	remove_child(proc)

	return exit_code


## List currently installed flatpaks
func list(context: Context = Context.User) -> Array[FlatpakApp]:
	logger.info("Fetching list of installed flatpaks")
	var installed: Array[FlatpakApp] = []
	var out := await _exec(context, ["list", "--app", "--columns=name,application,version"])
	if out.code != OK:
		logger.warn("flatpak list failed with exit code " + str(out.code) + ": " + out.stdout + " " + out.stderr)
		return installed

	var lines: Array = out.stdout.split("\n")
	for line in lines:
		logger.debug("Line: " + line)
		if not line is String:
			continue
		if line == "":
			continue
		var parts: Array = (line as String).split("\t")
		if parts.size() < 2:
			continue
		if parts[1] == "Application ID":
			continue

		var app := FlatpakApp.new()
		app.context = context
		app.name = parts[0]
		app.app_id = parts[1]
		if parts.size() >= 3:
			app.version = parts[2]
		installed.append(app)

	return installed


## Returns a list of Flatpak apps that have an update available
func list_updates(context: Context = Context.User) -> Array[FlatpakApp]:
	logger.info("Fetching available updates")
	var updates: Array[FlatpakApp] = []
	var out := await _exec(context, ["remote-ls", "--updates", "--app", "--columns=name,application,version"])
	if out.code != OK:
		logger.warn("flatpak remote-ls failed with exit code " + str(out.code) + ": " + out.stdout + " " + out.stderr)
		return updates

	var lines: Array = out.stdout.split("\n")
	for line in lines:
		logger.debug("Line: " + line)
		if not line is String:
			continue
		if line == "":
			continue
		var parts: Array = (line as String).split("\t")
		if parts.size() < 2:
			continue
		if parts[1] == "Application ID":
			continue

		var app := FlatpakApp.new()
		app.context = context
		app.name = parts[0]
		app.app_id = parts[1]
		if parts.size() >= 3:
			app.version = parts[2]
		updates.append(app)
	
	return updates


## Executes flatpak with the given arguments
func _exec(context: Context, args: PackedStringArray) -> Command:
	var full_args := []
	if context == Context.User:
		full_args.append("--user")
	full_args.append_array(args)

	logger.debug("Executing command: flatpak " + " ".join(full_args))
	var cmd := Command.create("flatpak", full_args)
	cmd.execute()
	await cmd.finished
	logger.debug("Command exit code: " + str(cmd.code))
	logger.debug("Command output: " + cmd.stdout + " " + cmd.stderr)
	
	return cmd


## A flatpak entry
class FlatpakApp extends RefCounted:
	var name: String
	var app_id: String
	var version: String
	var context: Context
