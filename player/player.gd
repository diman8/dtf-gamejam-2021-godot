class_name Player
extends KinematicBody

const CAMERA_MOUSE_ROTATION_SPEED = 0.001
const CAMERA_CONTROLLER_ROTATION_SPEED = 3.0
const CAMERA_X_ROT_MIN = -40
const CAMERA_X_ROT_MAX = 30

const DIRECTION_INTERPOLATE_SPEED = 1
const MOTION_INTERPOLATE_SPEED = 10
const ROTATION_INTERPOLATE_SPEED = 6

const MIN_AIRBORNE_TIME = 0.1
const JUMP_SPEED = 5

var airborne_time = 100

var orientation = Transform()
var root_motion = Transform()
var motion = Vector2()
var velocity = Vector3()

var aiming = false
var camera_x_rot = 0.0

onready var initial_position = transform.origin
onready var gravity = ProjectSettings.get_setting("physics/3d/default_gravity") * ProjectSettings.get_setting("physics/3d/default_gravity_vector")

onready var animation_tree = $AnimationTree
onready var player_model = $PlayerModel
onready var shoot_from = player_model.get_node(@"Robot_Skeleton/Skeleton/GunBone/ShootFrom")
onready var color_rect = $ColorRect
onready var fire_cooldown = $FireCooldown

onready var camera_base = $CameraBase
onready var camera_animation = camera_base.get_node(@"Animation")
onready var camera_camera = camera_base.get_node(@"Camera")

onready var sound_effects = $SoundEffects
onready var sound_effect_jump = sound_effects.get_node(@"Jump")
onready var sound_effect_land = sound_effects.get_node(@"Land")
onready var sound_effect_shoot = sound_effects.get_node(@"Shoot")

func _init():
#	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	pass


func _ready():
	# Pre-initialize orientation transform.
	orientation = player_model.global_transform
	orientation.origin = Vector3()
	# Dont rotate camera with player
	camera_base.set_as_toplevel(true)


func _process(_delta):
	# Fade out to black if falling out of the map. -17 is lower than
	# the lowest valid position on the map (which is a bit under -16).
	# At 15 units below -17 (so -32), the screen turns fully black.
	if transform.origin.y < -17:
		color_rect.modulate.a = min((-17 - transform.origin.y) / 15, 1)
		# If we're below -40, respawn (teleport to the initial position).
		if transform.origin.y < -40:
			color_rect.modulate.a = 0
			transform.origin = initial_position


func _physics_process(delta):
	var motion_target = Vector2(
			Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
			Input.get_action_strength("move_back") - Input.get_action_strength("move_forward"))
	motion = motion.linear_interpolate(motion_target, MOTION_INTERPOLATE_SPEED * delta)

	var current_aim = Input.is_action_pressed("aim")

	if aiming != current_aim:
		aiming = current_aim
		if aiming:
			camera_animation.play("shoot")
		else:
			camera_animation.play("far")

	# Jump/in-air logic.
	airborne_time += delta
	if is_on_floor():
		if airborne_time > 0.5:
			sound_effect_land.play()
		airborne_time = 0

	var on_air = airborne_time > MIN_AIRBORNE_TIME

	if not on_air and Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_SPEED
		on_air = true
		# Increase airborne time so next frame on_air is still true
		airborne_time = MIN_AIRBORNE_TIME
		animation_tree["parameters/state/current"] = 2
		sound_effect_jump.play()

	if on_air:
		if (velocity.y > 0):
			animation_tree["parameters/state/current"] = 2
		else:
			animation_tree["parameters/state/current"] = 3
	elif aiming:
		# Change state to strafe.
		animation_tree["parameters/state/current"] = 0

		# Convert orientation to quaternions for interpolating rotation.
#		var q_from = orientation.basis.get_rotation_quat()
#		var q_to = camera_base.global_transform.basis.get_rotation_quat()
#		# Interpolate current rotation with desired one.
#		orientation.basis = Basis(q_from.slerp(q_to, delta * ROTATION_INTERPOLATE_SPEED))

		motion *= 0.95

		# The animation's forward/backward axis is reversed.
		animation_tree["parameters/strafe/blend_position"] = Vector2(motion.x, -motion.y)

		root_motion = animation_tree.get_root_motion_transform()

		if Input.is_action_pressed("shoot") and fire_cooldown.time_left == 0:
			var shoot_origin = shoot_from.global_transform.origin

			var plane = Plane(Vector3(0,1,0), global_transform.origin.y)
			var ch_pos = get_viewport().get_mouse_position()
			var ray_from = camera_camera.project_ray_origin(ch_pos)
			var ray_dir = camera_camera.project_ray_normal(ch_pos)

			var col : Vector3 = plane.intersects_ray(ray_from, ray_from + ray_dir * 1000)
			col.y = shoot_origin.y
			var shoot_dir = (col - shoot_origin).normalized()

			var bullet = preload("res://player/bullet/bullet.tscn").instance()
			get_parent().add_child(bullet)
			bullet.global_transform.origin = shoot_origin
			# If we don't rotate the bullets there is no useful way to control the particles ..
			bullet.look_at(shoot_origin + shoot_dir, Vector3.UP)
			bullet.add_collision_exception_with(self)
			var shoot_particle = $PlayerModel/Robot_Skeleton/Skeleton/GunBone/ShootFrom/ShootParticle
			shoot_particle.restart()
			shoot_particle.emitting = true
			var muzzle_particle = $PlayerModel/Robot_Skeleton/Skeleton/GunBone/ShootFrom/MuzzleFlash
			muzzle_particle.restart()
			muzzle_particle.emitting = true
			fire_cooldown.start()
			sound_effect_shoot.play()
			camera_camera.add_trauma(0.35)

	else:

		animation_tree["parameters/aim/add_amount"] = 0
		animation_tree["parameters/state/current"] = 0
		animation_tree["parameters/strafe/blend_position"] = Vector2(motion.x, -motion.y)

		root_motion = animation_tree.get_root_motion_transform()


	var above_floor_vec = Vector3(0,0.4,0)

	# Player Y rotation (hacky)
	var plane = Plane(Vector3(0,1,0), global_transform.origin.y)
	var ch_pos = get_viewport().get_mouse_position()
	var ray_from = camera_camera.project_ray_origin(ch_pos)
	var ray_dir = camera_camera.project_ray_normal(ch_pos)
	var col : Vector3 = plane.intersects_ray(ray_from, ray_from + ray_dir * 1000)
	var shoot_dir = (global_transform.origin - col).normalized()
	
	var tt = Transform().looking_at(shoot_dir.normalized(), Vector3.UP)
#	print(tt)
	var q_from = orientation.basis.get_rotation_quat()
	var q_to = Quat(tt.basis)
	orientation.basis = Basis(q_from.slerp(q_to, delta * ROTATION_INTERPOLATE_SPEED))

	camera_follows_player()
#	DebugDraw.draw_line_3d(global_transform.origin + above_floor_vec, global_transform.origin + above_floor_vec + shoot_dir, Color.black)
	


	# Apply root motion to orientation.
	orientation *= root_motion

	var h_velocity = orientation.origin / delta
	velocity.x = h_velocity.x
	velocity.z = h_velocity.z
	velocity += gravity * delta
	velocity = move_and_slide(velocity, Vector3.UP)

	orientation.origin = Vector3() # Clear accumulated root motion displacement (was applied to speed).
	orientation = orientation.orthonormalized() # Orthonormalize orientation.

	player_model.global_transform.basis = orientation.basis

#	DebugDraw.draw_line_3d(global_transform.origin + above_floor_vec, global_transform.origin + above_floor_vec + velocity, Color.red)


func _input(event):
	if event.is_action_pressed("quit"):
		get_tree().quit()
#	if event is InputEventMouseMotion:
#		var camera_speed_this_frame = CAMERA_MOUSE_ROTATION_SPEED
#		if aiming:
#			camera_speed_this_frame *= 0.75
#		rotate_camera(event.relative * camera_speed_this_frame)


#func rotate_camera(move):
#	camera_base.rotate_y(-move.x)
#	# After relative transforms, camera needs to be renormalized.
#	camera_base.orthonormalize()
#	camera_x_rot += move.y
#	camera_x_rot = clamp(camera_x_rot, deg2rad(CAMERA_X_ROT_MIN), deg2rad(CAMERA_X_ROT_MAX))


func add_camera_shake_trauma(amount):
	camera_camera.add_trauma(amount)

func camera_follows_player():
	camera_base.global_transform.origin = global_transform.origin
