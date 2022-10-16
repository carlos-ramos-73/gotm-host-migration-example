extends Control


signal failed_to_find_migration_lobby(room_code)
signal failed_to_migrate()
signal found_migration_lobby(lobby)
signal migrated_lobby()

const ALPHANUMBERIC := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
const MIGRATION_TIMER: float = 10.0 # time in seconds to try joining the migration lobby
const PORT: int = 8070

onready var code_label: Label = $CodeLabel
onready var host_button: Button = $HBoxContainer/Host
onready var hosting_label: Label = $HostingLabel
onready var label: Label = $HBoxContainer/Label
onready var join_button: Button = $HBoxContainer/Join
onready var joined_label: Label = $JoinedLabel
onready var code_input: LineEdit = $HBoxContainer/CodeInput
onready var leave_button: Button = $HBoxContainer/Leave

var _migration_info := MigrationInfo.new()
var _old_lobby: GotmLobby = null


func _ready() -> void:
	var config = GotmConfig.new()
#	config.project_key = "" # not needed for this example
	Gotm.initialize(config)
	
	get_tree().connect("network_peer_connected", self, "on_network_peer_connected")
	get_tree().connect("network_peer_disconnected", self, "on_network_peer_disconnected")
	get_tree().connect("connected_to_server", self, "_on_connected_to_server")
	Gotm.connect("lobby_changed", self, "_on_lobby_changed")
	connect("failed_to_find_migration_lobby", self, "_attempt_to_find_migration_host") # keep trying to find migration host
	connect("failed_to_migrate", self, "_on_failed_to_migrate")
	connect("found_migration_lobby", self, "_join_migration_lobby")


func _append_feed(message_to_append: String) -> void:
	var feed: TextEdit = $Feed
	feed.readonly = false
	feed.cursor_set_line(feed.get_line_count())
	feed.insert_text_at_cursor(" " + message_to_append + "\n")
	feed.readonly = true


func _attempt_migration(room_code: String) -> void:
	_migration_info.migration_room_code = room_code
	
	# this client is the next to host migration lobby
	if _migration_info.host_migration_order[0].id == Gotm.user.id:
		_append_feed("Attempting to host migration lobby...")
		Gotm.host_lobby(false)
		Gotm.lobby.hidden = false
		Gotm.lobby.set_property("room_code", room_code)
		Gotm.lobby.set_filterable("room_code")
	
	else:
		# add migration host count down timer (know when to give up joining lobby)
		var timer := Timer.new()
		timer.name = "MigrationTimer"
		timer.wait_time = MIGRATION_TIMER
		timer.autostart = true
		timer.connect("timeout", self, "_on_migration_timer_timeout")
		add_child(timer)
		_attempt_to_find_migration_host(room_code)


func _attempt_to_find_migration_host(room_code: String) -> void:
	var timer = get_node_or_null("MigrationTimer")
	if timer == null:
		emit_signal("failed_to_migrate")
		return
	
	_append_feed("Attempting to find host...")
	var fetch := GotmLobbyFetch.new()
	fetch.filter_properties.room_code = room_code
	var find_lobby: Array = yield(fetch.first(1), "completed")
	if find_lobby.empty():
		emit_signal("failed_to_find_migration_lobby", room_code)
	else:
		_append_feed("Found migration host in " + str(MIGRATION_TIMER - timer.time_left) + " seconds")
		emit_signal("found_migration_lobby", find_lobby[0])


func _on_CodeInput_text_changed(new_text: String) -> void:
	if new_text.empty():
		join_button.disabled = true
	else:
		join_button.disabled = false


func _on_connected_to_server() -> void:
	_append_feed("Enet: Connected to server")


func _on_failed_to_migrate() -> void:
	_append_feed("Error: Failed to Migrate")
	_append_feed("------------------------------------------------")
	_migration_info = MigrationInfo.new()
	
	code_label.visible = false
	host_button.disabled = false
	host_button.visible = true
	hosting_label.visible = false
	label.visible = true
	join_button.disabled = true
	join_button.visible = true
	joined_label.visible = false
	leave_button.disabled = true
	leave_button.visible = false
	code_input.editable = true
	code_input.text = ""
	code_input.visible = true


func _on_Host_pressed() -> void:
	host_button.disabled = true
	join_button.disabled = true
	leave_button.disabled = true
	leave_button.visible = false
	code_input.editable = false
	code_input.text = ""
	
	var code := ""
	randomize()
	for _i in range(4):
		code += ALPHANUMBERIC[randi() % ALPHANUMBERIC.length()]
	code = code.to_upper()
	
	Gotm.host_lobby(false)
	Gotm.lobby.hidden = false
	Gotm.lobby.set_property("room_code", code)
	Gotm.lobby.set_filterable("room_code")


func _on_Join_pressed() -> void:
	if code_input.text.empty():
		return
	host_button.disabled = true
	join_button.disabled = true
	leave_button.disabled = true
	leave_button.visible = false
	code_input.editable = false
	
	var code := code_input.text.to_upper()
	_append_feed("Finding lobby with code " + code)

	var fetch = GotmLobbyFetch.new()
	fetch.filter_properties.room_code = code
	var found_lobby: Array = yield(fetch.first(1), "completed")
	if found_lobby.empty():
		_append_feed("Error: Could not find lobby with code " + code)
		host_button.disabled = false
		join_button.disabled = false
		leave_button.disabled = true
		leave_button.visible = false
		code_input.editable = true
		code_input.text = ""
		return
	
	# found lobby, now join
	var success: bool = yield((found_lobby[0] as GotmLobby).join(), "completed")
	if !success:
		_append_feed("Error: Found lobby with code " + code + " but could not join it")
		host_button.disabled = false
		join_button.disabled = false
		leave_button.disabled = true
		leave_button.visible = false
		code_input.editable = true
		code_input.text = ""
		return


func _join_migration_lobby(lobby: GotmLobby) -> void:
	var success: bool = yield(lobby.join(), "completed")
	if !success:
		_append_feed("Error: Found migration lobby with code " + lobby.get_property("room_code") + " but could not join it")
		emit_signal("failed_to_migrate")
		return
	_append_feed("Migrated lobby successfully")
	emit_signal("migrated_lobby")


func _on_Leave_pressed():
	Gotm.lobby.leave()


func _on_lobby_changed() -> void:
	var old_lobby: GotmLobby = _old_lobby
	_old_lobby = Gotm.lobby
	
	if Gotm.lobby != null:
		Gotm.lobby.connect("peer_joined", self, "_on_peer_joined")
		Gotm.lobby.connect("peer_left", self, "_on_peer_left")
	
	if old_lobby != null and Gotm.lobby == null:
		# just left lobby
		_append_feed("Leaving lobby")
		_append_feed("Enet: Clearing Connection")
		_append_feed("------------------------------------------------")
		(get_tree().network_peer as NetworkedMultiplayerENet).close_connection()
		
		if _migration_info._did_host_leave == true:
			_append_feed("Attempting Migration...")
			_attempt_migration(old_lobby.get_property("room_code"))
			return
		
		code_label.visible = false
		host_button.disabled = false
		host_button.visible = true
		hosting_label.visible = false
		label.visible = true
		join_button.disabled = true
		join_button.visible = true
		joined_label.visible = false
		leave_button.disabled = true
		leave_button.visible = false
		code_input.editable = true
		code_input.text = ""
		code_input.visible = true
		return
	
	
	if old_lobby == null and Gotm.lobby != null and !Gotm.lobby.is_host():
		# just joined lobby
		_append_feed("Lobby joined")
		_append_feed("Enet: Clearing Connection")
		(get_tree().network_peer as NetworkedMultiplayerENet).close_connection()
		var client := NetworkedMultiplayerENet.new()
		client.create_client(Gotm.lobby.host.address, PORT)
		get_tree().network_peer = client
		_append_feed("Enet: Established Client")
		
		code_label.visible = false
		host_button.disabled = true
		host_button.visible = false
		hosting_label.visible = false
		label.visible = false
		join_button.disabled = true
		join_button.visible = false
		joined_label.visible = true
		leave_button.disabled = false
		leave_button.visible = true
		code_input.editable = false
		code_input.text = ""
		code_input.visible = false
		return
	
	if Gotm.lobby != null and Gotm.lobby.is_host():
		# just hosted lobby
		_append_feed("Hosting lobby with code " + Gotm.lobby.get_property("room_code"))
		_append_feed("Enet: Clearing Connection")
		(get_tree().network_peer as NetworkedMultiplayerENet).close_connection()
		var server := NetworkedMultiplayerENet.new()
		server.create_server(PORT)
		get_tree().network_peer = server
		_append_feed("Enet: Established Server")
		
		_migration_info = MigrationInfo.new()
		
		code_label.text = Gotm.lobby.get_property("room_code")
		code_label.visible = true
		host_button.disabled = true
		host_button.visible = false
		hosting_label.visible = true
		label.visible = false
		join_button.disabled = true
		join_button.visible = false
		joined_label.visible = false
		leave_button.disabled = false
		leave_button.visible = true
		code_input.editable = false
		code_input.text = ""
		code_input.visible = false
		return


func _on_migration_timer_timeout() -> void:
	get_node("MigrationTimer").queue_free()


func on_network_peer_connected(id: int) -> void:
	if Gotm.lobby != null and Gotm.lobby.is_host():
		rpc_id(id, "_request_user_info")


func on_network_peer_disconnected(id: int) -> void:
	_migration_info.remove_player(id)
	_append_feed("Updated migration info: Removed Player")


func _on_peer_joined(user: GotmUser) -> void:
	_append_feed(user.display_name + " joined")


func _on_peer_left(user: GotmUser) -> void:
	_append_feed(user.display_name + " left")
	if user.id == _old_lobby.host.id:
		_migration_info._did_host_leave = true


master func _receive_user_info(user_str: String) -> void:
	var user: GotmUser = str2var(user_str)
	_migration_info.add_player(get_tree().get_rpc_sender_id(), user)
	_append_feed("Updated migration info: Added Player")
	rpc("_send_migration_info", var2str(_migration_info))


puppet func _request_user_info() -> void:
	rpc_id(get_tree().get_rpc_sender_id(), "_receive_user_info", var2str(Gotm.user))


puppet func _send_migration_info(migration_info: String) -> void:
	_migration_info = str2var(migration_info)
	_append_feed("Updated migration info from host")
