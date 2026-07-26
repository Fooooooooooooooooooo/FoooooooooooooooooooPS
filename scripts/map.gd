extends Node3D

@onready var spawner: MultiplayerSpawner = $PlayerSpawner
@onready var players_node: Node = $Players
@onready var spawn_points_parent: Node = $SpawnPoints

func _ready() -> void:
	print("🌍 MAP _ready() 开始")
	if not spawner:
		printerr("❌ 错误: 缺少 PlayerSpawner")
		return
	print("✅ PlayerSpawner 存在，Spawn Path: ", spawner.spawn_path)
	if not players_node:
		printerr("❌ 错误: 缺少 Players 容器")
		return
	print("✅ Players 容器存在")
	if not spawn_points_parent:
		printerr("⚠️ 警告: 缺少 SpawnPoints")
	else:
		var children = spawn_points_parent.get_children()
		print("✅ SpawnPoints 有 ", children.size(), " 个子节点")

	if NetworkManager.is_server:
		print("🟢 我是主机，生成本地玩家")
		# 修复：延迟一帧确保所有生成点节点已进入树
		await get_tree().process_frame
		spawn_player(multiplayer.get_unique_id())
	else:
		print("🔵 我是客户端，等待主机生成")

	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	print("🌍 MAP _ready() 结束")

func _on_player_connected(id: int) -> void:
	print("📨 收到玩家连接信号: ", id)
	if NetworkManager.is_server:
		print("🟢 主机生成新玩家 ", id)
		spawn_player(id)

func _on_player_disconnected(id: int) -> void:
	print("📨 玩家断开: ", id)
	var player = players_node.get_node_or_null(str(id))
	if player:
		player.queue_free()
		print("🗑️ 已移除玩家 ", id)

func spawn_player(id: int) -> void:
	print("📦 spawn_player 被调用，玩家ID: ", id)
	if not NetworkManager.is_server:
		return

	var spawn_pos = Vector3(0, 2, 0)
	if spawn_points_parent:
		var spawn_points = spawn_points_parent.get_children()
		if spawn_points.size() > 0:
			var chosen = spawn_points[randi() % spawn_points.size()]
			# 修复：安全获取全局位置，若节点不在树中则使用默认值
			if chosen.is_inside_tree():
				spawn_pos = chosen.global_position
			else:
				printerr("⚠️ 生成点节点不在树中，使用默认位置 (0,2,0)")
			print("📍 选择生成点: ", spawn_pos)
		else:
			print("⚠️ SpawnPoints 下没有子节点，使用 (0,2,0)")

	var player_scene = load("res://scenes/player.tscn")
	if not player_scene:
		printerr("❌ 无法加载玩家场景")
		return
	var player = player_scene.instantiate()
	player.name = str(id)
	player.global_position = spawn_pos
	player.set_multiplayer_authority(id)
	players_node.add_child(player)
	print("✅ 手动添加玩家 ", id, " 到场景")
