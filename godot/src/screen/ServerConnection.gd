extends Node

signal chat_message_received(username, text)
signal user_joined(username)
signal user_left(username)

enum ReadPermissions { NO_READ, OWNER_READ, PUBLIC_READ }
enum WritePermissions { NO_WRITE, OWNER_WRITE }

const KEY := "nakama_godot_demo"

var _session: NakamaSession
var _client := Nakama.create_client(KEY, "127.0.0.1", 7350, "http")
var _socket: NakamaSocket
var _world_id := ""
var _channel_id := ""
var _presences := {}

func authenticate_async(email: String, password: String) -> int:
	var result := OK
	
	var new_session = yield(_client.authenticate_email_async(email, password, null), "completed")
	
	if not new_session.is_exception():
		_session = new_session
	else:
		result = new_session.get_exception().status_code
	
	return result


func connect_to_server_async() -> int:
	_socket = Nakama.create_socket_from(_client)
	var result: NakamaAsyncResult = yield(_socket.connect_async(_session), "completed")
	if not result.is_exception():
		_socket.connect("closed", self, "_on_NakamaSocket_closed")
		_socket.connect("received_channel_message", self, "_on_NakamaSocket_received_channel_message")
		_socket.connect("received_match_presence", self, "_on_NakamaSocket_received_match_presence")
		return OK
	return ERR_CANT_CONNECT

func join_world_async() -> Dictionary:
	var world: NakamaAPI.ApiRpc = yield(_client.rpc_async(_session, "get_world_id", ""), 'completed')
	if not world.is_exception():
		_world_id = world.payload
	var match_join_result: NakamaRTAPI.Match = yield(_socket.join_match_async(_world_id), "completed")
	if match_join_result.is_exception():
		var exception: NakamaException = match_join_result.get_exception()
		printerr("error joining the match: %s - %s" % [exception.status_code, exception.message])
		return
	
	
	for presence in match_join_result.presences:
		_presences[presence.user_id] = presence
	return _presences

func join_chat_async() -> int:
	var chat_join_result: NakamaRTAPI.Channel = yield(
		_socket.join_chat_async("world", NakamaSocket.ChannelType.Room, false, false), "completed"
		)
	if not chat_join_result.is_exception():
		_channel_id = chat_join_result.id
		return OK
	else:
		return ERR_CONNECTION_ERROR

func send_text_async(text: String) -> int:
	if not _socket:
		return ERR_UNAVAILABLE
	if _channel_id == "":
		printerr("cant send text message to chat: _channel_id is missing")
		return ERR_INVALID_DATA
	var result: NakamaRTAPI.ChannelMessageAck =  yield(_socket.write_chat_message_async(_channel_id, {"msg": text}), "completed")
	return ERR_CONNECTION_ERROR if result.is_exception() else OK

func write_characters_async(characters := []) -> void:
	yield(_client.write_storage_objects_async(
		_session,
		[
			NakamaWriteStorageObject.new(
				"player_data",
				"characters",
				ReadPermissions.OWNER_READ,
				WritePermissions.OWNER_WRITE,
				JSON.print({characters = characters}),
				""
			)
		]
	), "completed")

func get_characters_async() -> Array:
	var characters := []
	var storage_objects: NakamaAPI.ApiStorageObjects = yield(_client.read_storage_objects_async(
		_session, [NakamaStorageObjectId.new("player_data", "characters", _session.user_id)]
	), "completed")
	
	if storage_objects.objects:
		var decoded: Array = JSON.parse(storage_objects.objects[0].value).result.characters
		characters = decoded
	
	return characters

func _on_NakamaSocket_closed() -> void:
	_socket = null

func _on_NakamaSocket_received_channel_message(message: NakamaAPI.ApiChannelMessage) -> void:
	if message.code != 0:
		return
	
	var content: Dictionary = JSON.parse(message.content).result
	emit_signal("chat_message_received", message.username, content.msg)

func _on_NakamaSocket_received_match_presence(new_presences: NakamaRTAPI.MatchPresenceEvent) -> void:
	for user in new_presences.leaves:
		_presences.erase(user.user_id)
		emit_signal("user_left", user.username)
	
	for user in new_presences.joins:
		_presences[user.user_id] = user
		emit_signal("user_joined", user.username)
