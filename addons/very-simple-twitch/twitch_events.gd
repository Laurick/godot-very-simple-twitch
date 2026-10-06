@tool
class_name VSTEvents extends Node

signal event_happened(type:String, data:Dictionary)

const USE_MOCK_SERVER := true  # cambia esto para alternar

#const TWITCH_EVENTS_URL := "ws://127.0.0.1:8080/ws"
#const TWITCH_EVENTS_SUBCRIPTIONS := "http://127.0.0.1:8080/eventsub/subscriptions"
const TWITCH_EVENTS_URL = "wss://eventsub.wss.twitch.tv/ws"
const TWITCH_EVENTS_SUBCRIPTIONS = "https://api.twitch.tv/helix/eventsub/subscriptions"

var socket:WebSocketPeer
var session_id:String = ""
var channel_info:VSTChannel
var _client_id:String

var _debug_messages:bool = true

func _ready():
	_client_id = VSTSettings.get_setting(VSTSettings.settings.client_id)
	_connect_to_events_server()

func _process(_delta):
	if !socket:
		return
		
	socket.poll()
	var state = socket.get_ready_state()

	match (state):
		WebSocketPeer.STATE_OPEN:
			while socket.get_available_packet_count():
				_handle_message(socket.get_packet().get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			var code = socket.get_close_code()
			var reason = socket.get_close_reason()
			print('Disconnected twitch events')
			print("WebSocket closed with code: %d, reason %s. Clean: %s" % [code, reason, code != -1])
			print('Reconecting...')
			_connect_to_events_server()

 
func _connect_to_events_server():
	if not socket:
		socket = WebSocketPeer.new()
	socket.connect_to_url(TWITCH_EVENTS_URL)


func _handle_message(raw: String):
	_print_debug_info("message: "+raw)
	var json = JSON.parse_string(raw)
	if json == null:
		return

	var msg_type = json["metadata"]["message_type"]

	match msg_type:
		"session_welcome":
			session_id = json["payload"]["session"]["id"]
			print("Session stablished: ", str(json))
			var events_to_suscribe = VSTSettings.get_setting(VSTSettings.settings.events)
			for event in events_to_suscribe:
				subscribe_to_event(event)

		"notification":
			var type:String = json["metadata"]["subscription_type"]
			var data:Dictionary = json["payload"]["event"]
			event_happened.emit(type, data)

		"session_reconnect":
			var new_url = json["payload"]["session"]["reconnect_url"]
			socket.connect_to_url(new_url)

		"revocation":
			print("Suscripcion revoked: ", json["payload"])


func _get_version_from(type: String) -> String:
	match type:
		"channel.follow": 
			return "2"
		_:
			return "1"


func _get_condition_from(type: String) -> Dictionary:
	match type:
		"channel.follow":
			return {
				"broadcaster_user_id": channel_info.id,
				"moderator_user_id": channel_info.id
			}
		"channel.raid":
			return {
				"to_broadcaster_user_id": channel_info.id
			}
		_:
			return {
				"broadcaster_user_id": channel_info.id
			}


func subscribe_to_event(type:String):
	var vst = VSTNetwork_Call.new()
	vst.to(TWITCH_EVENTS_SUBCRIPTIONS)
	vst.verb(HTTPClient.METHOD_POST)
	vst.with({
		"type": type,
		"version": _get_version_from(type),
		"condition": _get_condition_from(type),
		"transport": {
			"method": "websocket",
			"session_id": session_id
		}
	})
	vst.add_all_headers({
		'Client-Id' : _client_id,
		'Authorization': 'Bearer ' + channel_info.token,
		'Content-Type': 'application/json'
	})

	vst.set_on_call_success(_on_subscription_response)
	vst.set_on_call_fail(_on_subscription_fail)

	vst.launch_request(self)


func _on_subscription_response(body):
	_print_debug_info("Suscription created: %s " % body.get_string_from_utf8())


func _on_subscription_fail(error):
	_print_debug_info("Suscription failed: %s " % str(error))


func _print_debug_info(...messages):
	if _debug_messages:
		for message in messages:
			print(message)
