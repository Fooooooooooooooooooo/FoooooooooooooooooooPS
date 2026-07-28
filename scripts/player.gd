extends CharacterBody3D

# ===== 射击模式枚举 =====
enum FireMode { SEMI_AUTO, BURST, FULL_AUTO }

## ===== 移动参数 =====
@export var walk_speed: float = 5.0
@export var jump_velocity: float = 6.0
@export var gravity: float = 22.0
@export var mouse_sensitivity: float = 0.002
@export var recoil_multiplier: float = 3.0
@export var hp_bar_max_width: float = 0.0
## ===== 侧瞄过渡速度 =====
@export var side_transition_speed: float = 10.0

## ===== 探头参数 =====
@export var lean_offset: float = 0.2
@export var lean_transition_speed: float = 12.0

## ===== 武器数据 =====
var weapons: Array[Dictionary] = []

var current_weapon_index: int = 0

## ===== 新增变量 (枪械与手感系统) =====
var is_crouching: bool = false
var is_sprinting: bool = false
var jump_penalty_timer: float = 0.0

var shot_count: int = 0
var recoil_peak: float = 0.0
var recovery_delay_timer: float = 0.0

var breath_time: float = 0.0
var breath_offset: Vector3 = Vector3.ZERO

var ads_progress: float = 0.0
var is_ads_transitioning: bool = false

var is_switching: bool = false
var switch_progress: float = 0.0
var switch_duration: float = 0.3

var burst_counter: int = 0
var burst_timer: float = 0.0

var hit_marker_timer: float = 0.0
var damage_flash_timer: float = 0.0

var hit_marker_ui = null
var damage_flash_ui = null

## ===== 节点引用 =====
@onready var camera: Camera3D = $Camera3D
@onready var weapon_pivot: Node3D = $Camera3D/WeaponPivot
@onready var hprect: ColorRect = $CanvasLayer/hpRect
@onready var bulletlabel: Label = $CanvasLayer/bulletLabel
@onready var hplabel: Label = $CanvasLayer/hpLabel

## ===== 动画与抖动 =====
@onready var weapon_animator: AnimationPlayer = $Camera3D/WeaponPivot/Vector/AnimationPlayer
var is_playing_reload: bool = false
var target_jitter: Vector3 = Vector3.ZERO
var current_jitter: Vector3 = Vector3.ZERO
var jitter_speed: float = 12.0

## ===== 状态变量 =====
var current_ammo: int
var reserve_ammo: int
var is_reloading: bool = false
var can_shoot: bool = true
var is_aiming: bool = false
var current_speed: float
var player_id: int = 0
var is_local_player: bool = false

# 血量与生存状态（移除 @export，防止被外部覆盖）
var current_health: float = 100.0
var max_health: float = 100.0
var is_dead: bool = false

## ===== 侧瞄状态 =====
var is_side_aiming: bool = false
var current_side_position: Vector3 = Vector3.ZERO
var target_side_position: Vector3 = Vector3.ZERO
var current_side_rotation: Vector3 = Vector3.ZERO
var target_side_rotation: Vector3 = Vector3.ZERO

## ===== 探头状态 =====
var target_lean: float = 0.0
var current_lean: float = 0.0

## ===== 视角控制 =====
var player_yaw: float = 0.0
var camera_pitch: float = 0.0
var recoil_pitch_offset: float = 0.0
var recoil_yaw_offset: float = 0.0

## ===== 武器视觉插值 =====
var current_position_offset: Vector3 = Vector3.ZERO
var current_rotation_offset: Vector3 = Vector3.ZERO
var target_position_offset: Vector3 = Vector3.ZERO
var target_rotation_offset: Vector3 = Vector3.ZERO

## ===== FOV 插值 =====
var current_fov: float = 75.0
var target_fov: float = 75.0
@export var fov_transition_speed: float = 8.0

## ===== 相机基础位置 =====
var camera_base_position: Vector3 = Vector3(0, 1.5, 0)
var target_camera_height: float = 1.5
@export var camera_height_transition_speed: float = 18.0


## ===== 滑铲相关 =====
var is_sliding: bool = false
var slide_timer: float = 0.0
var slide_duration: float = 1.6
var slide_speed: float = 50.0
var slide_friction: float = 0.99
var slide_cooldown: float = 0.0
var slide_cooldown_duration: float = 0.0
var normal_camera_height: float = 1.5
var slide_camera_height: float = 0.8
var slide_pending: bool = false

var shoot_timer: float = 0.0
var reload_timer: Timer = null

# ===== 手动同步变量 =====
var sync_timer: float = 0.0
var sync_interval: float = 0.05  # 20 Hz
var last_sent_position: Vector3 = Vector3.ZERO
var last_sent_rotation: float = 0.0
var last_sent_pitch: float = 0.0


# =========================================================================
#  网络初始化
# =========================================================================
func _enter_tree() -> void:
	player_id = int(str(name))
	is_local_player = multiplayer.get_unique_id() == player_id
	set_multiplayer_authority(player_id)

	current_health = max_health
	is_dead = false


func _ready() -> void:
	# 动态程序化生成 53 把世界名枪
	weapons = generate_all_weapons()

	current_health = max_health
	is_dead = false

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if not is_local_player:
		camera.current = false
		set_process_input(false)
	else:
		camera.current = true

	initialize_weapon(current_weapon_index)
	player_yaw = rotation.y
	camera_pitch = camera.rotation.x

	add_to_group("players")

	if not weapon_animator:
		printerr("⚠️ 武器动画播放器未找到")

	slide_speed = walk_speed * 1.6
	target_camera_height = normal_camera_height
	camera_base_position.y = normal_camera_height

	# ===== 修复血量条宽度 =====
	hp_bar_max_width = 280.0
	# 固定锚点避免被父容器影响
	hprect.anchor_left = 0.0
	hprect.anchor_right = 0.0
	if hplabel:
		hplabel.clip_text = false

	if not is_local_player:
		if has_node("CanvasLayer"):
			$CanvasLayer.visible = false
	else:
		setup_aim_line()
		setup_feedback_ui()

	print("[玩家 ", player_id, "] 准备就绪，血量: ", current_health)
	_update_ui()  # 初始化 UI


func get_current_weapon() -> Dictionary:
	return weapons[current_weapon_index]


func initialize_weapon(index: int) -> void:
	if index < 0 or index >= weapons.size():
		return

	var weapon: Dictionary = weapons[index]
	current_ammo = weapon.max_ammo
	reserve_ammo = weapon.max_reserve_ammo

	is_reloading = false
	is_playing_reload = false
	can_shoot = true
	shoot_timer = 0.0

	if reload_timer:
		reload_timer.stop()
		reload_timer.queue_free()
		reload_timer = null

	current_fov = weapon.normal_fov
	target_fov = weapon.normal_fov
	camera.fov = current_fov

	target_position_offset = weapon.normal_position_offset
	target_rotation_offset = weapon.normal_rotation_offset
	current_position_offset = target_position_offset
	current_rotation_offset = target_rotation_offset

	is_side_aiming = false
	target_side_position = Vector3.ZERO
	target_side_rotation = Vector3.ZERO
	current_side_position = Vector3.ZERO
	current_side_rotation = Vector3.ZERO
	target_lean = 0.0
	current_lean = 0.0

	apply_weapon_offset()
	play_weapon_animation("idle")


func play_weapon_animation(anim_name: String) -> void:
	if weapon_animator and weapon_animator.has_animation(anim_name):
		if is_playing_reload and anim_name != "reload":
			weapon_animator.stop()
			is_playing_reload = false
		weapon_animator.play(anim_name)


# =========================================================================
#  UI 更新函数（独立抽取，便于调用）
# =========================================================================
func _update_ui() -> void:
	if not is_local_player:
		return
	if hprect and hplabel:
		var display_health = clamp(current_health, 0, max_health)
		# 颜色逻辑保持不变
		if display_health < max_health / 3:
			hprect.color = Color.RED
		elif display_health < max_health / 3 * 2:
			hprect.color = Color.ORANGE
		else:
			hprect.color = Color.GREEN
		hplabel.text = str(display_health) + " / " + str(max_health)
		# 使用存储的最大宽度
		hprect.size.x = display_health / max_health * hp_bar_max_width
		print("[UI 调试] hprect.size.x 变化为: ", hprect.size.x)

	if bulletlabel:
		if reserve_ammo < 0:
			bulletlabel.text = str(current_ammo) + " / ∞"
		else:
			bulletlabel.text = str(current_ammo) + " / " + str(reserve_ammo)


# =========================================================================
#  物理更新
# =========================================================================
func _physics_process(delta: float) -> void:
	# 物理帧计时器衰减
	if jump_penalty_timer > 0:
		jump_penalty_timer -= delta
	if hit_marker_timer > 0:
		hit_marker_timer -= delta
	if damage_flash_timer > 0:
		damage_flash_timer -= delta

	# 权威端钳制血量
	if is_multiplayer_authority():
		current_health = clamp(current_health, 0, max_health)
		if current_health <= 0 and not is_dead:
			die()

	if is_local_player:
		if not is_dead:
			# 实时更新蹲下和冲刺状态变量
			is_sprinting = Input.is_key_pressed(KEY_SHIFT) and velocity.length() > 0.5 and is_on_floor()
			is_crouching = (Input.is_key_pressed(KEY_CTRL) or is_sliding) and is_on_floor()
			handle_movement(delta)
		else:
			is_sprinting = false
			is_crouching = false
			velocity = Vector3.ZERO
			move_and_slide()
	else:
		player_yaw = rotation.y
		camera_pitch = camera.rotation.x

	# 呼吸晃动更新
	update_breath(delta)

	# 瞄准过渡系统 (ADS)
	update_ads(delta)

	update_side_aim(delta)
	update_lean(delta)
	update_camera_height(delta)

	# 应用相机位置（整合了侧瞄、探头、高度与呼吸晃动）
	apply_camera_position()

	# 瞄准线更新
	if is_local_player:
		update_aim_line(delta)

	if is_local_player and not is_dead:
		if slide_pending and is_on_floor() and not is_sliding and slide_cooldown <= 0:
			start_slide()
			slide_pending = false

		if shoot_timer > 0:
			shoot_timer -= delta
		else:
			can_shoot = true

		if Input.is_action_just_pressed("reload") and not is_reloading and current_ammo < get_current_weapon().max_ammo and (reserve_ammo > 0 or reserve_ammo < 0):
			start_reload.rpc()
		if current_ammo == 0 and (reserve_ammo > 0 or reserve_ammo < 0) and not is_reloading:
			start_reload.rpc()

	# 后坐力延迟恢复
	update_recoil_recovery(delta)
	# 武器切换更新
	update_weapon_switch(delta)

	apply_view(delta)
	update_weapon_offset(delta)
	update_fov(delta)
	update_jitter(delta)

	if slide_cooldown > 0:
		slide_cooldown -= delta

	if is_local_player and not is_dead:
		sync_timer += delta
		if sync_timer >= sync_interval:
			sync_timer = 0.0
			var pos = global_position
			var rot = rotation.y
			var pitch = camera_pitch
			if pos.distance_to(last_sent_position) > 0.1 or abs(rot - last_sent_rotation) > 0.01 or abs(pitch - last_sent_pitch) > 0.01:
				last_sent_position = pos
				last_sent_rotation = rot
				last_sent_pitch = pitch
				rpc("update_transform", pos, rot, pitch)


func handle_movement(delta: float) -> void:
	if is_dead:
		return

	if is_sliding:
		if Input.is_action_just_pressed("jump") and is_on_floor():
			end_slide()
			velocity.y = jump_velocity
			_on_jump()
			move_and_slide()
			return

		var horizontal_vel = Vector2(velocity.x, velocity.z)
		var speed = horizontal_vel.length()
		if speed > 0.1:
			var dir = horizontal_vel.normalized()
			speed *= slide_friction
			velocity.x = dir.x * speed
			velocity.z = dir.y * speed
		else:
			velocity.x = 0
			velocity.z = 0
			end_slide()
			return

		if not is_on_floor():
			velocity.y -= gravity * delta
			end_slide()
			return

		slide_timer -= delta
		if slide_timer <= 0:
			end_slide()
			return

		move_and_slide()
		return

	var input_dir: Vector2 = Input.get_vector("right", "left", "backward", "forward")
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	var weapon = get_current_weapon()
	var target_speed: float = walk_speed * weapon.get("speed_multiplier", 1.0)
	if is_aiming:
		target_speed *= weapon.aim_speed_multiplier

	current_speed = target_speed

	if direction:
		velocity.x = move_toward(velocity.x, direction.x * target_speed, target_speed * delta * 20.0)
		velocity.z = move_toward(velocity.z, direction.z * target_speed, target_speed * delta * 20.0)
	else:
		velocity.x = move_toward(velocity.x, 0.0, target_speed * delta * 20.0)
		velocity.z = move_toward(velocity.z, 0.0, target_speed * delta * 20.0)

	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_sliding:
		velocity.y = jump_velocity
		_on_jump()

	if not is_on_floor():
		velocity.y -= gravity * delta

	move_and_slide()
	update_movement_animation()


func update_movement_animation() -> void:
	if is_dead or is_reloading or is_playing_reload:
		return
	var is_moving = velocity.length() > 0.5 and is_on_floor()
	if is_moving:
		play_weapon_animation("walk")
	else:
		play_weapon_animation("idle")


func update_camera_height(delta: float) -> void:
	camera_base_position.y = lerp(camera_base_position.y, target_camera_height, 1.0 - exp(-camera_height_transition_speed * delta))


func update_jitter(delta: float) -> void:
	if is_dead:
		current_jitter = Vector3.ZERO
		return
	var is_moving = velocity.length() > 0.5 and is_on_floor()
	var is_jumping = not is_on_floor()
	var target = Vector3.ZERO
	var aim_mult = get_current_weapon().get("aim_jitter_multiplier", 0.5)

	if is_moving:
		target.y = sin(Time.get_ticks_msec() * 0.01) * 0.006
		target.x = sin(Time.get_ticks_msec() * 0.015) * 0.001
		target.z = cos(Time.get_ticks_msec() * 0.012) * 0.001
	elif is_jumping:
		target.y = 0.04
		target.x = randf_range(-0.003, 0.003)
		target.z = randf_range(-0.003, 0.003)
	else:
		target = Vector3.ZERO

	if is_aiming:
		target *= aim_mult

	target_jitter = target
	current_jitter = current_jitter.lerp(target_jitter, jitter_speed * delta)


func update_aiming(delta: float) -> void:
	var aiming_now: bool = Input.is_action_pressed("aim") if is_local_player and not is_dead else is_aiming
	var weapon: Dictionary = get_current_weapon()

	if aiming_now and not is_aiming:
		is_aiming = true
		target_fov = weapon.aim_fov
		target_position_offset = weapon.aim_position_offset
		target_rotation_offset = weapon.aim_rotation_offset
	elif not aiming_now and is_aiming:
		is_aiming = false
		target_fov = weapon.normal_fov
		target_position_offset = weapon.normal_position_offset
		target_rotation_offset = weapon.normal_rotation_offset
		# Reset side aim state when aiming is released
		is_side_aiming = false
		target_side_position = Vector3.ZERO
		target_side_rotation = Vector3.ZERO


func update_side_aim(delta: float) -> void:
	var speed: float = side_transition_speed
	current_side_position = current_side_position.lerp(target_side_position, 1.0 - exp(-speed * delta))
	current_side_rotation = current_side_rotation.lerp(target_side_rotation, 1.0 - exp(-speed * delta))


func update_lean(delta: float) -> void:
	current_lean = lerp(current_lean, target_lean, 1.0 - exp(-lean_transition_speed * delta))
	if is_local_player:
		camera.position.x = camera_base_position.x + current_lean
		camera.position.y = camera_base_position.y
		camera.position.z = camera_base_position.z


func update_fov(delta: float) -> void:
	current_fov = lerp(current_fov, target_fov, 1.0 - exp(-fov_transition_speed * delta))
	camera.fov = current_fov


func apply_view(delta: float) -> void:
	var weapon: Dictionary = get_current_weapon()
	recoil_pitch_offset = move_toward(recoil_pitch_offset, 0.0, weapon.recoil_recovery_speed * delta)
	recoil_yaw_offset = move_toward(recoil_yaw_offset, 0.0, weapon.recoil_recovery_speed * delta * 0.7)

	rotation.y = player_yaw + recoil_yaw_offset
	camera.rotation.x = camera_pitch + recoil_pitch_offset
	camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))


func update_weapon_offset(delta: float) -> void:
	var weapon: Dictionary = get_current_weapon()
	var speed: float = weapon.transition_speed

	current_position_offset = current_position_offset.lerp(target_position_offset, speed * delta)
	current_rotation_offset = current_rotation_offset.lerp(target_rotation_offset, speed * delta)

	apply_weapon_offset()


func apply_weapon_offset() -> void:
	if weapon_pivot:
		var final_pos = current_position_offset + current_side_position + current_jitter
		var final_rot = current_rotation_offset + current_side_rotation
		weapon_pivot.position = final_pos
		weapon_pivot.rotation = final_rot


# =========================================================================
#  输入处理
# =========================================================================
func _input(event: InputEvent) -> void:
	if not is_local_player or is_dead:
		return

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var sensitivity: float = mouse_sensitivity
		if is_aiming:
			sensitivity *= get_current_weapon().aim_sensitivity_multiplier

		player_yaw -= event.relative.x * sensitivity
		camera_pitch -= event.relative.y * sensitivity
		camera_pitch = clamp(camera_pitch, deg_to_rad(-89.0), deg_to_rad(89.0))

	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# 切换射击模式快捷键
	if event is InputEventKey and event.pressed and event.keycode == KEY_B:
		toggle_fire_mode()

	# 切换武器快捷键
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_1:
			start_weapon_switch(0)
		elif event.keycode == KEY_2:
			start_weapon_switch(1)

	# 鼠标滚轮切换武器 (循环切枪，轻松体验所有 53 把世界名枪！)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			var next_index = (current_weapon_index - 1 + weapons.size()) % weapons.size()
			start_weapon_switch(next_index)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var next_index = (current_weapon_index + 1) % weapons.size()
			start_weapon_switch(next_index)


# =========================================================================
#  手动同步 RPC
# =========================================================================
@rpc("authority", "call_remote", "unreliable")
func update_transform(new_pos: Vector3, new_rot_y: float, new_pitch: float) -> void:
	if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	global_position = new_pos
	rotation.y = new_rot_y
	player_yaw = new_rot_y
	camera_pitch = new_pitch
	if has_node("Camera3D"):
		$Camera3D.rotation.x = new_pitch


# =========================================================================
#  血量同步 RPC
# =========================================================================
@rpc("authority", "call_remote", "reliable")
func sync_health(new_health: float) -> void:
	if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	if is_local_player:
		return
	current_health = new_health
	_update_ui()  # 立即刷新 UI


# =========================================================================
#  RPC 射击与换弹
# =========================================================================
@rpc("any_peer", "call_local")
func shoot() -> void:
	if multiplayer.get_remote_sender_id() != 0 and multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	if is_dead or current_ammo <= 0 or is_reloading or not can_shoot:
		return

	if is_multiplayer_authority():
		current_ammo -= 1
		can_shoot = false
		shoot_timer = get_current_weapon().shoot_cooldown

		var weapon: Dictionary = get_current_weapon()
		var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		var cam_global: Transform3D = camera.global_transform
		var origin: Vector3 = cam_global.origin
		
		# 支持散弹枪多弹丸射击 (Shotgun Pellets)
		var pellet_count = weapon.get("pellet_count", 1)
		for p in range(pellet_count):
			var spread_angle: float = calculate_spread()
			var rand_h: float = randf_range(-spread_angle, spread_angle)
			var rand_v: float = randf_range(-spread_angle, spread_angle)
			var local_dir: Vector3 = Vector3(rand_h, rand_v, -1.0).normalized()
			var global_dir: Vector3 = cam_global.basis * local_dir
			var end: Vector3 = origin + global_dir * weapon.shoot_range

			var query := PhysicsRayQueryParameters3D.create(origin, end)
			query.collision_mask = 1
			query.exclude = [self.get_rid()]
			var result: Dictionary = space_state.intersect_ray(query)

			# 子弹拖尾与击中效果 (authority/local)
			if result:
				var hit: Object = result.collider
				create_bullet_trail(origin, result.position)
				create_bullet_impact(result.position, result.normal)
				if hit.is_in_group("players") and hit != self:
					hit.take_damage.rpc_id(hit.get_multiplayer_authority(), weapon.damage, player_id)
					if is_local_player:
						show_hit_marker()
			else:
				create_bullet_trail(origin, end)

		# 应用后坐力模式
		apply_recoil()

	# 播放音效与动画
	play_shot_sound()
	play_weapon_animation("shoot")

	if is_multiplayer_authority() and current_ammo == 0 and (reserve_ammo > 0 or reserve_ammo < 0) and not is_reloading:
		start_reload.rpc()


@rpc("any_peer", "call_local")
func start_reload() -> void:
	if is_dead or is_reloading:
		return

	is_playing_reload = true
	play_weapon_animation("reload")

	if not is_multiplayer_authority():
		return

	is_reloading = true
	var weapon: Dictionary = get_current_weapon()

	if reload_timer:
		reload_timer.stop()
		reload_timer.queue_free()
		reload_timer = null

	reload_timer = Timer.new()
	reload_timer.one_shot = true
	reload_timer.wait_time = weapon.reload_time
	reload_timer.timeout.connect(_on_reload_timeout)
	add_child(reload_timer)
	reload_timer.start()


@rpc("any_peer", "call_local")
func finish_reload() -> void:
	if is_dead or not is_reloading:
		return

	if is_multiplayer_authority():
		var weapon: Dictionary = get_current_weapon()
		var needed: int = weapon.max_ammo - current_ammo
		if reserve_ammo < 0:
			current_ammo = weapon.max_ammo
		else:
			var to_add: int = min(needed, reserve_ammo)
			current_ammo += to_add
			reserve_ammo -= to_add

	is_reloading = false
	is_playing_reload = false
	reload_timer = null
	update_movement_animation()


func _on_reload_timeout() -> void:
	finish_reload.rpc()


# =========================================================================
#  伤害与死亡系统
# =========================================================================
@rpc("any_peer", "call_local", "reliable")
func take_damage(amount: float, attacker_id: int) -> void:
	if is_dead or current_health <= 0:
		return

	current_health = max(0, current_health - amount)
	print("[玩家 ", player_id, "] 受到 ", amount, " 点伤害，剩余血量: ", current_health)

	# 权威端广播血量
	if is_multiplayer_authority():
		rpc("sync_health", current_health)

	_update_ui()  # 自己立即更新 UI

	# 命中反馈：受伤时屏幕闪烁
	if is_local_player:
		show_damage_flash(clamp(amount / 20.0, 0.2, 1.0))

	if current_health <= 0 and not is_dead:
		die()


func die() -> void:
	if is_dead or not is_multiplayer_authority():
		return

	is_dead = true
	current_health = 0
	print("[玩家 ", player_id, "] 死亡")

	is_reloading = false
	is_playing_reload = false
	can_shoot = false
	shoot_timer = 0.0
	if is_sliding:
		end_slide()
		is_sliding = false
	slide_pending = false

	if reload_timer:
		reload_timer.stop()
		reload_timer.queue_free()
		reload_timer = null

	velocity = Vector3.ZERO
	play_weapon_animation("idle")
	_update_ui()  # 更新 UI 为 0

	_respawn()


func _respawn() -> void:
	await get_tree().create_timer(2.0).timeout
	if not is_inside_tree() or not is_dead:
		return

	current_health = max_health
	is_dead = false
	can_shoot = true
	is_reloading = false
	is_playing_reload = false

	var spawn_nodes = get_tree().get_nodes_in_group("spawn_points")
	if spawn_nodes.size() > 0:
		var spawn = spawn_nodes[randi() % spawn_nodes.size()]
		global_position = spawn.global_position

	initialize_weapon(current_weapon_index)

	recoil_pitch_offset = 0.0
	recoil_yaw_offset = 0.0
	camera_pitch = 0.0
	player_yaw = rotation.y

	update_movement_animation()
	print("[玩家 ", player_id, "] 重生，血量: ", current_health)

	if is_local_player:
		rpc("update_transform", global_position, rotation.y, camera_pitch)

	# 广播新血量
	rpc("sync_health", current_health)
	_update_ui()  # 本地立即更新


# =========================================================================
#  滑铲
# =========================================================================
func start_slide() -> void:
	if is_dead or is_sliding or not is_on_floor() or slide_cooldown > 0:
		return

	var dir: Vector3
	if velocity.length() > 0.5:
		dir = Vector3(velocity.x, 0, velocity.z).normalized()
	else:
		dir = -transform.basis.z

	velocity.x = dir.x * slide_speed
	velocity.z = dir.z * slide_speed

	is_sliding = true
	slide_timer = slide_duration
	target_camera_height = slide_camera_height
	slide_pending = false


func end_slide() -> void:
	if not is_sliding:
		return
	is_sliding = false
	target_camera_height = normal_camera_height
	slide_cooldown = slide_cooldown_duration
	slide_pending = false
	if not is_reloading and not is_dead:
		update_movement_animation()


# =========================================================================
#  每帧 UI 与输入
# =========================================================================
func _process(delta: float) -> void:
	if not is_local_player:
		return

	if not is_dead:
		if Input.is_action_just_pressed("slide"):
			if not is_sliding and is_on_floor() and slide_cooldown <= 0:
				start_slide()
			elif not is_sliding and not is_on_floor() and slide_cooldown <= 0:
				slide_pending = true

	# 每帧更新 UI（确保同步，但主动调用已覆盖）
	_update_ui()

	# 射击输入
	if not is_dead and not is_reloading and current_ammo > 0:
		process_shoot_input()

	# 侧瞄和探头
	if not is_dead:
		if Input.is_action_just_pressed("side_aim"):
			if is_aiming:
				is_side_aiming = true
				var weapon = get_current_weapon()
				target_side_position = weapon.get("side_aim_position_offset", Vector3.ZERO)
				target_side_rotation = weapon.get("side_aim_rotation_offset", Vector3.ZERO)
		if Input.is_action_just_released("side_aim"):
			if is_aiming:
				is_side_aiming = false
				target_side_position = Vector3.ZERO
				target_side_rotation = Vector3.ZERO

		if Input.is_action_pressed("lean_left"):
			target_lean = -lean_offset
		elif Input.is_action_pressed("lean_right"):
			target_lean = lean_offset
		else:
			target_lean = 0.0


func switch_weapon(index: int) -> void:
	start_weapon_switch(index)

# ===== 2️⃣ 移动精度惩罚计算 =====
func get_accuracy_multiplier() -> float:
	var mult = 1.0
	var current_speed = velocity.length()

	# 移动惩罚
	if current_speed > 0.1:
		var speed_factor = clamp(current_speed / walk_speed, 0.0, 1.0)
		mult *= lerp(1.0, 0.4, speed_factor)

	# 冲刺惩罚
	if is_sprinting:
		mult *= 0.3

	# 滑铲惩罚
	if is_sliding:
		mult *= 0.2

	# 蹲下增益
	if is_crouching:
		mult *= 1.3

	# 跳跃惩罚（带衰减）
	if jump_penalty_timer > 0:
		mult *= lerp(0.5, 1.0, jump_penalty_timer / 0.5)

	# 空中惩罚
	if not is_on_floor():
		mult *= 0.3

	return clamp(mult, 0.1, 1.5)

func calculate_spread() -> float:
	var weapon = get_current_weapon()
	var base_spread = weapon.spread
	var accuracy_mult = get_accuracy_multiplier()
	var shot_spread = shot_count * 0.0005

	if is_aiming:
		base_spread *= weapon.aim_spread_multiplier

	return base_spread * (1.0 / accuracy_mult) + shot_spread

func _on_jump() -> void:
	jump_penalty_timer = 0.5

# ===== 3️⃣ 呼吸晃动计算 =====
func update_breath(delta: float) -> void:
	breath_time += delta

	var intensity = 1.0
	var is_moving = velocity.length() > 0.5 and is_on_floor()

	if is_moving:
		intensity = 2.0
	if is_aiming:
		intensity *= 0.3
	if is_crouching:
		intensity *= 0.5

	breath_offset = Vector3(
		sin(breath_time * 0.3) * 0.005 * intensity,
		sin(breath_time * 0.25) * 0.008 * intensity * 0.7,
		0
	)

	# 急停惯性
	if velocity.length() < 0.1 and not is_moving:
		breath_offset.x *= exp(-delta * 3.0)

# ===== 应用到相机 =====
func apply_camera_position() -> void:
	var final_pos = camera_base_position
	if is_local_player:
		final_pos.x += current_lean + breath_offset.x
		final_pos.y += breath_offset.y
		final_pos.z += breath_offset.z
	camera.position = final_pos

# ===== 4️⃣ 开镜过渡计算 =====
func update_ads(delta: float) -> void:
	var aiming = false
	if is_local_player:
		aiming = Input.is_action_pressed("aim") and not is_dead
	else:
		aiming = is_aiming

	var weapon = get_current_weapon()
	var ads_speed = 1.0 / weapon.get("ads_time", 0.15)

	if aiming and not is_aiming:
		is_ads_transitioning = true
	elif not aiming and is_aiming:
		is_ads_transitioning = true

	if is_ads_transitioning:
		if aiming:
			ads_progress += delta * ads_speed
			if ads_progress >= 1.0:
				ads_progress = 1.0
				is_ads_transitioning = false
				is_aiming = true
		else:
			ads_progress -= delta * ads_speed
			if ads_progress <= 0.0:
				ads_progress = 0.0
				is_ads_transitioning = false
				is_aiming = false

		# 插值参数
		var start_fov = weapon.normal_fov
		var end_fov = weapon.aim_fov
		current_fov = lerp(start_fov, end_fov, ads_progress)

		var start_pos = weapon.normal_position_offset
		var end_pos = weapon.aim_position_offset
		target_position_offset = lerp(start_pos, end_pos, ads_progress)

		var start_rot = weapon.normal_rotation_offset
		var end_rot = weapon.aim_rotation_offset
		target_rotation_offset = lerp(start_rot, end_rot, ads_progress)
	else:
		if aiming:
			is_aiming = true
			ads_progress = 1.0
			current_fov = weapon.aim_fov
			target_position_offset = weapon.aim_position_offset
			target_rotation_offset = weapon.aim_rotation_offset
		else:
			is_aiming = false
			ads_progress = 0.0
			current_fov = weapon.normal_fov
			target_position_offset = weapon.normal_position_offset
			target_rotation_offset = weapon.normal_rotation_offset

# ===== 6️⃣ 武器切换手感 =====
func start_weapon_switch(new_index: int) -> void:
	if is_switching or new_index == current_weapon_index or new_index < 0 or new_index >= weapons.size():
		return
	if is_reloading:
		is_reloading = false
		is_playing_reload = false
		if reload_timer:
			reload_timer.stop()
			reload_timer.queue_free()
			reload_timer = null

	is_switching = true
	switch_progress = 0.0
	current_weapon_index = new_index
	initialize_weapon(new_index)
	weapon_pivot.position.y = -1.0

func update_weapon_switch(delta: float) -> void:
	if not is_switching:
		return

	switch_progress += delta / switch_duration
	if switch_progress >= 1.0:
		switch_progress = 1.0
		is_switching = false
		weapon_pivot.position = Vector3.ZERO
		return

	# 新武器从下方升起
	var new_pos = lerp(Vector3(0, -1, 0), Vector3.ZERO, switch_progress)
	weapon_pivot.position = new_pos

	# 旋转动画
	weapon_pivot.rotation.z = lerp(0.5, 0.0, switch_progress)

# ===== 7️⃣ 射击模式系统与输入 =====
func process_shoot_input() -> void:
	var weapon = get_current_weapon()
	var should_shoot = false

	var mode = weapon.get("fire_mode", FireMode.FULL_AUTO)
	match mode:
		FireMode.SEMI_AUTO:
			if Input.is_action_just_pressed("shoot"):
				should_shoot = true

		FireMode.BURST:
			if Input.is_action_just_pressed("shoot") and burst_counter == 0:
				burst_counter = weapon.get("burst_count", 3) - 1 # 修复多射一发的 Off-by-one 逻辑漏洞
				should_shoot = true
			elif burst_counter > 0:
				burst_timer += get_process_delta_time()
				if burst_timer >= weapon.shoot_cooldown:
					burst_counter -= 1
					should_shoot = true
					burst_timer = 0.0

		FireMode.FULL_AUTO:
			if Input.is_action_pressed("shoot"):
				should_shoot = true

	if should_shoot and can_shoot:
		shoot.rpc()

func toggle_fire_mode() -> void:
	var weapon = get_current_weapon()
	var modes = [FireMode.SEMI_AUTO, FireMode.BURST, FireMode.FULL_AUTO]
	var current_index = modes.find(weapon.get("fire_mode", FireMode.FULL_AUTO))
	current_index = (current_index + 1) % modes.size()
	weapon.fire_mode = modes[current_index]
	print("切换射击模式为: ", FireMode.keys()[weapon.fire_mode])

# ===== 1️⃣ 后坐力模式系统 =====
func apply_recoil() -> void:
	var weapon = get_current_weapon()
	shot_count += 1

	# 前几发后坐力逐渐增大到峰值
	recoil_peak = min(shot_count / 5.0, 1.0)

	var pattern = weapon.get("recoil_pattern", [])
	if pattern.size() > 0:
		var index = (shot_count - 1) % pattern.size()
		var offset = pattern[index] * recoil_peak

		# If aiming, reduce recoil a bit for better feel
		if is_aiming:
			offset *= 0.6

		recoil_pitch_offset -= offset.y
		recoil_yaw_offset += offset.x
	else:
		# 降级方案：使用随机后坐力
		var recoil_v = randf_range(weapon.recoil_vertical * 0.5, weapon.recoil_vertical) * recoil_multiplier
		var recoil_h = randf_range(-weapon.recoil_horizontal, weapon.recoil_horizontal) * recoil_multiplier
		if is_aiming:
			recoil_v *= 0.6
			recoil_h *= 0.6
		recoil_pitch_offset -= recoil_v * recoil_peak
		recoil_yaw_offset += recoil_h * recoil_peak

func update_recoil_recovery(delta: float) -> void:
	var is_shooting = false
	if is_local_player:
		var weapon = get_current_weapon()
		var mode = weapon.get("fire_mode", FireMode.FULL_AUTO)
		if mode == FireMode.BURST:
			is_shooting = burst_counter > 0 or Input.is_action_pressed("shoot")
		else:
			is_shooting = Input.is_action_pressed("shoot")

	if not is_shooting:
		recovery_delay_timer += delta
		var weapon = get_current_weapon()
		var delay = weapon.get("recoil_recovery_delay", 0.0)

		# 延迟后开始恢复
		if recovery_delay_timer > delay:
			# Stop count resets when recovery begins
			shot_count = 0
			var speed = weapon.recoil_recovery_speed
			var progress = 1.0 - exp(-speed * delta * 0.5)
			recoil_pitch_offset = lerp(recoil_pitch_offset, 0.0, progress)
			recoil_yaw_offset = lerp(recoil_yaw_offset, 0.0, progress * 0.7)
	else:
		recovery_delay_timer = 0.0

# ===== 5️⃣ 瞄准线系统 (激光指示) =====
var aim_line: Line3D = null

func setup_aim_line() -> void:
	aim_line = Line3D.new()
	aim_line.width = 0.02
	aim_line.material = StandardMaterial3D.new()
	aim_line.material.albedo_color = Color.GREEN
	aim_line.material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	aim_line.top_level = true # 避免全局坐标产生双重坐标系变换 Bug
	aim_line.visible = false
	add_child(aim_line)

func update_aim_line(delta: float) -> void:
	if not aim_line:
		return

	if is_aiming and not is_dead:
		var origin = weapon_pivot.global_position
		var direction = -camera.global_transform.basis.z

		var space_state = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(origin, origin + direction * 100)
		query.exclude = [self.get_rid()] # 排除自身
		var result = space_state.intersect_ray(query)

		var target = result.get("position", origin + direction * 100)
		aim_line.points = [origin, target]
		aim_line.visible = true
	else:
		aim_line.visible = false

# ===== 8️⃣ 子弹拖尾效果 =====
func create_bullet_trail(start: Vector3, end: Vector3) -> void:
	if not is_local_player:
		return

	var trail = Line3D.new()
	trail.width = 0.04
	trail.material = StandardMaterial3D.new()
	trail.material.albedo_color = Color(1.0, 0.8, 0.2, 0.8)
	trail.material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail.material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail.points = [start, end]

	get_tree().current_scene.add_child(trail)

	var tween = create_tween()
	tween.tween_property(trail.material, "albedo_color:a", 0.0, 0.1)
	tween.tween_callback(trail.queue_free)

# ===== 9️⃣ 撞击效果 =====
func create_bullet_impact(position: Vector3, normal: Vector3) -> void:
	if not is_local_player:
		return

	var impact = MeshInstance3D.new()
	impact.mesh = SphereMesh.new()
	(impact.mesh as SphereMesh).radius = 0.02
	(impact.mesh as SphereMesh).height = 0.04
	impact.position = position
	impact.material_override = StandardMaterial3D.new()
	impact.material_override.albedo_color = Color.YELLOW
	impact.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	impact.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	if normal.length_squared() > 0.001:
		var target_pos = position + normal
		if abs(normal.dot(Vector3.UP)) < 0.99:
			impact.look_at(target_pos, Vector3.UP)
		else:
			impact.look_at(target_pos, Vector3.RIGHT)

	get_tree().current_scene.add_child(impact)

	var tween = create_tween()
	tween.tween_property(impact, "scale", Vector3(2.0, 2.0, 2.0), 0.3)
	tween.parallel().tween_property(impact.material_override, "albedo_color:a", 0.0, 0.3)
	tween.tween_callback(impact.queue_free)

# ===== 🔟 命中反馈 UI 节点绑定 =====
func setup_feedback_ui() -> void:
	if not is_local_player or not has_node("CanvasLayer"):
		return
	var canvas = $CanvasLayer

	hit_marker_ui = HitMarkerUI.new()
	hit_marker_ui.anchor_left = 0.5
	hit_marker_ui.anchor_top = 0.5
	hit_marker_ui.anchor_right = 0.5
	hit_marker_ui.anchor_bottom = 0.5
	hit_marker_ui.size = Vector2(100, 100)
	hit_marker_ui.position = -hit_marker_ui.size * 0.5
	canvas.add_child(hit_marker_ui)

	damage_flash_ui = DamageFlashUI.new()
	canvas.add_child(damage_flash_ui)

func show_hit_marker() -> void:
	hit_marker_timer = 0.2
	if hit_marker_ui:
		hit_marker_ui.timer = 0.2

func show_damage_flash(intensity: float) -> void:
	damage_flash_timer = 0.3
	if damage_flash_ui:
		damage_flash_ui.timer = 0.3
		damage_flash_ui.intensity = intensity

# ===== 命中反馈与闪烁动态 UI 类 =====
class HitMarkerUI extends Control:
	var timer: float = 0.0
	func _process(delta: float) -> void:
		if timer > 0:
			timer -= delta
			visible = true
			queue_redraw()
		else:
			visible = false
	func _draw() -> void:
		var center = size * 0.5
		var length = 8.0
		var gap = 4.0
		var color = Color(1, 1, 1, timer / 0.2)
		draw_line(center - Vector2(gap + length, gap + length), center - Vector2(gap, gap), color, 2.0)
		draw_line(center + Vector2(gap, -gap), center + Vector2(gap + length, -(gap + length)), color, 2.0)
		draw_line(center + Vector2(-gap, gap), center + Vector2(-(gap + length), gap + length), color, 2.0)
		draw_line(center + Vector2(gap, gap), center + Vector2(gap + length, gap + length), color, 2.0)

class DamageFlashUI extends ColorRect:
	var timer: float = 0.0
	var intensity: float = 0.0
	func _ready() -> void:
		anchor_right = 1.0
		anchor_bottom = 1.0
		color = Color(1, 0, 0, 0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _process(delta: float) -> void:
		if timer > 0:
			timer -= delta
			var alpha = (timer / 0.3) * 0.3 * intensity
			color = Color(1, 0, 0, alpha)
			visible = true
		else:
			visible = false

# ===== 1️⃣1️⃣ 简单音效生成 =====
func generate_impulse_sound(freq: float, duration: float) -> AudioStreamWAV:
	var stream = AudioStreamWAV.new()
	stream.mix_rate = 44100
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = false

	var samples = int(stream.mix_rate * duration)
	var data = PackedByteArray()
	data.resize(samples * 2)

	var decay = 1.0 / duration
	var phase = 0.0

	for i in range(samples):
		phase += freq / stream.mix_rate
		var value = sin(phase * TAU) * exp(-i * decay * 0.2)
		value += randf_range(-0.15, 0.15) * (1.0 - float(i) / samples)
		value = clamp(value, -1.0, 1.0)

		var int_val = int(value * 32767)
		data.encode_s16(i * 2, int_val)

	stream.data = data
	return stream

func play_shot_sound() -> void:
	if not is_local_player:
		return

	var audio = AudioStreamPlayer3D.new()
	var weapon = get_current_weapon()
	var freq = 300 + randi() % 200
	audio.stream = generate_impulse_sound(freq, 0.05)
	audio.max_distance = 50
	audio.volume_db = -10
	audio.global_position = weapon_pivot.global_position

	get_tree().current_scene.add_child(audio)
	audio.play()

	await get_tree().create_timer(0.1).timeout
	audio.queue_free()

# ===== 动态程序化生成 53 把枪械的数据系统 =====
func generate_all_weapons() -> Array[Dictionary]:
	var list: Array[Dictionary] = []

	# 53把枪的原始核心属性配置 (手枪*10, 冲锋枪*10, 突击步枪*12, 精射*5, 狙击步枪*6, 霰弹枪*5, 机枪*5)
	var raw_weapons = [
		# === 1️⃣ 手枪 (Handguns) - 10 把 ===
		{"name": "Glock 17", "cat": "Handgun", "mode": FireMode.SEMI_AUTO, "ammo": 17, "dmg": 22.0, "cool": 0.12, "v_rec": 0.04, "h_rec": 0.01},
		{"name": "Glock 18C", "cat": "Handgun", "mode": FireMode.FULL_AUTO, "ammo": 20, "dmg": 19.0, "cool": 0.06, "v_rec": 0.05, "h_rec": 0.03},
		{"name": "USP .45", "cat": "Handgun", "mode": FireMode.SEMI_AUTO, "ammo": 12, "dmg": 30.0, "cool": 0.15, "v_rec": 0.05, "h_rec": 0.015},
		{"name": "Desert Eagle", "cat": "Handgun", "mode": FireMode.SEMI_AUTO, "ammo": 7, "dmg": 60.0, "cool": 0.4, "v_rec": 0.12, "h_rec": 0.06},
		{"name": "P250", "cat": "Handgun", "mode": FireMode.SEMI_AUTO, "ammo": 13, "dmg": 24.0, "cool": 0.14, "v_rec": 0.045, "h_rec": 0.018},
		{"name": "Five-seveN", "cat": "Handgun", "mode": FireMode.SEMI_AUTO, "ammo": 20, "dmg": 20.0, "cool": 0.11, "v_rec": 0.035, "h_rec": 0.01},
		{"name": "M1911", "cat": "Handgun", "mode": FireMode.SEMI_AUTO, "ammo": 7, "dmg": 32.0, "cool": 0.16, "v_rec": 0.06, "h_rec": 0.02},
		{"name": "CZ-75", "cat": "Handgun", "mode": FireMode.SEMI_AUTO, "ammo": 16, "dmg": 22.0, "cool": 0.12, "v_rec": 0.04, "h_rec": 0.015},
		{"name": "FNX-45", "cat": "Handgun", "mode": FireMode.SEMI_AUTO, "ammo": 15, "dmg": 28.0, "cool": 0.15, "v_rec": 0.05, "h_rec": 0.02},
		{"name": "Rex Zero 1", "cat": "Handgun", "mode": FireMode.SEMI_AUTO, "ammo": 17, "dmg": 22.0, "cool": 0.13, "v_rec": 0.038, "h_rec": 0.012},

		# === 2️⃣ 冲锋枪 (SMGs) - 10 把 ===
		{"name": "MP5", "cat": "SMG", "mode": FireMode.FULL_AUTO, "ammo": 30, "dmg": 23.0, "cool": 0.075, "v_rec": 0.03, "h_rec": 0.01},
		{"name": "UMP45", "cat": "SMG", "mode": FireMode.FULL_AUTO, "ammo": 25, "dmg": 28.0, "cool": 0.1, "v_rec": 0.045, "h_rec": 0.015},
		{"name": "Vector", "cat": "SMG", "mode": FireMode.FULL_AUTO, "ammo": 30, "dmg": 20.0, "cool": 0.05, "v_rec": 0.035, "h_rec": 0.025},
		{"name": "P90", "cat": "SMG", "mode": FireMode.FULL_AUTO, "ammo": 50, "dmg": 21.0, "cool": 0.066, "v_rec": 0.028, "h_rec": 0.012},
		{"name": "MP7", "cat": "SMG", "mode": FireMode.FULL_AUTO, "ammo": 30, "dmg": 21.0, "cool": 0.06, "v_rec": 0.032, "h_rec": 0.015},
		{"name": "PP-19 Bizon", "cat": "SMG", "mode": FireMode.FULL_AUTO, "ammo": 64, "dmg": 22.0, "cool": 0.08, "v_rec": 0.035, "h_rec": 0.01},
		{"name": "PP-2000", "cat": "SMG", "mode": FireMode.FULL_AUTO, "ammo": 20, "dmg": 23.0, "cool": 0.07, "v_rec": 0.038, "h_rec": 0.018},
		{"name": "Scorpion EVO 3", "cat": "SMG", "mode": FireMode.FULL_AUTO, "ammo": 30, "dmg": 19.0, "cool": 0.052, "v_rec": 0.03, "h_rec": 0.012},
		{"name": "MAC-10", "cat": "SMG", "mode": FireMode.FULL_AUTO, "ammo": 32, "dmg": 18.0, "cool": 0.048, "v_rec": 0.06, "h_rec": 0.04},
		{"name": "MP9", "cat": "SMG", "mode": FireMode.FULL_AUTO, "ammo": 30, "dmg": 20.0, "cool": 0.06, "v_rec": 0.035, "h_rec": 0.02},

		# === 3️⃣ 突击步枪 (Assault Rifles) - 12 把 ===
		{"name": "AKM", "cat": "AR", "mode": FireMode.FULL_AUTO, "ammo": 30, "dmg": 38.0, "cool": 0.1, "v_rec": 0.07, "h_rec": 0.035},
		{"name": "AK-74", "cat": "AR", "mode": FireMode.FULL_AUTO, "ammo": 30, "dmg": 30.0, "cool": 0.09, "v_rec": 0.05, "h_rec": 0.02},
		{"name": "M4A1", "cat": "AR", "mode": FireMode.FULL_AUTO, "ammo": 30, "dmg": 31.0, "cool": 0.075, "v_rec": 0.045, "h_rec": 0.018},
		{"name": "M16A4", "cat": "AR", "mode": FireMode.BURST, "ammo": 30, "dmg": 32.0, "cool": 0.075, "v_rec": 0.042, "h_rec": 0.015},
		{"name": "AUG", "cat": "AR", "mode": FireMode.FULL_AUTO, "ammo": 30, "dmg": 32.0, "cool": 0.08, "v_rec": 0.045, "h_rec": 0.018},
		{"name": "FAMAS", "cat": "AR", "mode": FireMode.BURST, "ammo": 25, "dmg": 28.0, "cool": 0.06, "v_rec": 0.048, "h_rec": 0.022},
		{"name": "SCAR-H", "cat": "AR", "mode": FireMode.FULL_AUTO, "ammo": 20, "dmg": 42.0, "cool": 0.11, "v_rec": 0.08, "h_rec": 0.03},
		{"name": "G36C", "cat": "AR", "mode": FireMode.FULL_AUTO, "ammo": 30, "dmg": 31.0, "cool": 0.08, "v_rec": 0.046, "h_rec": 0.02},
		{"name": "Galil", "cat": "AR", "mode": FireMode.FULL_AUTO, "ammo": 35, "dmg": 32.0, "cool": 0.09, "v_rec": 0.055, "h_rec": 0.022},
		{"name": "HK416", "cat": "AR", "mode": FireMode.FULL_AUTO, "ammo": 30, "dmg": 31.0, "cool": 0.072, "v_rec": 0.044, "h_rec": 0.016},
		{"name": "AK-12", "cat": "AR", "mode": FireMode.FULL_AUTO, "ammo": 30, "dmg": 31.0, "cool": 0.085, "v_rec": 0.048, "h_rec": 0.018},
		{"name": "CZ 805", "cat": "AR", "mode": FireMode.FULL_AUTO, "ammo": 30, "dmg": 31.0, "cool": 0.08, "v_rec": 0.045, "h_rec": 0.02},

		# === 4️⃣ 战斗步枪 / 精确射手 (Battle / DMR) - 5 把 ===
		{"name": "SVD", "cat": "DMR", "mode": FireMode.SEMI_AUTO, "ammo": 10, "dmg": 55.0, "cool": 0.25, "v_rec": 0.09, "h_rec": 0.03},
		{"name": "MK14 EBR", "cat": "DMR", "mode": FireMode.SEMI_AUTO, "ammo": 20, "dmg": 48.0, "cool": 0.18, "v_rec": 0.085, "h_rec": 0.028},
		{"name": "SR-25", "cat": "DMR", "mode": FireMode.SEMI_AUTO, "ammo": 10, "dmg": 58.0, "cool": 0.3, "v_rec": 0.095, "h_rec": 0.025},
		{"name": "M39 EMR", "cat": "DMR", "mode": FireMode.SEMI_AUTO, "ammo": 10, "dmg": 55.0, "cool": 0.28, "v_rec": 0.09, "h_rec": 0.028},
		{"name": "G3", "cat": "DMR", "mode": FireMode.SEMI_AUTO, "ammo": 20, "dmg": 45.0, "cool": 0.15, "v_rec": 0.08, "h_rec": 0.03},

		# === 5️⃣ 狙击步枪 (Sniper Rifles) - 6 把 ===
		{"name": "AWP", "cat": "Sniper", "mode": FireMode.SEMI_AUTO, "ammo": 5, "dmg": 100.0, "cool": 1.4, "v_rec": 0.2, "h_rec": 0.1},
		{"name": "M24", "cat": "Sniper", "mode": FireMode.SEMI_AUTO, "ammo": 5, "dmg": 95.0, "cool": 1.2, "v_rec": 0.18, "h_rec": 0.08},
		{"name": "Dragunov", "cat": "Sniper", "mode": FireMode.SEMI_AUTO, "ammo": 10, "dmg": 70.0, "cool": 0.4, "v_rec": 0.12, "h_rec": 0.05},
		{"name": "M40A3", "cat": "Sniper", "mode": FireMode.SEMI_AUTO, "ammo": 5, "dmg": 95.0, "cool": 1.3, "v_rec": 0.18, "h_rec": 0.08},
		{"name": "T-5000", "cat": "Sniper", "mode": FireMode.SEMI_AUTO, "ammo": 5, "dmg": 98.0, "cool": 1.3, "v_rec": 0.19, "h_rec": 0.09},
		{"name": "Barrett M82", "cat": "Sniper", "mode": FireMode.SEMI_AUTO, "ammo": 10, "dmg": 150.0, "cool": 0.8, "v_rec": 0.25, "h_rec": 0.15},

		# === 6️⃣ 霰弹枪 (Shotguns) - 5 把 ===
		{"name": "M870", "cat": "Shotgun", "mode": FireMode.SEMI_AUTO, "ammo": 8, "dmg": 80.0, "cool": 0.8, "v_rec": 0.15, "h_rec": 0.08},
		{"name": "SPAS-12", "cat": "Shotgun", "mode": FireMode.SEMI_AUTO, "ammo": 8, "dmg": 75.0, "cool": 0.5, "v_rec": 0.12, "h_rec": 0.06},
		{"name": "AA-12", "cat": "Shotgun", "mode": FireMode.FULL_AUTO, "ammo": 20, "dmg": 45.0, "cool": 0.2, "v_rec": 0.1, "h_rec": 0.05},
		{"name": "KS-23", "cat": "Shotgun", "mode": FireMode.SEMI_AUTO, "ammo": 3, "dmg": 120.0, "cool": 1.1, "v_rec": 0.22, "h_rec": 0.12},
		{"name": "Origin-12", "cat": "Shotgun", "mode": FireMode.FULL_AUTO, "ammo": 12, "dmg": 50.0, "cool": 0.22, "v_rec": 0.11, "h_rec": 0.06},

		# === 7️⃣ 轻机枪 / 通用机枪 (LMG / MMG) - 5 把 ===
		{"name": "M249 SAW", "cat": "LMG", "mode": FireMode.FULL_AUTO, "ammo": 100, "dmg": 28.0, "cool": 0.075, "v_rec": 0.05, "h_rec": 0.02},
		{"name": "PKM", "cat": "LMG", "mode": FireMode.FULL_AUTO, "ammo": 100, "dmg": 40.0, "cool": 0.092, "v_rec": 0.07, "h_rec": 0.035},
		{"name": "RPD", "cat": "LMG", "mode": FireMode.FULL_AUTO, "ammo": 100, "dmg": 34.0, "cool": 0.09, "v_rec": 0.06, "h_rec": 0.03},
		{"name": "M250", "cat": "LMG", "mode": FireMode.FULL_AUTO, "ammo": 100, "dmg": 38.0, "cool": 0.085, "v_rec": 0.048, "h_rec": 0.02},
		{"name": "MG3", "cat": "LMG", "mode": FireMode.FULL_AUTO, "ammo": 100, "dmg": 26.0, "cool": 0.05, "v_rec": 0.065, "h_rec": 0.03}
	]

	for rw in raw_weapons:
		var w: Dictionary = {}
		w.name = rw.name
		w.max_ammo = rw.ammo
		w.max_reserve_ammo = -1 # 无限备弹
		w.shoot_cooldown = rw.cool
		w.damage = rw.dmg
		w.recoil_vertical = rw.v_rec
		w.recoil_horizontal = rw.h_rec
		w.fire_mode = rw.mode
		w.burst_count = 3

		var cat = rw.cat
		if cat == "Handgun":
			w.reload_time = 1.6
			w.shoot_range = 50.0
			w.spread = 0.015
			w.aim_spread_multiplier = 0.4
			w.aim_fov = 65.0
			w.normal_fov = 75.0
			w.aim_sensitivity_multiplier = 0.6
			w.aim_speed_multiplier = 0.9
			w.ads_time = 0.12
			w.recoil_recovery_speed = 10.0
			w.recoil_recovery_delay = 0.03
			w.aim_position_offset = Vector3(-0.005, -0.16, -0.18)
		elif cat == "SMG":
			w.reload_time = 2.0
			w.shoot_range = 80.0
			w.spread = 0.02
			w.aim_spread_multiplier = 0.45
			w.aim_fov = 60.0
			w.normal_fov = 75.0
			w.aim_sensitivity_multiplier = 0.5
			w.aim_speed_multiplier = 0.8
			w.ads_time = 0.15
			w.recoil_recovery_speed = 8.5
			w.recoil_recovery_delay = 0.05
			w.aim_position_offset = Vector3(-0.005, -0.16, -0.2)
		elif cat == "AR":
			w.reload_time = 2.6
			w.shoot_range = 150.0
			w.spread = 0.012
			w.aim_spread_multiplier = 0.35
			w.aim_fov = 55.0
			w.normal_fov = 75.0
			w.aim_sensitivity_multiplier = 0.45
			w.aim_speed_multiplier = 0.65
			w.ads_time = 0.22
			w.recoil_recovery_speed = 7.0
			w.recoil_recovery_delay = 0.06
			w.aim_position_offset = Vector3(-0.005, -0.16, -0.22)
		elif cat == "DMR":
			w.reload_time = 3.0
			w.shoot_range = 250.0
			w.spread = 0.008
			w.aim_spread_multiplier = 0.2
			w.aim_fov = 40.0
			w.normal_fov = 75.0
			w.aim_sensitivity_multiplier = 0.3
			w.aim_speed_multiplier = 0.5
			w.ads_time = 0.28
			w.recoil_recovery_speed = 6.0
			w.recoil_recovery_delay = 0.08
			w.aim_position_offset = Vector3(-0.005, -0.16, -0.25)
		elif cat == "Sniper":
			w.reload_time = 3.5
			w.shoot_range = 400.0
			w.spread = 0.004
			w.aim_spread_multiplier = 0.05
			w.aim_fov = 25.0
			w.normal_fov = 75.0
			w.aim_sensitivity_multiplier = 0.2
			w.aim_speed_multiplier = 0.4
			w.ads_time = 0.35
			w.recoil_recovery_speed = 4.0
			w.recoil_recovery_delay = 0.15
			w.aim_position_offset = Vector3(-0.005, -0.16, -0.28)
		elif cat == "Shotgun":
			w.reload_time = 3.0
			w.shoot_range = 35.0
			w.spread = 0.06
			w.aim_spread_multiplier = 0.7
			w.aim_fov = 65.0
			w.normal_fov = 75.0
			w.aim_sensitivity_multiplier = 0.6
			w.aim_speed_multiplier = 0.75
			w.ads_time = 0.2
			w.recoil_recovery_speed = 6.5
			w.recoil_recovery_delay = 0.08
			w.aim_position_offset = Vector3(-0.005, -0.16, -0.2)
		elif cat == "LMG":
			w.reload_time = 4.5
			w.shoot_range = 180.0
			w.spread = 0.025
			w.aim_spread_multiplier = 0.4
			w.aim_fov = 50.0
			w.normal_fov = 75.0
			w.aim_sensitivity_multiplier = 0.4
			w.aim_speed_multiplier = 0.5
			w.ads_time = 0.3
			w.recoil_recovery_speed = 5.0
			w.recoil_recovery_delay = 0.08
			w.aim_position_offset = Vector3(-0.005, -0.16, -0.24)

		# 通用初始化配置参数
		w.normal_position_offset = Vector3(0.323, -0.297, -0.488)
		w.normal_rotation_offset = Vector3(0.0, 0.0, 0.0)
		w.aim_rotation_offset = Vector3(0.0, 0.0, 0.0)
		w.transition_speed = 10.0
		w.side_aim_position_offset = Vector3(0, 0, 0)
		w.side_aim_rotation_offset = Vector3(0, 0, 1)
		w.aim_jitter_multiplier = 0.4
		w.pellet_count = rw.get("pellets", 1) # 支持散弹枪多弹丸属性

		# 自动生成 30 发高精度专业级后坐力 S-Curve 曲线数据 (使用 2.0 倍数使手感平滑可控)
		var pattern: Array[Vector2] = []
		var base_v = rw.v_rec * 2.0
		var base_h = rw.h_rec * 2.0
		for i in range(30):
			var shot = i + 1
			var v = base_v * (1.0 + shot * 0.03)
			var h = sin(shot * 0.5) * base_h * 1.5
			if shot > 10:
				h += base_h * 0.5
			pattern.append(Vector2(h, v))
		w.recoil_pattern = pattern

		list.append(w)

	return list
