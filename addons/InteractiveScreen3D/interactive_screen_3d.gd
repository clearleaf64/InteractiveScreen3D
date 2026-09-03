@tool
@icon("res://addons/InteractiveScreen3D/television_flat_screen.svg")
class_name InteractiveScreen3D extends Area3D
## Computer screen that takes mouse input
##
## Place this in a scene and then place UI scenes as children of the screens. They will be 
## reparented into the screen, retaining whatever signals or stuff you set up with them. 
## All typical godot stuff applies as normal.  


@onready var viewport: SubViewport = $SubViewport
@onready var mesh_instance: MeshInstance3D = $DisplayMesh
@onready var collision_shape: CollisionShape3D = $MouseDetector

## The pixel resolution of this virtual display/subviewport.
@export var resolution: Vector2i = Vector2i(640, 360):
	set(value):
		resolution = value
		_update_display()

## Height of screen in meters. Width will follow aspect ratio of resolution.
@export_range(0.01, 25.0, 0.01)
var screen_height: float = 1.0:
	set(value):
		screen_height = value
		_update_display()

## Take input when in captured mouse mode (used for 1st person, over the shoulder, etc).
## In other words, turns the center of the game camera into a mouse rather than the actual mouse. 
## If the mouse is uncaptured, camera mouse will not be used during that time.
@export var enable_captured_mouse_input = true

## How far away the screen can be interacted with when captured mouse input is enabled.
@export var captured_input_ray_length: float = 5.0

## False if screen should "glow" and true if screen is lit by environment 
@export var shaded = false


func set_shaded(shade_screen:bool):
	var mat = mesh_instance.mesh.surface_get_material(0).duplicate()
	if shade_screen:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		
	else:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_instance.mesh.surface_set_material(0,mat)
	shaded = shade_screen

var mouse_over_display = false
var last_pixel_pos = Vector2.ZERO

signal screen_entered
signal screen_exited

func _ready():
	mesh_instance.mesh = mesh_instance.mesh.duplicate()
	if Engine.is_editor_hint():
		_update_display()
		return

	for i in get_children():
		if not i.is_in_group("screen_internal"):
			i.reparent(viewport)
	set_shaded(shaded)
	_update_display()


func _process(_delta):
	if Engine.is_editor_hint():
		return
	
	if not enable_captured_mouse_input:
		return

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	_update_camera_mouse()


func _input(event: InputEvent):
	if Engine.is_editor_hint():
		return

	if not enable_captured_mouse_input:
		return

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	if event is InputEventMouseButton:
		_handle_camera_mouse_button(event)


func _update_display():
	if not is_inside_tree():
		return

	if resolution.x <= 0 or resolution.y <= 0:
		return

	viewport.size = resolution

	var quad = mesh_instance.mesh as QuadMesh

	var aspect = float(resolution.x) / float(resolution.y)

	var target = Vector2(
		screen_height * aspect,
		screen_height
	)

	quad.size = target

	var box = collision_shape.shape as BoxShape3D

	box.size = Vector3(
		target.x,
		target.y,
		0.1
		)


func _input_event(
	_camera: Node,
	event: InputEvent,
	event_position: Vector3,
	_normal: Vector3,
	_shape_idx: int
):
	# This handles normal, non-captured mouse input.
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		return

	if not event is InputEventMouse: 
		return

	var pixel_pos = _world_to_pixel(event_position)

	if pixel_pos == Vector2.INF:
		return

	var ev = event.duplicate()

	ev.position = pixel_pos
	ev.global_position = pixel_pos

	viewport.push_input(ev)


func _update_camera_mouse():
	var camera = get_viewport().get_camera_3d()

	if not camera: return

	var viewport_size = get_viewport().get_visible_rect().size

	var screen_center = viewport_size * 0.5

	var ray_origin = camera.project_ray_origin(screen_center)
	var ray_direction = camera.project_ray_normal(screen_center)

	var ray_end = ray_origin + ray_direction * captured_input_ray_length

	var space_state = get_world_3d().direct_space_state

	var query = PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_end
	)

	query.collide_with_areas = true
	query.collide_with_bodies = false

	var result = space_state.intersect_ray(query)

	if result.is_empty():
		_set_camera_mouse_out()
		return

	if result["collider"] != self and not is_ancestor_of(result["collider"]):
		_set_camera_mouse_out()
		return

	var hit_position: Vector3 = result["position"]
	var hit_normal: Vector3 = result["normal"]

	# Don't interact with the back of the screen.
	if hit_normal.dot(ray_direction) >= 0.0:
		_set_camera_mouse_out()
		return

	var pixel_pos = _world_to_pixel(hit_position)

	if pixel_pos == Vector2.INF:
		_set_camera_mouse_out()
		return

	_set_camera_mouse_position(pixel_pos)


func _handle_camera_mouse_button(event: InputEventMouseButton):
	var camera = get_viewport().get_camera_3d()

	if not camera:
		return

	var viewport_size = get_viewport().get_visible_rect().size
	var screen_center = viewport_size * 0.5

	var ray_origin = camera.project_ray_origin(screen_center)
	var ray_direction = camera.project_ray_normal(screen_center)
	var ray_end = ray_origin + ray_direction * captured_input_ray_length

	var space_state = get_world_3d().direct_space_state

	var query = PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_end
	)

	query.collide_with_areas = true
	query.collide_with_bodies = false

	var result = space_state.intersect_ray(query)

	if result.is_empty():
		return

	if result["collider"] != self and not is_ancestor_of(result["collider"]):
		return

	var hit_position: Vector3 = result["position"]
	var hit_normal: Vector3 = result["normal"]

	# Don't click the back of the display.
	if hit_normal.dot(ray_direction) >= 0.0:
		return

	var pixel_pos = _world_to_pixel(hit_position)

	if pixel_pos == Vector2.INF:
		return

	var button_event = event.duplicate()

	button_event.position = pixel_pos
	button_event.global_position = pixel_pos

	viewport.push_input(button_event)


func _set_camera_mouse_position(pixel_pos: Vector2):
	if mouse_over_display == false:
		screen_entered.emit()
	mouse_over_display = true
	last_pixel_pos = pixel_pos

	var motion = InputEventMouseMotion.new()

	motion.position = pixel_pos
	motion.global_position = pixel_pos
	motion.relative = Vector2.ZERO

	viewport.push_input(motion)


func _set_camera_mouse_out():
	if not mouse_over_display: return

	mouse_over_display = false
	
	var motion = InputEventMouseMotion.new()
	motion.position = Vector2(-1, -1)
	motion.global_position = Vector2(-1, -1)
	motion.relative = Vector2.ZERO

	viewport.push_input(motion)
	screen_exited.emit()


func _world_to_pixel(world_position: Vector3) -> Vector2:
	var quad = mesh_instance.mesh as QuadMesh

	var local_hit = (
		mesh_instance.global_transform.affine_inverse()
		* world_position
	)

	var uv = Vector2(
		local_hit.x / quad.size.x + 0.5,
		0.5 - local_hit.y / quad.size.y
	)

	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return Vector2.INF

	return uv * Vector2(viewport.size)
