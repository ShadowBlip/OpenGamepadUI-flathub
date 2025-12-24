extends Library

const Flatpak := preload("res://plugins/flathub/core/flatpak.gd")

var icon := load("res://plugins/flathub/docs/icon.png")
var notification_manager := load("res://core/global/notification_manager.tres") as NotificationManager
var flatpak := Flatpak.new()
var flatpak_bin_path := Flatpak.get_bin()
var flatpak_is_installed := Flatpak.is_installed()


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	logger.info("Flatpak Library loaded")
	add_child(flatpak)
	if not flatpak_is_installed:
		var msg := "Flatpak is not currently installed"
		logger.warn(msg)
		var notify := Notification.new(msg)
		notify.icon = icon
		notification_manager.show(notify)


# Return a list of installed flatpak applications
func get_library_launch_items() -> Array[LibraryLaunchItem]:
	if not flatpak_is_installed:
		return []

	logger.debug("Running 'flatpak list'")
	var apps: Dictionary[String, Flatpak.FlatpakApp] = {}
	var user_apps := await flatpak.list()
	for app in user_apps:
		apps[app.name] = app
	var system_apps := await flatpak.list(Flatpak.Context.System)
	for app in system_apps:
		apps[app.name] = app

	var flatpak_bin := flatpak_bin_path
	if flatpak_bin.is_empty():
		flatpak_bin = "/usr/bin/flatpak"

	var installed: Array[LibraryLaunchItem] = []
	for app: Flatpak.FlatpakApp in apps.values():
		var library_item := LibraryLaunchItem.new()
		logger.info("Found Flatpak app: " + app.name)
		var context_arg: String
		if app.context == Flatpak.Context.User:
			context_arg = "--user"
		elif app.context == Flatpak.Context.System:
			context_arg = "--system"
		library_item.name = app.name
		library_item.provider_app_id = app.app_id
		library_item.installed = true
		library_item.command = flatpak_bin
		library_item.args = ["run", context_arg, app.app_id]
		library_item.tags = ["flathub"]
		installed.push_back(library_item)

	logger.debug(installed)
	return installed


## Installs the given library item. This method should be overriden in the 
## child class, if it supports it.
func install(item: LibraryLaunchItem) -> void:
	if not flatpak_is_installed:
		logger.warn("Flatpak is not currently installed. Failed to install app.")
		install_completed.emit(item, false)

	var app_id := item.provider_app_id
	if app_id == "":
		logger.warn("Item does not have a valid flatpak ID: " + item.name)
		install_completed.emit(item, false)
		return
	
	var on_progress := func(_app_id: String, percent_completed: float):
		install_progressed.emit(item, percent_completed)
	flatpak.install_progressed.connect(on_progress)
	
	var err := await flatpak.install(app_id)
	if err != OK:
		logger.warn("Failed to install: " + app_id)
		install_completed.emit(item, false)
		return
	
	install_completed.emit(item, true)
	flatpak.install_progressed.disconnect(on_progress)


## Updates the given library item. This method should be overriden in the 
## child class, if it supports it.
func update(item: LibraryLaunchItem) -> void:
	if not flatpak_is_installed:
		logger.warn("Flatpak is not currently installed. Failed to update app.")
		update_completed.emit(item, false)

	var app_id := item.provider_app_id
	if app_id == "":
		logger.warn("Item does not have a valid flatpak ID: " + item.name)
		update_completed.emit(item, false)
		return
	
	var on_progress := func(_app_id: String, percent_completed: float):
		install_progressed.emit(item, percent_completed)
	flatpak.install_progressed.connect(on_progress)
	
	var err := await flatpak.update(app_id)
	if err != OK:
		logger.warn("Failed to update: " + app_id)
		update_completed.emit(item, false)
		return
	
	update_completed.emit(item, true)
	flatpak.install_progressed.disconnect(on_progress)


## Uninstalls the given library item. This method should be overriden in the 
## child class if it supports it.
func uninstall(item: LibraryLaunchItem) -> void:
	if not flatpak_is_installed:
		logger.warn("Flatpak is not currently installed. Failed to uninstall app.")
		update_completed.emit(item, false)

	var app_id := item.provider_app_id
	if app_id == "":
		logger.warn("Item does not have a valid flatpak ID: " + item.name)
		uninstall_completed.emit(item, false)
		return

	var err := await flatpak.uninstall(app_id)
	if err != OK:
		logger.warn("Failed to uninstall: " + app_id)
		uninstall_completed.emit(item, false)
		return
	
	uninstall_completed.emit(item, true)


func has_update(item: LibraryLaunchItem) -> bool:
	if not flatpak_is_installed:
		return false

	var app_id := item.provider_app_id
	if app_id.is_empty():
		logger.warn("Item does not have a valid flatpak ID: " + item.name)

	var updates := await flatpak.list_updates()
	for app in updates:
		if app.app_id == app_id:
			return true
	return false
