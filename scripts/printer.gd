class_name PrinterRig
extends Node3D

# The 3D machine: resin vat, LCD photomask, UV LED array, Z-axis build plate,
# and the part that accumulates one cured layer at a time.
#
# Real MSLA printers print UPSIDE DOWN: the plate dips to one layer height above
# the glass, the LCD masks the UV, the layer cures against the film, then the
# plate peels up. The part hangs below the plate as it grows.

const BUILD_W := ResinSlicer.BUILD_W
const BUILD_D := ResinSlicer.BUILD_D
const PLATE_W := 6.4
const PLATE_D := 5.6
const PLATE_T := 0.26
const VAT_H := 3.2
const RESIN_LEVEL := 1.6

var pivot: Node3D
var camera: Camera3D
var plate: Node3D            # origin sits at the BOTTOM face of the build plate
var screw: MeshInstance3D
var beam: MeshInstance3D
var uv_light: SpotLight3D
var part_marker: Node3D
var markers: Array = []      # [{node: Node3D, text: String}]

var lcd_mat: StandardMaterial3D
var beam_mat: StandardMaterial3D
var uv_panel_mat: StandardMaterial3D
var cured_mat: StandardMaterial3D
var voxel_mesh: BoxMesh

var layer_h := 0.125
var layers: Array[MultiMeshInstance3D] = []
var display_root: Node3D     # holds the finished part when flipped upright
var _plate_entries := []
var _finished_entry := {}
var _plate_y_saved := 0.0

const DISPLAY_Y := 3.8       # where the flipped-upright part stands, clear of the vat
const PARKED_AWAY_Y := 13.5  # plate gets moved clear while showing the part

var yaw := -0.60
var pitch := -0.24
var dist := 23.0
var follow_y := 1.8

var _fresh_mats: Array[StandardMaterial3D] = []


func _ready() -> void:
	_build_environment()
	_build_machine()
	_build_vat()
	_build_lcd_stack()
	_build_z_axis()
	update_camera()


# ---------------------------------------------------------------- construction

func _mat(color: Color, rough := 0.5, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m


func _glass(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.08
	m.metallic = 0.2
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _marker(pos: Vector3, text: String, parent: Node3D) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	markers.append({"node": n, "text": text, "hidden": false})
	return n


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.045, 0.05, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.46, 0.58)
	env.ambient_light_energy = 0.65
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52, -35, 0)
	key.light_energy = 1.0
	key.shadow_enabled = true
	add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-12, 155, 0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.7, 0.8, 1.0)
	add_child(fill)

	# Grazing light from the front so the part hanging under the plate is readable.
	var part_light := DirectionalLight3D.new()
	part_light.rotation_degrees = Vector3(-6, 8, 0)
	part_light.light_energy = 0.6
	part_light.light_color = Color(1.0, 0.95, 0.88)
	add_child(part_light)

	pivot = Node3D.new()
	pivot.position = Vector3(0, 1.8, 0)
	add_child(pivot)
	camera = Camera3D.new()
	camera.fov = 42.0
	camera.near = 0.05
	camera.far = 200.0
	pivot.add_child(camera)


func _build_machine() -> void:
	var body := _mat(Color(0.10, 0.11, 0.14), 0.6)
	_box(Vector3(17.0, 1.4, 13.0), Vector3(0, -1.5, 0), body, self)          # plinth
	_box(Vector3(17.0, 0.25, 13.0), Vector3(0, -0.72, 0), _mat(Color(0.09, 0.10, 0.13), 0.4), self)


func _build_vat() -> void:
	var glass := _glass(Color(0.55, 0.68, 0.82, 0.07))
	var rim := _mat(Color(0.22, 0.24, 0.30), 0.45, 0.6)
	var ow := BUILD_W + 0.9
	var od := BUILD_D + 0.9
	var t := 0.28
	# four vat walls
	_box(Vector3(ow, VAT_H, t), Vector3(0, VAT_H * 0.5, -od * 0.5), glass, self)
	_box(Vector3(ow, VAT_H, t), Vector3(0, VAT_H * 0.5, od * 0.5), glass, self)
	_box(Vector3(t, VAT_H, od), Vector3(-ow * 0.5, VAT_H * 0.5, 0), glass, self)
	_box(Vector3(t, VAT_H, od), Vector3(ow * 0.5, VAT_H * 0.5, 0), glass, self)
	# metal rim on top of the vat
	_box(Vector3(ow + 0.3, 0.22, od + 0.3), Vector3(0, VAT_H + 0.11, 0), rim, self)

	# liquid resin
	var resin := _glass(Color(0.72, 0.36, 0.10, 0.07))
	resin.roughness = 0.45
	resin.metallic = 0.0
	_box(Vector3(ow - 0.3, RESIN_LEVEL, od - 0.3), Vector3(0, RESIN_LEVEL * 0.5, 0), resin, self)

	_marker(Vector3(-ow * 0.5 - 0.2, 0.5, od * 0.5), "Resin vat", self)


func _build_lcd_stack() -> void:
	# LCD photomask: its top face is exactly y = 0, the plane every layer cures against.
	# The panel itself is near-black and does not react to scene lights - the only
	# thing you see on it is the mask, glowing exactly where UV gets through.
	lcd_mat = StandardMaterial3D.new()
	lcd_mat.albedo_color = Color(0.015, 0.015, 0.022)
	lcd_mat.roughness = 0.9
	lcd_mat.metallic = 0.0
	lcd_mat.disable_ambient_light = true
	lcd_mat.emission_enabled = true
	lcd_mat.emission = Color(0.85, 0.72, 1.0)
	lcd_mat.emission_energy_multiplier = 0.5
	lcd_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# A flat quad, not a box: BoxMesh gives each face only a sub-rect of the texture,
	# which would show the mask at the wrong scale.
	var screen := PlaneMesh.new()
	screen.size = Vector2(BUILD_W, BUILD_D)
	var screen_mi := MeshInstance3D.new()
	screen_mi.mesh = screen
	screen_mi.material_override = lcd_mat
	screen_mi.position = Vector3(0, 0.005, 0)
	add_child(screen_mi)
	# dark glass sandwich under the screen
	_box(Vector3(BUILD_W, 0.12, BUILD_D), Vector3(0, -0.06, 0),
		_mat(Color(0.02, 0.02, 0.03), 0.8), self)
	# LCD bezel
	_box(Vector3(BUILD_W + 0.8, 0.14, BUILD_D + 0.8), Vector3(0, -0.14, 0),
		_mat(Color(0.10, 0.11, 0.14), 0.5), self)

	# UV LED array underneath
	uv_panel_mat = StandardMaterial3D.new()
	uv_panel_mat.albedo_color = Color(0.30, 0.18, 0.55)
	uv_panel_mat.emission_enabled = true
	uv_panel_mat.emission = Color(0.55, 0.30, 1.0)
	uv_panel_mat.emission_energy_multiplier = 0.15
	_box(Vector3(BUILD_W - 0.6, 0.30, BUILD_D - 0.6), Vector3(0, -0.75, 0), uv_panel_mat, self)

	# A tight light just above the mask, so the layer being cured is lit from below
	# without spilling across the whole vat. Range is barely more than the layer gap.
	uv_light = SpotLight3D.new()
	uv_light.position = Vector3(0, -0.15, 0)
	uv_light.rotation_degrees = Vector3(90, 0, 0)     # aim straight up
	uv_light.light_color = Color(0.72, 0.50, 1.0)
	uv_light.spot_range = 1.6
	uv_light.spot_angle = 30.0
	uv_light.spot_attenuation = 2.0
	uv_light.light_energy = 0.0
	add_child(uv_light)

	# The visible column of UV light passing through the mask into the layer gap.
	beam_mat = StandardMaterial3D.new()
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.albedo_color = Color(0.72, 0.52, 1.0, 0.85)
	beam_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam_mat.no_depth_test = false
	var beam_mesh := PlaneMesh.new()
	beam_mesh.size = Vector2(BUILD_W, BUILD_D)
	beam = MeshInstance3D.new()
	beam.mesh = beam_mesh
	beam.material_override = beam_mat
	beam.visible = false
	add_child(beam)

	_marker(Vector3(BUILD_W * 0.5 + 0.5, 0.0, -BUILD_D * 0.3), "LCD photomask", self)
	_marker(Vector3(-BUILD_W * 0.35, -0.75, BUILD_D * 0.5 + 0.9), "UV LEDs (405 nm)", self)


func _build_z_axis() -> void:
	var metal := _mat(Color(0.42, 0.45, 0.52), 0.35, 0.85)
	var dark := _mat(Color(0.13, 0.14, 0.17), 0.5)
	var col_z := -(BUILD_D * 0.5 + 1.9)
	_box(Vector3(2.6, 14.0, 1.5), Vector3(0, 6.2, col_z), dark, self)

	var screw_mesh := CylinderMesh.new()
	screw_mesh.top_radius = 0.20
	screw_mesh.bottom_radius = 0.20
	screw_mesh.height = 12.6
	screw = MeshInstance3D.new()
	screw.mesh = screw_mesh
	screw.material_override = metal
	screw.position = Vector3(0, 6.3, col_z + 0.85)
	add_child(screw)
	_marker(Vector3(0.9, 9.8, col_z + 0.85), "Z axis (lead screw)", self)

	# Build plate. Its origin is the bottom face - layers hang below it.
	plate = Node3D.new()
	add_child(plate)
	_box(Vector3(PLATE_W, PLATE_T, PLATE_D), Vector3(0, PLATE_T * 0.5, 0),
		_mat(Color(0.46, 0.48, 0.54), 0.50, 0.55), plate)
	_box(Vector3(1.3, 0.5, 5.0), Vector3(0, PLATE_T + 0.25, col_z * 0.5), dark, plate)
	_box(Vector3(1.9, 1.1, 1.2), Vector3(0, PLATE_T + 0.4, col_z + 0.85), metal, plate)
	_marker(Vector3(PLATE_W * 0.5 + 0.3, PLATE_T, -PLATE_D * 0.3), "Build plate", plate)
	_plate_entries.append(markers[-1])
	part_marker = _marker(Vector3(-PLATE_W * 0.5 - 0.3, -0.4, 0),
		"Part (prints upside-down)", plate)
	_plate_entries.append(markers[-1])

	# Shown only once the print is done and the part is flipped upright.
	_marker(Vector3(1.9, DISPLAY_Y + ResinSlicer.MODEL_HEIGHT * 0.6, 0),
		"Finished part — the first layer printed ends up on top", self)
	_finished_entry = markers[-1]
	_finished_entry["hidden"] = true

	cured_mat = _mat(Color(0.94, 0.86, 0.66), 0.32)
	cured_mat.rim_enabled = true
	cured_mat.rim = 0.55


# ---------------------------------------------------------------- printing API

func configure(new_layer_h: float) -> void:
	layer_h = new_layer_h
	voxel_mesh = BoxMesh.new()
	voxel_mesh.size = Vector3(ResinSlicer.CELL, layer_h, ResinSlicer.CELL)
	# The lit shape sits just under the layer being cured.
	beam.position = Vector3(0, layer_h * 0.92, 0)


func set_plate_y(y: float) -> void:
	plate.position.y = y
	screw.rotation.y = y * 3.2      # lead screw turns as the axis travels


func set_mask(tex: Texture2D) -> void:
	# Only the emission channel carries the mask, so black pixels stay truly black.
	lcd_mat.emission_texture = tex
	beam_mat.albedo_texture = tex


func set_uv(on: bool, intensity := 1.0) -> void:
	beam.visible = on
	uv_light.light_energy = 2.0 * intensity if on else 0.0
	lcd_mat.emission_energy_multiplier = (2.6 * intensity) if on else 0.5
	uv_panel_mat.emission_energy_multiplier = (1.2 * intensity) if on else 0.15
	if on:
		beam_mat.albedo_color = Color(0.72, 0.52, 1.0, 0.35 + 0.5 * intensity)


# Solidify one layer: one small box per lit LCD pixel, parented to the plate.
@warning_ignore("integer_division")
func add_layer(cells: PackedInt32Array, index: int) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = voxel_mesh
	mm.instance_count = cells.size()
	var half_w := float(ResinSlicer.MASK_W) * 0.5
	var half_h := float(ResinSlicer.MASK_H) * 0.5
	for i in cells.size():
		var c := cells[i]
		var gx := c % ResinSlicer.MASK_W
		var gy := int(c / ResinSlicer.MASK_W)
		var x := (float(gx) + 0.5 - half_w) * ResinSlicer.CELL
		var z := (float(gy) + 0.5 - half_h) * ResinSlicer.CELL
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(x, 0, z)))

	var fresh := cured_mat.duplicate() as StandardMaterial3D
	fresh.emission_enabled = true
	fresh.emission = Color(0.72, 0.48, 1.0)
	fresh.emission_energy_multiplier = 3.0

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = fresh
	mmi.position = Vector3(0, -(float(index) + 0.5) * layer_h, 0)
	plate.add_child(mmi)
	layers.append(mmi)
	_fresh_mats.append(fresh)
	part_marker.position.y = -0.5 * layer_h * float(index + 1)


# Called every frame with the elapsed sim time so fresh layers cool off.
func fade_fresh_layers(delta: float) -> void:
	for i in range(_fresh_mats.size() - 1, -1, -1):
		var m := _fresh_mats[i]
		m.emission_energy_multiplier = maxf(0.0, m.emission_energy_multiplier - delta * 4.0)
		if m.emission_energy_multiplier <= 0.01:
			m.emission_enabled = false
			_fresh_mats.remove_at(i)


func clear_layers() -> void:
	for l in layers:
		l.queue_free()
	layers.clear()
	_fresh_mats.clear()
	if display_root and is_instance_valid(display_root):
		display_root.queue_free()
		display_root = null
	part_marker.position.y = -0.4


# Detach the finished part and flip it upright, the way you'd see it after
# cutting it off the plate.
func show_finished(upright: bool) -> void:
	for e in _plate_entries:
		e["hidden"] = upright
	_finished_entry["hidden"] = not upright
	if upright:
		if display_root and is_instance_valid(display_root):
			return
		# Move the plate clear, then stand the part up above the vat.
		_plate_y_saved = plate.position.y
		set_plate_y(PARKED_AWAY_Y)
		display_root = Node3D.new()
		# Flipping about X maps layer local -y to +y, so the origin is the part's base.
		display_root.position = Vector3(0, DISPLAY_Y, 0)
		display_root.rotation_degrees = Vector3(180, 0, 0)
		add_child(display_root)
		for l in layers:
			var t := l.position
			plate.remove_child(l)
			display_root.add_child(l)
			l.position = t
	else:
		if not (display_root and is_instance_valid(display_root)):
			return
		for l in layers:
			var t := l.position
			display_root.remove_child(l)
			plate.add_child(l)
			l.position = t
		display_root.queue_free()
		display_root = null
		set_plate_y(_plate_y_saved)


# ---------------------------------------------------------------- camera

func orbit(delta_x: float, delta_y: float) -> void:
	yaw -= delta_x * 0.006
	pitch = clampf(pitch - delta_y * 0.006, -1.35, 0.5)
	update_camera()


func zoom(amount: float) -> void:
	dist = clampf(dist + amount, 9.0, 55.0)
	update_camera()


func update_camera() -> void:
	pivot.rotation = Vector3(pitch, yaw, 0)
	camera.position = Vector3(0, 0, dist)


# Keep the growing part roughly centred in frame as the plate climbs.
func follow(plate_y: float, delta: float) -> void:
	var target := clampf(plate_y * 0.5 + 0.3, 1.2, 4.2)
	follow_y = lerpf(follow_y, target, clampf(delta * 2.0, 0.0, 1.0))
	pivot.position.y = follow_y
