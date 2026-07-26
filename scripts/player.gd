extends CharacterBody3D

## ===== 移动参数 =====
@export var walk_speed: float = 5.0
@export var jump_velocity: float = 4.5
@export var gravity: float = 15.0
@export var mouse_sensitivity: float = 0.002
@export var hp_bar_max_width: float = 0.0
## ===== 侧瞄过渡速度 =====
@export var side_transition_speed: float = 10.0

## ===== 探头参数 =====
@export var lean_offset: float = 0.2
@export var lean_transition_speed: float = 12.0

## ===== 武器数据 =====
var weapons: Array[Dictionary] = [
	{
		"name": "Vector",
		"max_ammo": 90,
		"max_reserve_ammo": -1,
		"reload_time": 2.0,
		"shoot_cooldown": 0.05,
		"damage": 20.0,
		"shoot_range": 100.0,
		"recoil_vertical": 0.05,
		"recoil_horizontal": 0.02,
		"spread": 0.01,
		"aim_spread_multiplier": 0.5,
		"aim_fov": 60.0,
		"normal_fov": 75,
		"aim_sensitivity_multiplier": 0.5,
		"aim_speed_multiplier": 0.7,
		"aim_position_offset": Vector3(-0.005, -0.16, -0.2),
		"aim_rotation_offset": Vector3(0.0, 0.0, 0.0),
		"normal_position_offset": Vector3(0.323, -0.297, -0.488),
		"normal_rotation_offset": Vector3(0.0, 0.0, 0.0),
		"transition_speed": 10.0,
		"recoil_recovery_speed": 8.0,
		"side_aim_position_offset": Vector3(0, 0, 0),
		"side_aim_rotation_offset": Vector3(0, 0, 1),
		"aim_jitter_multiplier": 0.5
	}
]

var current_weapon_index: int = 0

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
	hp_bar_max_width = hprect.size.x
	if hp_bar_max_width == 0:
		hp_bar_max_width = 280
	# 固定锚点避免被父容器影响
	hprect.anchor_left = 0.0
	hprect.anchor_right = 0.0

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
		

	if bulletlabel:
		if reserve_ammo < 0:
			bulletlabel.text = str(current_ammo) + " / ∞"
		else:
			bulletlabel.text = str(current_ammo) + " / " + str(reserve_ammo)


# =========================================================================
#  物理更新
# =========================================================================
func _physics_process(delta: float) -> void:
	# 权威端钳制血量
	if is_multiplayer_authority():
		current_health = clamp(current_health, 0, max_health)
		if current_health <= 0 and not is_dead:
			die()

	if is_local_player:
		if not is_dead:
			handle_movement(delta)
		else:
			velocity = Vector3.ZERO
			move_and_slide()
	else:
		player_yaw = rotation.y
		camera_pitch = camera.rotation.x

	update_aiming(delta)
	update_side_aim(delta)
	update_lean(delta)
	update_camera_height(delta)

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
			if pos.distance_to(last_sent_position) > 0.1 or abs(rot - last_sent_rotation) > 0.01:
				last_sent_position = pos
				last_sent_rotation = rot
				rpc("update_transform", pos, rot)


func handle_movement(delta: float) -> void:
	if is_dead:
		return

	if is_sliding:
		if Input.is_action_just_pressed("jump") and is_on_floor():
			end_slide()
			velocity.y = jump_velocity
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
	
	var target_speed: float = walk_speed
	if is_aiming:
		target_speed *= get_current_weapon().aim_speed_multiplier

	current_speed = target_speed

	if direction:
		velocity.x = move_toward(velocity.x, direction.x * target_speed, target_speed * delta * 10)
		velocity.z = move_toward(velocity.z, direction.z * target_speed, target_speed * delta * 10)
	else:
		velocity.x = move_toward(velocity.x, 0.0, target_speed * delta * 10)
		velocity.z = move_toward(velocity.z, 0.0, target_speed * delta * 10)

	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_sliding:
		velocity.y = jump_velocity

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


func update_side_aim(delta: float) -> void:
	var speed: float = side_transition_speed
	current_side_position = current_side_position.lerp(target_side_position, speed * delta)
	current_side_rotation = current_side_rotation.lerp(target_side_rotation, speed * delta)


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


# =========================================================================
#  手动同步 RPC
# =========================================================================
@rpc("any_peer", "call_remote", "unreliable")
func update_transform(new_pos: Vector3, new_rot_y: float) -> void:
	global_position = new_pos
	rotation.y = new_rot_y
	player_yaw = new_rot_y


# =========================================================================
#  血量同步 RPC
# =========================================================================
@rpc("any_peer", "call_remote", "reliable")
func sync_health(new_health: float) -> void:
	if is_local_player:
		return
	current_health = new_health
	_update_ui()  # 立即刷新 UI


# =========================================================================
#  RPC 射击与换弹
# =========================================================================
@rpc("any_peer", "call_local")
func shoot() -> void:
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
		
		var spread_angle: float = weapon.spread
		if is_aiming:
			spread_angle *= weapon.aim_spread_multiplier
		var rand_h: float = randf_range(-spread_angle, spread_angle)
		var rand_v: float = randf_range(-spread_angle, spread_angle)
		var local_dir: Vector3 = Vector3(rand_h, rand_v, -1.0).normalized()
		var global_dir: Vector3 = cam_global.basis * local_dir
		var end: Vector3 = origin + global_dir * weapon.shoot_range

		var query := PhysicsRayQueryParameters3D.create(origin, end)
		query.collision_mask = 1
		var result: Dictionary = space_state.intersect_ray(query)

		if result:
			var hit: Object = result.collider
			if hit.is_in_group("players") and hit != self:
				hit.take_damage.rpc_id(hit.get_multiplayer_authority(), weapon.damage, player_id)

		var recoil_v: float = randf_range(weapon.recoil_vertical * 0.5, weapon.recoil_vertical)
		var recoil_h: float = randf_range(-weapon.recoil_horizontal, weapon.recoil_horizontal)
		if is_aiming:
			recoil_v *= 0.6
			recoil_h *= 0.6
		recoil_pitch_offset -= recoil_v
		recoil_yaw_offset += recoil_h

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


func _on_reload_timeout() -> void:
	if is_dead or not is_reloading:
		return

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
	if not is_dead:
		return

	current_health = max_health
	is_dead = false
	can_shoot = true

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
		rpc("update_transform", global_position, rotation.y)

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
	if not is_dead and Input.is_action_pressed("shoot") and not is_reloading and current_ammo > 0 and can_shoot:
		shoot.rpc()

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
	if is_dead or index == current_weapon_index or index < 0 or index >= weapons.size():
		return
	if is_reloading:
		is_reloading = false
		is_playing_reload = false
	current_weapon_index = index
	initialize_weapon(index)
	print("切换到: ", get_current_weapon().name)
