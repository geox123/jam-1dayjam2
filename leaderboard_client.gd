class_name LeaderboardClient
extends Node

signal scores_received(scores: Array)
signal score_submitted
signal request_failed(message: String)

var supabase_url := ""
var publishable_key := ""
var access_token := ""
var pending_action := ""
var pending_score := {}


func configure(url: String, key: String) -> void:
	supabase_url = url.trim_suffix("/")
	publishable_key = key


func is_configured() -> bool:
	return not supabase_url.is_empty() and not publishable_key.is_empty()


func load_scores() -> void:
	if not is_configured():
		request_failed.emit("Leaderboard is not configured yet")
		return
	if access_token.is_empty():
		pending_action = "load"
		_authenticate()
		return
	_request("GET", "/functions/v1/leaderboard", "load", "")


func submit_score(player_name: String, score: int, duration: float) -> void:
	if not is_configured():
		request_failed.emit("Leaderboard is not configured yet")
		return
	pending_score = {
		"player_name": player_name.strip_edges().substr(0, 12),
		"score": score,
		"duration": duration,
	}
	if access_token.is_empty():
		pending_action = "submit"
		_authenticate()
		return
	_request("POST", "/functions/v1/leaderboard", "submit", JSON.stringify(pending_score))


func _authenticate() -> void:
	_request("POST", "/auth/v1/signup", "auth", "{}")


func _request(method: String, path: String, action: String, body: String) -> void:
	var request := HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_request_completed.bind(request, action))
	var headers := PackedStringArray([
		"apikey: %s" % publishable_key,
		"Content-Type: application/json",
	])
	if not access_token.is_empty():
		headers.append("Authorization: Bearer %s" % access_token)
	var http_method := HTTPClient.METHOD_GET if method == "GET" else HTTPClient.METHOD_POST
	var error := request.request(supabase_url + path, headers, http_method, body)
	if error != OK:
		request_failed.emit("Could not reach leaderboard")
		request.queue_free()


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest, action: String) -> void:
	request.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		request_failed.emit("Leaderboard request failed (%d)" % response_code)
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if action == "auth":
		if parsed is not Dictionary or not parsed.has("access_token"):
			request_failed.emit("Anonymous leaderboard sign-in failed")
			return
		access_token = str(parsed["access_token"])
		if pending_action == "load":
			pending_action = ""
			load_scores()
		elif pending_action == "submit":
			pending_action = ""
			submit_score(pending_score["player_name"], pending_score["score"], pending_score["duration"])
	elif action == "load":
		if parsed is Array:
			scores_received.emit(parsed)
		else:
			request_failed.emit("Leaderboard returned invalid data")
	elif action == "submit":
		score_submitted.emit()
