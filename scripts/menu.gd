# main_menu.gd
extends Control

@onready var ip_input = $VBoxContainer/IPInput
@onready var status_label = $VBoxContainer/StatusLabel

func _ready() -> void:
	# 本地测试默认填 127.0.0.1
	ip_input.text = "127.0.0.1"

func _on_host_button_pressed() -> void:
	print("✅ 创建主机按钮被点击")
	NetworkManager.create_host()
	print("✅ 场景切换前")
	get_tree().change_scene_to_file("res://scenes/map.tscn")

func _on_join_button_pressed() -> void:
	var ip = ip_input.text.strip_edges()
	if ip.is_empty():
		status_label.text = "❌ 请输入IP地址"
		return
	else: status_label.text = "输入IP地址"	
	NetworkManager.join_game(ip)
	get_tree().change_scene_to_file("res://scenes/map.tscn")
