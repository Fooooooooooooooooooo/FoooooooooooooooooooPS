# gunsmith_ui.gd
extends CanvasLayer
class_name GunsmithUI

var player = null # 引用玩家实例

# UI 控件引用
var background_panel: Panel = null
var main_rect: ColorRect = null
var title_label: Label = null
var slots_container: VBoxContainer = null
var stats_container: VBoxContainer = null
var popup_rect: ColorRect = null
var popup_container: VBoxContainer = null
var close_button: Button = null

# 预设保存与加载控件
var preset_container: HBoxContainer = null

# 当前打开的插槽类型
var active_slot_name: String = ""

# 颜色常量
const COLOR_BETTER = Color(0.2, 0.9, 0.2) # 绿色加成
const COLOR_WORSE = Color(0.9, 0.2, 0.2)  # 红色减益
const COLOR_NORMAL = Color(0.9, 0.9, 0.9) # 白色不变

func _ready() -> void:
	# 设置全屏覆盖 UI
	layer = 10
	visible = false

	# 暗色半透明全屏背景
	background_panel = Panel.new()
	background_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.05, 0.85)
	background_panel.add_theme_stylebox_override("panel", style)
	add_child(background_panel)

	# 主工作面板
	main_rect = ColorRect.new()
	main_rect.color = Color(0.1, 0.1, 0.1, 0.95)
	main_rect.size = Vector2(850, 520)
	main_rect.anchor_left = 0.5
	main_rect.anchor_top = 0.5
	main_rect.anchor_right = 0.5
	main_rect.anchor_bottom = 0.5
	main_rect.position = -main_rect.size * 0.5
	background_panel.add_child(main_rect)

	# 标题
	title_label = Label.new()
	title_label.text = "🎯 WEAPON CUSTOMIZATION / GUNSMITH (武器改装工坊)"
	title_label.position = Vector2(30, 20)
	title_label.add_theme_font_size_override("font_size", 22)
	main_rect.add_child(title_label)

	# 左侧附件槽位区
	var slots_title = Label.new()
	slots_title.text = "⚙️ ATTACHMENT SLOTS (附件改装槽位)"
	slots_title.position = Vector2(30, 70)
	slots_title.add_theme_font_size_override("font_size", 16)
	main_rect.add_child(slots_title)

	slots_container = VBoxContainer.new()
	slots_container.position = Vector2(30, 100)
	slots_container.size = Vector2(320, 320)
	slots_container.add_theme_constant_override("separation", 8)
	main_rect.add_child(slots_container)

	# 右侧参数性能反馈区
	var stats_title = Label.new()
	stats_title.text = "📊 STATS COMPARISON (实时性能评估)"
	stats_title.position = Vector2(480, 70)
	stats_title.add_theme_font_size_override("font_size", 16)
	main_rect.add_child(stats_title)

	stats_container = VBoxContainer.new()
	stats_container.position = Vector2(480, 100)
	stats_container.size = Vector2(340, 320)
	stats_container.add_theme_constant_override("separation", 6)
	main_rect.add_child(stats_container)

	# 下方预设方案保存加载区
	var preset_title = Label.new()
	preset_title.text = "📁 PRESET SCHEMES (战术配置预设方案)"
	preset_title.position = Vector2(30, 440)
	preset_title.add_theme_font_size_override("font_size", 13)
	main_rect.add_child(preset_title)

	preset_container = HBoxContainer.new()
	preset_container.position = Vector2(30, 465)
	preset_container.size = Vector2(400, 35)
	preset_container.add_theme_constant_override("separation", 10)
	main_rect.add_child(preset_container)
	setup_preset_buttons()

	# 关闭按钮
	close_button = Button.new()
	close_button.text = "💾 SAVE & CLOSE (保存并退出)"
	close_button.size = Vector2(250, 40)
	close_button.position = Vector2(570, 460)
	close_button.pressed.connect(toggle_ui)
	main_rect.add_child(close_button)

	# 选择附件弹出面板 (弹出窗口)
	popup_rect = ColorRect.new()
	popup_rect.color = Color(0.15, 0.15, 0.15, 0.98)
	popup_rect.size = Vector2(400, 360)
	popup_rect.anchor_left = 0.5
	popup_rect.anchor_top = 0.5
	popup_rect.anchor_right = 0.5
	popup_rect.anchor_bottom = 0.5
	popup_rect.position = -popup_rect.size * 0.5
	popup_rect.visible = false
	background_panel.add_child(popup_rect)

	var popup_title = Label.new()
	popup_title.text = "🛠️ SELECT ATTACHMENT (选择附件)"
	popup_title.position = Vector2(20, 15)
	popup_title.add_theme_font_size_override("font_size", 16)
	popup_rect.add_child(popup_title)

	# 滚动列表放置可选附件
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(20, 50)
	scroll.size = Vector2(360, 290)
	popup_rect.add_child(scroll)

	popup_container = VBoxContainer.new()
	popup_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	popup_container.add_theme_constant_override("separation", 8)
	scroll.add_child(popup_container)

func setup_preset_buttons() -> void:
	for i in range(3):
		var preset_id = i + 1
		var save_btn = Button.new()
		save_btn.text = "Save " + str(preset_id)
		save_btn.pressed.connect(save_preset_scheme.bind(preset_id))
		preset_container.add_child(save_btn)

		var load_btn = Button.new()
		load_btn.text = "Load " + str(preset_id)
		load_btn.pressed.connect(load_preset_scheme.bind(preset_id))
		preset_container.add_child(load_btn)

func open_gunsmith(p_player) -> void:
	player = p_player
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	refresh_all()

func toggle_ui() -> void:
	visible = false
	popup_rect.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func refresh_all() -> void:
	if not player:
		return

	var base_weapon = player.weapons[player.current_weapon_index]
	title_label.text = "🎯 WEAPON CUSTOMIZATION - " + base_weapon.name.upper() + " (武器改装工坊)"

	# 刷新改装插槽列表
	for child in slots_container.get_children():
		child.queue_free()

	var current_attachments = player.weapon_customizations.get(base_weapon.name, {})
	var slots = ["sight", "muzzle", "grip", "magazine", "stock"]

	for slot in slots:
		var slot_hb = HBoxContainer.new()
		slot_hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slots_container.add_child(slot_hb)

		# 插槽类型标签
		var label = Label.new()
		label.text = slot.capitalize() + ": "
		label.custom_minimum_size = Vector2(100, 30)
		slot_hb.add_child(label)

		# 装备的附件按钮
		var btn = Button.new()
		var att_id = current_attachments.get(slot, null)
		if att_id and player.ATTACHMENTS.has(att_id):
			btn.text = player.ATTACHMENTS[att_id].name
		else:
			btn.text = "[ Empty / 槽位空置 ]"
		btn.custom_minimum_size = Vector2(200, 30)
		btn.pressed.connect(open_attachment_selector.bind(slot))
		slot_hb.add_child(btn)

	# 刷新性能属性评估
	refresh_stats_panel()

func open_attachment_selector(slot_name: String) -> void:
	active_slot_name = slot_name
	popup_rect.visible = true

	for child in popup_container.get_children():
		child.queue_free()

	# 增加 "None / 卸下" 选项
	var none_btn = Button.new()
	none_btn.text = "❌ None / 卸下该槽位附件"
	none_btn.pressed.connect(select_attachment.bind(null))
	popup_container.add_child(none_btn)

	# 获取玩家附件库中兼容此插槽的所有选项
	for att_id in player.ATTACHMENTS:
		var att = player.ATTACHMENTS[att_id]
		if att.category == slot_name:
			var btn = Button.new()
			btn.text = att.name
			btn.tooltip_text = att.desc
			btn.pressed.connect(select_attachment.bind(att_id))
			popup_container.add_child(btn)

func select_attachment(att_id) -> void:
	if not player:
		return

	var base_weapon = player.weapons[player.current_weapon_index]
	if not player.weapon_customizations.has(base_weapon.name):
		player.weapon_customizations[base_weapon.name] = {
			"sight": null,
			"muzzle": null,
			"grip": null,
			"magazine": null,
			"stock": null
		}

	player.weapon_customizations[base_weapon.name][active_slot_name] = att_id
	popup_rect.visible = false

	# 更新改装和性能
	player.recalculate_current_weapon_customization()
	refresh_all()

func refresh_stats_panel() -> void:
	if not player:
		return

	for child in stats_container.get_children():
		child.queue_free()

	var base_weapon = player.weapons[player.current_weapon_index]
	var current_attachments = player.weapon_customizations.get(base_weapon.name, {})
	var customized_weapon = player.get_modified_weapon(base_weapon, current_attachments)

	# 要对比的所有属性列表
	var stat_keys = [
		{"key": "damage", "name": "Damage (杀伤力)", "lower_is_better": false, "fmt": "%.1f"},
		{"key": "shoot_cooldown", "name": "Fire Interval (射击间隔)", "lower_is_better": true, "fmt": "%.3fs"},
		{"key": "max_ammo", "name": "Magazine Size (弹匣容量)", "lower_is_better": false, "fmt": "%d"},
		{"key": "recoil_vertical", "name": "Vertical Recoil (垂直后坐力)", "lower_is_better": true, "fmt": "%.2f"},
		{"key": "recoil_horizontal", "name": "Horizontal Recoil (水平后坐力)", "lower_is_better": true, "fmt": "%.2f"},
		{"key": "spread", "name": "Spread Angle (基础散布)", "lower_is_better": true, "fmt": "%.4f"},
		{"key": "reload_time", "name": "Reload Time (换弹用时)", "lower_is_better": true, "fmt": "%.2fs"},
		{"key": "ads_time", "name": "ADS Zoom Speed (开镜耗时)", "lower_is_better": true, "fmt": "%.2fs"},
		{"key": "speed_multiplier", "name": "Weapon Weight (携枪速度)", "lower_is_better": false, "fmt": "%.2f"},
	]

	for stat in stat_keys:
		var key = stat.key
		var val_base = base_weapon.get(key, 0.0)
		var val_custom = customized_weapon.get(key, 0.0)

		# 射击间隔要特殊处理，因为手枪RPS比cooldown直观，但由于我们要和表格对齐所以保持cooldown比对
		if key == "shoot_cooldown" and val_base > 0:
			# 可选：我们可以直接比对 cooldown 间隔
			pass

		var hb = HBoxContainer.new()
		stats_container.add_child(hb)

		var name_lbl = Label.new()
		name_lbl.text = stat.name
		name_lbl.custom_minimum_size = Vector2(180, 22)
		hb.add_child(name_lbl)

		var comp_lbl = Label.new()
		var base_str = stat.fmt % val_base
		var cust_str = stat.fmt % val_custom
		comp_lbl.text = base_str + "  ➔  " + cust_str

		# 根据变好变坏赋予颜色
		if abs(val_custom - val_base) < 0.00001:
			comp_lbl.add_theme_color_override("font_color", COLOR_NORMAL)
		else:
			var improved = val_custom > val_base
			if stat.lower_is_better:
				improved = val_custom < val_base

			if improved:
				comp_lbl.add_theme_color_override("font_color", COLOR_BETTER)
				comp_lbl.text += " (▲)"
			else:
				comp_lbl.add_theme_color_override("font_color", COLOR_WORSE)
				comp_lbl.text += " (▼)"

		hb.add_child(comp_lbl)

# ===== 方案保存加载预设实现 (Preserve configs to current session) =====
func save_preset_scheme(preset_id: int) -> void:
	if not player:
		return
	var base_weapon = player.weapons[player.current_weapon_index]
	var current_attachments = player.weapon_customizations.get(base_weapon.name, {}).duplicate(true)

	var save_key = base_weapon.name + "_preset_" + str(preset_id)
	player.weapon_customizations[save_key] = current_attachments
	print("已保存武器 [", base_weapon.name, "] 的改装方案 ", preset_id)
	refresh_all()

func load_preset_scheme(preset_id: int) -> void:
	if not player:
		return
	var base_weapon = player.weapons[player.current_weapon_index]
	var save_key = base_weapon.name + "_preset_" + str(preset_id)
	if player.weapon_customizations.has(save_key):
		player.weapon_customizations[base_weapon.name] = player.weapon_customizations[save_key].duplicate(true)
		player.recalculate_current_weapon_customization()
		print("已加载武器 [", base_weapon.name, "] 的改装方案 ", preset_id)
		refresh_all()
	else:
		print("未找到武器 [", base_weapon.name, "] 的改装方案 ", preset_id)
