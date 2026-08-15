class_name ScreenHome
extends Control

# Title screen. Edit these four strings to change the billing.
const COMPANY := "Researchase"
const TITLE := "3D Resin Printing"
const SUBTITLE := "How an LCD/MSLA printer turns a liquid into a solid object"
const PRESENTER := "Ashwin Venkat"

const SECTIONS := [
	["The chemistry", "Why UV light makes liquid resin harden — monomers, radicals and cross-links"],
	["The printer", "A working MSLA machine: LCD mask, UV array and the layer-by-layer build"],
	["Safety", "Why resin demands gloves, ventilation and proper disposal"],
]

const HERO_LAYERS := 36

signal start_pressed

var hero: Node3D
var spin := 0.0


func _ready() -> void:
	_build_3d()
	_build_text()


func _build_3d() -> void:
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(svc)

	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	svc.add_child(vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = UIKit.C_BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.38, 0.5)
	env.ambient_light_energy = 0.5
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -50, 0)
	key.light_energy = 1.3
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, 130, 0)
	rim.light_energy = 0.9
	rim.light_color = UIKit.C_UV
	vp.add_child(rim)

	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.position = Vector3(0, 0.4, 14.0)
	vp.add_child(cam)

	hero = Node3D.new()
	hero.position = Vector3(4.2, -2.6, 0)
	vp.add_child(hero)
	hero.add_child(_build_hero_mesh())


# The vase from the printer screen, stacked upright out of its own layer masks.
func _build_hero_mesh() -> MultiMeshInstance3D:
	var layer_h := ResinSlicer.MODEL_HEIGHT / float(HERO_LAYERS)
	var box := BoxMesh.new()
	box.size = Vector3(ResinSlicer.CELL, layer_h, ResinSlicer.CELL)

	var transforms: Array[Transform3D] = []
	var half_w := float(ResinSlicer.MASK_W) * 0.5
	var half_h := float(ResinSlicer.MASK_H) * 0.5
	for i in HERO_LAYERS:
		var data := ResinSlicer.slice_layer(ResinSlicer.Model.VASE,
			(float(i) + 0.5) / float(HERO_LAYERS))
		var cells: PackedInt32Array = data["cells"]
		for c in cells:
			@warning_ignore("integer_division")
			var gy := c / ResinSlicer.MASK_W
			var gx := c % ResinSlicer.MASK_W
			transforms.append(Transform3D(Basis(), Vector3(
				(float(gx) + 0.5 - half_w) * ResinSlicer.CELL,
				(float(i) + 0.5) * layer_h,
				(float(gy) + 0.5 - half_h) * ResinSlicer.CELL)))

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.94, 0.86, 0.66)
	mat.roughness = 0.35
	mat.rim_enabled = true
	mat.rim = 0.6

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	return mmi


func _build_text() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 90)
	margin.add_theme_constant_override("margin_top", 70)
	margin.add_theme_constant_override("margin_bottom", 60)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	margin.add_child(col)

	var brand := UIKit.label(COMPANY.to_upper(), 17, UIKit.C_UV, true)
	brand.add_theme_constant_override("line_spacing", 0)
	col.add_child(brand)
	col.add_child(UIKit.spacer(18))

	var title := UIKit.label(TITLE, 62, UIKit.C_TEXT)
	col.add_child(title)
	col.add_child(UIKit.spacer(10))
	col.add_child(UIKit.wrap_label(SUBTITLE, 19, UIKit.C_DIM, 620))
	col.add_child(UIKit.spacer(26))

	var by := HBoxContainer.new()
	by.add_theme_constant_override("separation", 10)
	by.add_child(UIKit.label("Workshop", 15, UIKit.C_DIM))
	by.add_child(UIKit.label("·", 15, UIKit.C_PANEL2))
	by.add_child(UIKit.label(PRESENTER, 15, UIKit.C_TEXT))
	col.add_child(by)
	col.add_child(UIKit.spacer(38))

	for i in SECTIONS.size():
		var card := UIKit.card(UIKit.C_PANEL, UIKit.C_PANEL2, 1)
		card.custom_minimum_size = Vector2(620, 0)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		var num := UIKit.label(str(i + 2), 20, UIKit.C_UV)
		num.custom_minimum_size = Vector2(26, 0)
		num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(num)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		v.add_child(UIKit.label(SECTIONS[i][0], 16, UIKit.C_TEXT))
		v.add_child(UIKit.wrap_label(SECTIONS[i][1], 12, UIKit.C_DIM, 540))
		h.add_child(v)
		card.add_child(h)
		col.add_child(card)
		col.add_child(UIKit.spacer(8))

	col.add_child(UIKit.spacer(26))
	var start := UIKit.button("Start  ▶", func(): start_pressed.emit(), 16, 46)
	start.custom_minimum_size = Vector2(200, 46)
	start.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	start.add_theme_color_override("font_color", UIKit.C_TEXT)
	start.add_theme_stylebox_override("normal",
		UIKit.stylebox(Color("2a2140"), UIKit.C_UV, 2, 6, 18))
	start.add_theme_stylebox_override("hover",
		UIKit.stylebox(Color("372a55"), UIKit.C_UV, 2, 6, 18))
	col.add_child(start)
	col.add_child(UIKit.spacer(14))
	col.add_child(UIKit.label("keys 1-4 or ◀ ▶ move between sections", 12, UIKit.C_DIM))


func _process(delta: float) -> void:
	spin += delta * 0.35
	if hero:
		hero.rotation.y = spin
