extends Node

export var user_color := Color.lime

var email := "test@test.com"
var password := "password"

onready var server_connection := $ServerConnection
onready var debug_panel := $CanvasLayer/DebugPanel
onready var chat_box := $CanvasLayer/ChatBox
onready var notification_list := $CanvasLayer/NotificationList


func _ready() -> void:
	yield(request_authentication(),"completed")
	yield(connect_to_server(), "completed")
	yield(join_world(), "completed")
	
	var characters := [
		{name = "Jack", color = Color.blue.to_html(false)},
		{name = "Lisa", color= Color.red.to_html(false)}
	]
	
	yield(server_connection.write_characters_async(characters), "completed")
	var characters_data = yield(server_connection.get_characters_async(), "completed")

	var string := ""
	for character in characters_data:
		string += "%s: %s\n" % [character.name, character.color]
	print_debug("from server storage:\n" + string)
	
	yield(server_connection.join_chat_async(), "completed")

func request_authentication() -> void:
	print_debug("authenticating user")
	debug_panel.write_message("Authenticating user %s." % email)
	var result: int = yield(server_connection.authenticate_async(email,password), "completed")
	if result == OK:
		print_debug("authenticating success")
	else:
		print_debug("authenticating failed")
	

func connect_to_server() -> void:
	var result: int = yield(server_connection.connect_to_server_async(), "completed")
	if result == OK:
		print_debug("connected to the server")
	else:
		print_debug("could not connect")

func join_world() -> void:
	var presences: Dictionary = yield(server_connection.join_world_async(), "completed")
	print_debug("joined world")
	print_debug("other connected players: %s" %presences.size())


func _on_ChatBox_text_sent(text) -> void:
	yield(server_connection.send_text_async(text), "completed")


func _on_ServerConnection_chat_message_received(username, text) -> void:
	chat_box.add_reply(text, username, user_color)


func _on_ServerConnection_user_joined(username: String) -> void:
	if email == username:
		return
	notification_list.add_notification(username, user_color)


func _on_ServerConnection_user_left(username: String) -> void:
	notification_list.add_notification(username, user_color, true)
	if email == username:
		return
