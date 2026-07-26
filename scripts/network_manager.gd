# network_manager.gd
extends Node

const PORT := 42420
const MAX_PLAYERS := 8

signal player_connected(id: int)
signal player_disconnected(id: int)

var is_server := false

func _ready() -> void:
	# 服务器中继转发（节省带宽）
	multiplayer.server_relay = false
	# 当玩家连接/断开时触发信号
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

# ===== 创建主机 =====
func create_host() -> void:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(PORT, MAX_PLAYERS)
	if error != OK:
		print("❌ 创建服务器失败: ", error)
		return
	
	multiplayer.multiplayer_peer = peer
	is_server = true
	print("✅ 服务器已创建，端口: ", PORT)
	_on_peer_connected(1)  # 主机自己的ID通常是1

# ===== 加入游戏 =====
func join_game(ip: String) -> void:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, PORT)
	if error != OK:
		print("❌ 连接失败: ", error)
		return
	
	multiplayer.multiplayer_peer = peer
	is_server = false
	print("✅ 正在连接到: ", ip)

# ===== 连接回调 =====
func _on_peer_connected(id: int) -> void:
	print("👤 玩家 ", id, " 已连接")
	player_connected.emit(id)

func _on_peer_disconnected(id: int) -> void:
	print("👤 玩家 ", id, " 已断开")
	player_disconnected.emit(id)
