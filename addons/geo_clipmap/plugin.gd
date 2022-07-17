tool
extends EditorPlugin

const GeoClipmap = preload("geo_clipmap.gd")

var _terrain : GeoClipmap = null
var _toolbar = null

func _enter_tree():
	add_custom_type("GeoClipmap", "Spatial", GeoClipmap, preload("terrain.svg"))

	_toolbar = HBoxContainer.new()
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)
	_toolbar.hide()

	var menu := MenuButton.new()
	menu.set_text("Terrain")
	menu.get_popup().add_item("Generate Collider", 1)
	menu.get_popup().connect("id_pressed", self, "_menu_item_selected")
	_toolbar.add_child(menu)

func _exit_tree():
	remove_custom_type("GeoClipmap")
	remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)

func handles(object):
	if object is GeoClipmap:
		return true

	return false

func edit(object):
	if object is GeoClipmap:
		_terrain = object
		_terrain.set_process(true)
		set_physics_process(true)
	else:
		set_physics_process(false)

func make_visible(visible: bool):
	_toolbar.set_visible(visible)

func forward_spatial_gui_input(camera : Camera, event):
	if _terrain == null:
		return false

	_terrain._update_viewer_position(camera)

func _menu_item_selected(id: int):
	match id:
		1:
			_generate_collider()

func _generate_collider():
	var collision_height
	var collision_width

	var float_array = PoolRealArray()

	var heightmap_image = load("res://assets/heightmap.png")

	heightmap_image.lock()

	collision_height = heightmap_image.get_height()
	collision_width = heightmap_image.get_width()

	for y in collision_height:
		for x in collision_width:
			var current_pixel = heightmap_image.get_pixel(x, y).r
			float_array.append(current_pixel * 255)

	heightmap_image.unlock()

	var shape : HeightMapShape = HeightMapShape.new()
	shape.map_width = collision_width
	shape.map_depth = collision_height
	shape.map_data = float_array

	ResourceSaver.save("res://assets/collider.res", shape)
