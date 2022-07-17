tool
extends Spatial

var terrain_material := ShaderMaterial.new()

var heightmap_image : Image
var heightmap_texture : ImageTexture
var heightmap_size : Vector2

const TILE_RESOLUTION = 48
const PATCH_VERT_RESOLUTION = TILE_RESOLUTION + 1
const CLIPMAP_RESOLUTION = TILE_RESOLUTION * 4 + 1
const CLIPMAP_VERT_RESOLUTION = CLIPMAP_RESOLUTION + 1
const NUM_CLIPMAP_LEVELS = 7
const MAX_CHUNK_HEIGHT = 255

var viewer_position : Vector3 = Vector3.ZERO

var cross_mesh = _generate_cross_mesh()
var tile_mesh = _generate_tile_mesh()
var filler_mesh = _generate_filler_mesh()
var trim_mesh = _generate_trim_mesh()
var seam_mesh = _generate_seam_mesh()

var mesh_instance : MeshInstance

var cross_instance_id
var tiles = {}
var fillers = {}
var trims = {}
var seams = {}

func _init():
	print("init")
	for child in get_children():
		child.queue_free()

	cross_instance_id = null
	tiles.clear()
	fillers.clear()
	seams.clear()

	heightmap_image = load("res://assets/heightmap.png")
	heightmap_texture = ImageTexture.new()
	heightmap_texture.create_from_image(heightmap_image)
	heightmap_texture.set_flags(0)

	terrain_material.shader = load("res://addons/geo_clipmap/shaders/terrain.shader")

	if not Engine.is_editor_hint():
		var shape : HeightMapShape

		shape = load("res://assets/collider.res")

		var collision_shape : CollisionShape = CollisionShape.new()
		collision_shape.set_shape(shape)

		var static_body = StaticBody.new()
		static_body.add_child(collision_shape)

		add_child(static_body)

		static_body.translation = Vector3(shape.map_width / 2 - 0.5, 0, shape.map_depth / 2 - 0.5)

func _ready():
	print("ready")

func _enter_tree():
	print("enter tree")

func _exit_tree():
	print("exit tree")

func _update_viewer_position(camera: Camera):
	if camera == null:
		var viewport : Viewport = get_viewport()
		if viewport != null:
			camera = viewport.get_camera()

	if camera == null:
		return

	viewer_position = camera.global_transform.origin

func _process(delta: float):
	if not Engine.is_editor_hint():
		_update_viewer_position(null)

	var custom_aabb : AABB

	var it = Transform()
	var normal_basis = Basis()

	var gt = Transform(Basis().scaled(Vector3(1, 1, 1)), global_transform.origin)
	it = gt.affine_inverse()

	terrain_material.set_shader_param("inverse_transform", it)

	terrain_material.set_shader_param("heightmap", heightmap_texture)
	terrain_material.set_shader_param("max_height", MAX_CHUNK_HEIGHT)

	var snapped_position : Vector2
	snapped_position = Vector2(viewer_position.x, viewer_position.z).floor()

	var cross : MeshInstance

	if cross_instance_id:
		cross = instance_from_id(cross_instance_id)
	else:
		cross = MeshInstance.new()
		cross.material_override = terrain_material
		cross.mesh = cross_mesh
		cross_instance_id = cross.get_instance_id()
		add_child(cross)

	cross.scale = Vector3(1, 1, 1)
	cross.translation = Vector3(snapped_position.x, 0, snapped_position.y)

	custom_aabb = cross.get_aabb()
	custom_aabb.size.y = MAX_CHUNK_HEIGHT
	cross.set_custom_aabb(custom_aabb)

	for level in range(NUM_CLIPMAP_LEVELS):
		var scale = 1 << level

		var viewer_pos = Vector2(viewer_position.x, viewer_position.z)
		snapped_position = (viewer_pos / scale).floor() * scale

		var tile_size = Vector2(TILE_RESOLUTION << level, TILE_RESOLUTION << level)
		var base = snapped_position - tile_size * 2

		for x in range(4):
			for y in range(4):
				if level != 0 && (x == 1 || x ==2) && (y == 1 || y == 2):
					continue

				var fill = Vector2(1 if x >= 2 else 0, 1 if y >= 2 else 0) * scale
				var tile_bl : Vector2 = base + Vector2(x, y) * tile_size + fill

				var tile_key = "%s-%s-%s" % [level, x, y]
				var tile : MeshInstance

				if tiles.has(tile_key):
					var mesh_instance_id = tiles.get(tile_key)
					tile = instance_from_id(mesh_instance_id)
				else:
					tile = MeshInstance.new()
					tile.material_override = terrain_material
					tile.mesh = tile_mesh
					tiles[tile_key] = tile.get_instance_id()
					add_child(tile)

				tile.scale = Vector3(scale, 1, scale)
				tile.translation = Vector3(tile_bl.x, 0, tile_bl.y)

				custom_aabb = tile.get_aabb()
				custom_aabb.size.y = MAX_CHUNK_HEIGHT
				tile.set_custom_aabb(custom_aabb)

		var filler : MeshInstance

		if fillers.has(scale):
			var mesh_instance_id = fillers.get(scale)
			filler = instance_from_id(mesh_instance_id)
		else:
			filler = MeshInstance.new()
			filler.material_override = terrain_material
			filler.mesh = filler_mesh
			fillers[scale] = filler.get_instance_id()
			add_child(filler)

		filler.scale = Vector3(scale, 1, scale)
		filler.translation = Vector3(snapped_position.x, 0, snapped_position.y)

		custom_aabb = filler.get_aabb()
		custom_aabb.size.y = MAX_CHUNK_HEIGHT
		filler.set_custom_aabb(custom_aabb)

		if level != NUM_CLIPMAP_LEVELS - 1:
			var next_scale = scale * 2
			var next_snapped_position = (viewer_pos / next_scale).floor() * next_scale

			var tile_centre = snapped_position + Vector2(scale * 0.5, scale * 0.5)

			var d = viewer_pos - next_snapped_position
			var r = 0
			r |= 0 if d.x >= scale else 2
			r |= 0 if d.y >= scale else 1

			var offset = CLIPMAP_VERT_RESOLUTION * scale

			var rotations = {
				0: {
					'angle': 0,
					'offset': Vector2(0, 0),
				},
				1: {
					'angle': 90,
					'offset': Vector2(offset, 0),
				},
				2: {
					'angle': 270,
					'offset': Vector2(0, offset),
				},
				3: {
					'angle': 180,
					'offset': Vector2(offset, offset),
				},
			}

			var trim : MeshInstance

			if trims.has(scale):
				var mesh_instance_id = trims.get(scale)
				trim = instance_from_id(mesh_instance_id)
			else:
				trim = MeshInstance.new()
				trim.material_override = terrain_material
				trim.mesh = trim_mesh
				trims[scale] = trim.get_instance_id()
				add_child(trim)

			var next_base = next_snapped_position - Vector2(TILE_RESOLUTION << (level + 1), TILE_RESOLUTION << (level + 1))

			trim.scale = Vector3(scale, 1, scale)
			trim.rotation_degrees = Vector3(0, rotations[r]['angle'], 0)
			trim.translation = Vector3(next_base.x + rotations[r]['offset'].y, 0, next_base.y + rotations[r]['offset'].x)

			custom_aabb = trim.get_aabb()
			custom_aabb.size.y = MAX_CHUNK_HEIGHT
			trim.set_custom_aabb(custom_aabb)

			var seam : MeshInstance

			if seams.has(scale):
				var mesh_instance_id = seams.get(scale)
				seam = instance_from_id(mesh_instance_id)
			else:
				seam = MeshInstance.new()
				seam.material_override = terrain_material
				seam.mesh = seam_mesh
				seams[scale] = seam.get_instance_id()
				add_child(seam)

			seam.scale = Vector3(scale, 1, scale)
			seam.translation = Vector3(next_base.x, 0, next_base.y)


func _generate_cross_mesh():
	var vertices = PoolVector3Array()
	vertices.resize(PATCH_VERT_RESOLUTION * 8)
	var vertices_index = 0;

	for i in range(PATCH_VERT_RESOLUTION * 2):
		vertices[vertices_index] = Vector3(i - TILE_RESOLUTION, 0, 0)
		vertices_index += 1
		vertices[vertices_index] = Vector3(i - TILE_RESOLUTION, 0, 1)
		vertices_index += 1

	var start_of_vertical = vertices_index

	for i in range(PATCH_VERT_RESOLUTION * 2):
		vertices[vertices_index] = Vector3(0, 0, i - TILE_RESOLUTION)
		vertices_index += 1
		vertices[vertices_index] = Vector3(1, 0, i - TILE_RESOLUTION)
		vertices_index += 1

	assert(vertices_index == vertices.size())

	var indices = PoolIntArray()
	indices.resize(TILE_RESOLUTION * 24 + 6)
	var indices_index = 0;

	for i in range(TILE_RESOLUTION * 2 + 1):
		var bl = i * 2 + 0
		var br = i * 2 + 1
		var tl = i * 2 + 2
		var tr = i * 2 + 3

		indices[indices_index] = br
		indices_index += 1
		indices[indices_index] = bl
		indices_index += 1
		indices[indices_index] = tr
		indices_index += 1
		indices[indices_index] = bl
		indices_index += 1
		indices[indices_index] = tl
		indices_index += 1
		indices[indices_index] = tr
		indices_index += 1

	for i in range(TILE_RESOLUTION * 2 + 1):
		if i == TILE_RESOLUTION:
			continue

		var bl = i * 2 + 0
		var br = i * 2 + 1
		var tl = i * 2 + 2
		var tr = i * 2 + 3

		indices[indices_index] = start_of_vertical + br
		indices_index += 1
		indices[indices_index] = start_of_vertical + tr
		indices_index += 1
		indices[indices_index] = start_of_vertical + bl
		indices_index += 1
		indices[indices_index] = start_of_vertical + bl
		indices_index += 1
		indices[indices_index] = start_of_vertical + tr
		indices_index += 1
		indices[indices_index] = start_of_vertical + tl
		indices_index += 1

	assert(indices_index == indices.size())

	var array_mesh = ArrayMesh.new()

	var arrays = []
	arrays.resize(ArrayMesh.ARRAY_MAX)
	arrays[ArrayMesh.ARRAY_VERTEX] = vertices
	arrays[ArrayMesh.ARRAY_INDEX] = indices

	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	return array_mesh

func _generate_tile_mesh():
	var vertices = PoolVector3Array()
	vertices.resize(PATCH_VERT_RESOLUTION * PATCH_VERT_RESOLUTION)
	var vertices_index = 0;

	for y in range(PATCH_VERT_RESOLUTION):
		for x in range(PATCH_VERT_RESOLUTION):
			vertices[vertices_index] = Vector3(x, 0, y)
			vertices_index += 1

	assert(vertices_index == vertices.size())

	var indices = PoolIntArray()
	indices.resize(TILE_RESOLUTION * TILE_RESOLUTION * 6)
	var indices_index = 0;

	for y in range(TILE_RESOLUTION):
		for x in range(TILE_RESOLUTION):
			indices[indices_index] = _patch_2d(x, y)
			indices_index += 1
			indices[indices_index] = _patch_2d(x + 1, y + 1)
			indices_index += 1
			indices[indices_index] = _patch_2d(x, y + 1)
			indices_index += 1

			indices[indices_index] = _patch_2d(x, y)
			indices_index += 1
			indices[indices_index] = _patch_2d(x + 1, y)
			indices_index += 1
			indices[indices_index] = _patch_2d(x + 1, y + 1)
			indices_index += 1

	assert(indices_index == indices.size())

	var array_mesh = ArrayMesh.new()

	var arrays = []
	arrays.resize(ArrayMesh.ARRAY_MAX)
	arrays[ArrayMesh.ARRAY_VERTEX] = vertices
	arrays[ArrayMesh.ARRAY_INDEX] = indices
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	return array_mesh

func _generate_trim_mesh():
	var vertices = PoolVector3Array()
	vertices.resize((CLIPMAP_VERT_RESOLUTION * 2 + 1) * 2)
	var vertices_index = 0;

	for i in range(CLIPMAP_VERT_RESOLUTION + 1):
		vertices[vertices_index] = Vector3(0, 0, CLIPMAP_VERT_RESOLUTION - i)
		vertices_index += 1
		vertices[vertices_index] = Vector3(1, 0, CLIPMAP_VERT_RESOLUTION - i)
		vertices_index += 1

	var start_of_horizontal = vertices_index

	for i in range(CLIPMAP_VERT_RESOLUTION):
		vertices[vertices_index] = Vector3(i + 1, 0, 0)
		vertices_index += 1
		vertices[vertices_index] = Vector3(i + 1, 0, 1)
		vertices_index += 1

	assert(vertices_index == vertices.size())

	for vector in vertices:
		vector -= Vector3(0.5 * (CLIPMAP_VERT_RESOLUTION + 1), 0.5 * (CLIPMAP_VERT_RESOLUTION + 1), 0)

	var indices = PoolIntArray()
	indices.resize((CLIPMAP_VERT_RESOLUTION * 2 - 1) * 6)
	var indices_index = 0;

	for i in range(CLIPMAP_VERT_RESOLUTION):
		indices[indices_index] = (i + 0) * 2 + 1
		indices_index += 1
		indices[indices_index] = (i + 0) * 2 + 0
		indices_index += 1
		indices[indices_index] = (i + 1) * 2 + 0
		indices_index += 1

		indices[indices_index] = (i + 1) * 2 + 1
		indices_index += 1
		indices[indices_index] = (i + 0) * 2 + 1
		indices_index += 1
		indices[indices_index] = (i + 1) * 2 + 0
		indices_index += 1

	for i in range(CLIPMAP_VERT_RESOLUTION - 1):
		indices[indices_index] = start_of_horizontal + (i + 0) * 2 + 1
		indices_index += 1
		indices[indices_index] = start_of_horizontal + (i + 0) * 2 + 0
		indices_index += 1
		indices[indices_index] = start_of_horizontal + (i + 1) * 2 + 0
		indices_index += 1

		indices[indices_index] = start_of_horizontal + (i + 1) * 2 + 1
		indices_index += 1
		indices[indices_index] = start_of_horizontal + (i + 0) * 2 + 1
		indices_index += 1
		indices[indices_index] = start_of_horizontal + (i + 1) * 2 + 0
		indices_index += 1

	assert(indices_index == indices.size())

	var array_mesh = ArrayMesh.new()

	var arrays = []
	arrays.resize(ArrayMesh.ARRAY_MAX)
	arrays[ArrayMesh.ARRAY_VERTEX] = vertices
	arrays[ArrayMesh.ARRAY_INDEX] = indices
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	return array_mesh

func _generate_filler_mesh():
	var vertices = PoolVector3Array()
	vertices.resize(PATCH_VERT_RESOLUTION * 8)
	var vertices_index = 0;
	var offset = TILE_RESOLUTION

	for i in range(PATCH_VERT_RESOLUTION):
		vertices[vertices_index] = Vector3(offset + i + 1, 0, 0)
		vertices_index += 1
		vertices[vertices_index] = Vector3(offset + i + 1, 0, 1)
		vertices_index += 1

	for i in range(PATCH_VERT_RESOLUTION):
		vertices[vertices_index] = Vector3(1, 0, offset + i + 1)
		vertices_index += 1
		vertices[vertices_index] = Vector3(0, 0, offset + i + 1)
		vertices_index += 1

	for i in range(PATCH_VERT_RESOLUTION):
		vertices[vertices_index] = Vector3(-(offset + i), 0, 1)
		vertices_index += 1
		vertices[vertices_index] = Vector3(-(offset + i), 0, 0)
		vertices_index += 1

	for i in range(PATCH_VERT_RESOLUTION):
		vertices[vertices_index] = Vector3(0, 0, -(offset + i))
		vertices_index += 1
		vertices[vertices_index] = Vector3(1, 0, -(offset + i))
		vertices_index += 1

	assert(vertices_index == vertices.size())

	var indices = PoolIntArray()
	indices.resize(TILE_RESOLUTION * 24)
	var indices_index = 0;

	for i in range(TILE_RESOLUTION * 4):
		var arm : int = i / TILE_RESOLUTION

		var bl = (arm + i) * 2 + 0
		var br = (arm + i) * 2 + 1
		var tl = (arm + i) * 2 + 2
		var tr = (arm + i) * 2 + 3

		if arm % 2 == 0:
			indices[indices_index] = br
			indices_index += 1
			indices[indices_index] = bl
			indices_index += 1
			indices[indices_index] = tr
			indices_index += 1
			indices[indices_index] = bl
			indices_index += 1
			indices[indices_index] = tl
			indices_index += 1
			indices[indices_index] = tr
			indices_index += 1
		else:
			indices[indices_index] = br
			indices_index += 1
			indices[indices_index] = bl
			indices_index += 1
			indices[indices_index] = tl
			indices_index += 1
			indices[indices_index] = br
			indices_index += 1
			indices[indices_index] = tl
			indices_index += 1
			indices[indices_index] = tr
			indices_index += 1

	assert(indices_index == indices.size())

	var array_mesh = ArrayMesh.new()

	var arrays = []
	arrays.resize(ArrayMesh.ARRAY_MAX)
	arrays[ArrayMesh.ARRAY_VERTEX] = vertices
	arrays[ArrayMesh.ARRAY_INDEX] = indices
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	return array_mesh

func _generate_seam_mesh():
	var vertices = PoolVector3Array()
	vertices.resize(CLIPMAP_VERT_RESOLUTION * 4)
	var vertices_index = 0;

	for i in range(CLIPMAP_VERT_RESOLUTION):
		vertices[CLIPMAP_VERT_RESOLUTION * 0 + i] = Vector3(i, 0, 0)
		vertices[CLIPMAP_VERT_RESOLUTION * 1 + i] = Vector3(CLIPMAP_VERT_RESOLUTION, 0, i)
		vertices[CLIPMAP_VERT_RESOLUTION * 2 + i] = Vector3(CLIPMAP_VERT_RESOLUTION - i, 0, CLIPMAP_VERT_RESOLUTION)
		vertices[CLIPMAP_VERT_RESOLUTION * 3 + i] = Vector3(0, 0, CLIPMAP_VERT_RESOLUTION - i)

	var indices = PoolIntArray()
	indices.resize(CLIPMAP_VERT_RESOLUTION  * 6)
	var indices_index = 0;

	for i in range(0, CLIPMAP_VERT_RESOLUTION * 4, 2):
		indices[indices_index] = i + 1
		indices_index += 1
		indices[indices_index] = i
		indices_index += 1
		indices[indices_index] = i + 2
		indices_index += 1

	indices[indices.size() - 1] = 0

	assert(indices_index == indices.size())

	var array_mesh = ArrayMesh.new()

	var arrays = []
	arrays.resize(ArrayMesh.ARRAY_MAX)
	arrays[ArrayMesh.ARRAY_VERTEX] = vertices
	arrays[ArrayMesh.ARRAY_INDEX] = indices
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	return array_mesh

func _patch_2d(x, y):
	return y * PATCH_VERT_RESOLUTION + x
