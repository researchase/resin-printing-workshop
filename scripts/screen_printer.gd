class_name ScreenPrinter
extends Control

# MSLA / LCD resin printer simulator for a workshop.
# Left: the machine in 3D.  Right: the LCD mask the printer is showing right now.

enum Phase { IDLE, LOWER, EXPOSE, CURE, LIFT, FINISH, DONE }

const DUR_LOWER := 0.55
const DUR_EXPOSE := 0.90
const DUR_CURE := 0.30
const DUR_LIFT := 0.60
const DEMO_LAYER_TIME := DUR_LOWER + DUR_EXPOSE + DUR_CURE + DUR_LIFT

# What the real machine takes per layer, in seconds.
const REAL_LOWER := 1.8
const REAL_EXPOSE := 2.5
const REAL_LIFT := 4.2
const REAL_LAYER_TIME := REAL_LOWER + REAL_EXPOSE + REAL_LIFT

const PARK_Y := 8.6
const PEEL_LIFT := 1.5

# demo_layers is what we animate; real_um is the actual layer height it stands for.
const PRESETS := [
	{"label": "0.100 mm  (draft)", "demo_layers": 20, "real_um": 100.0},
	{"label": "0.050 mm  (normal)", "demo_layers": 40, "real_um": 50.0},
	{"label": "0.025 mm  (fine)", "demo_layers": 80, "real_um": 25.0},
]

const PHASE_STEPS := [
	["1  LOWER", "Build plate dips to one layer height above the glass."],
	["2  EXPOSE", "UV shines up through the LCD. White pixels let light through."],
	["3  CURE", "Resin hardens in exactly that shape and bonds to the layer above."],
	["4  PEEL", "Plate lifts to peel the layer off the film; fresh resin flows in."],
]

const C_BG := UIKit.C_BG
const C_PANEL := UIKit.C_PANEL
const C_PANEL2 := UIKit.C_PANEL2
const C_TEXT := UIKit.C_TEXT
const C_DIM := UIKit.C_DIM
const C_UV := UIKit.C_UV
const C_CURE := UIKit.C_CURE

var rig: PrinterRig
var sub_vp: SubViewport
var overlay: Control
var mask_rect: TextureRect
var mask_tex: ImageTexture
var progress: ProgressBar
var play_btn: Button
var upright_btn: Button
var model_opt: OptionButton
var preset_opt: OptionButton
var stat_labels := {}
var step_rows := []
var callout_labels: Array[Label] = []
var banner: Label
var hint: Label
var labels_on := true

var phase: int = Phase.IDLE
var phase_t := 0.0
var playing := false
var single_step := false
var speed := 1.0
var model_id := 0
var preset_id := 1
var layer_count := 40
var layer_h := 0.125
var layer_index := 0
var cur_cells := PackedInt32Array()
var plate_from := PARK_Y
var plate_to := PARK_Y
var plate_y := PARK_Y


var _selftest := false


func _ready() -> void:
	_build_ui()
	_reset()
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--model="):
			model_id = clampi(int(a.get_slice("=", 1)), 0, ResinSlicer.MODEL_NAMES.size() - 1)
			model_opt.selected = model_id
			_reset()
		elif a.begins_with("--preset="):
			preset_id = clampi(int(a.get_slice("=", 1)), 0, PRESETS.size() - 1)
			preset_opt.selected = preset_id
			_reset()
	if "--selftest" in args:
		_selftest = true
		speed = 25.0
	if "--autoplay" in args or _selftest:
		_toggle_play()
	if "--shot" in args:
		speed = 5.0
		if not playing:
			_toggle_play()
		_run_shots()


# Debug helper: grab a few frames of the running sim to PNG, then quit.
func _run_shots() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	if dir == "":
		dir = "user://"
	var n := 0
	for wait in [1.2, 3.0, 4.0, 5.0]:
		await get_tree().create_timer(wait).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/shot_%d.png" % [dir, n])
		n += 1
	# run the rest of the print fast, then flip the part upright and grab that too
	speed = 20.0
	while phase != Phase.DONE:
		await get_tree().process_frame
	upright_btn.button_pressed = true
	_toggle_upright()
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/shot_final.png" % dir)
	get_tree().quit()


# ------------------------------------------------------------------ UI layout

func _stylebox(bg: Color, border_col := Color(0, 0, 0, 0), border := 0, radius := 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	if border > 0:
		sb.border_color = border_col
		sb.set_border_width_all(border)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _label(text: String, font_size := 15, color := C_TEXT, bold_caps := false) -> Label:
	var l := Label.new()
	l.text = text.to_upper() if bold_caps else text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 0)
	add_child(row)

	# ---- left: 3D view + callout overlay
	var left := Control.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(left)

	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(svc)

	sub_vp = SubViewport.new()
	sub_vp.own_world_3d = true
	sub_vp.transparent_bg = false
	sub_vp.msaa_3d = Viewport.MSAA_4X
	sub_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(sub_vp)

	rig = PrinterRig.new()
	sub_vp.add_child(rig)

	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_view_input)
	left.add_child(overlay)

	banner = _label("", 20, C_TEXT)
	banner.position = Vector2(22, 18)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(banner)

	hint = _label("drag to orbit  ·  wheel to zoom  ·  space = play/pause  ·  s = one layer  ·  r = reset",
		12, C_DIM)
	hint.position = Vector2(22, 46)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(hint)

	var ls := LabelSettings.new()
	ls.font_size = 12
	ls.font_color = Color("cfd6e6")
	ls.outline_size = 5
	ls.outline_color = Color(0, 0, 0, 0.85)
	for i in 8:
		var cl := Label.new()
		cl.label_settings = ls
		cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cl.visible = false
		overlay.add_child(cl)
		callout_labels.append(cl)

	# ---- right: the LCD mask panel
	var side := PanelContainer.new()
	side.custom_minimum_size = Vector2(480, 0)
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_theme_stylebox_override("panel", _stylebox(C_PANEL, Color(0, 0, 0, 0), 0, 0))
	row.add_child(side)

	var margin := MarginContainer.new()
	for s in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(s, 18)
	side.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	col.add_child(_label("LCD photomask — live", 13, C_UV, true))
	var head := _label("Layer 0 / 40", 24, C_TEXT)
	stat_labels["head"] = head
	col.add_child(head)

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _stylebox(Color("05060a"), C_PANEL2, 2, 4))
	col.add_child(frame)
	mask_rect = TextureRect.new()
	mask_rect.custom_minimum_size = Vector2(426, 284)
	mask_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mask_rect.stretch_mode = TextureRect.STRETCH_SCALE
	mask_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.add_child(mask_rect)

	var cap := _label("white = UV passes through and cures resin   ·   black = blocked",
		11, C_DIM)
	col.add_child(cap)

	progress = ProgressBar.new()
	progress.custom_minimum_size = Vector2(0, 10)
	progress.show_percentage = false
	progress.max_value = 1.0
	progress.step = 0.0001
	col.add_child(progress)

	# stats grid
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	col.add_child(grid)
	for key in [["z", "Height printed"], ["area", "Exposed area"], ["px", "Demo LCD"],
			["real", "Real slice"], ["time", "Machine time"]]:
		grid.add_child(_label(key[1], 12, C_DIM))
		var v := _label("-", 12, C_TEXT)
		grid.add_child(v)
		stat_labels[key[0]] = v

	col.add_child(_sep())

	# phase stepper
	col.add_child(_label("the four-step layer cycle", 12, C_UV, true))
	for i in PHASE_STEPS.size():
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", _stylebox(C_PANEL2, Color(0, 0, 0, 0), 0, 4))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 1)
		var t := _label(PHASE_STEPS[i][0], 13, C_DIM)
		var d := _label(PHASE_STEPS[i][1], 11, C_DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(400, 0)
		v.add_child(t)
		v.add_child(d)
		p.add_child(v)
		col.add_child(p)
		step_rows.append({"panel": p, "title": t, "desc": d})

	col.add_child(_sep())

	# controls
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	col.add_child(btns)
	play_btn = _button("▶  Play", _toggle_play)
	play_btn.custom_minimum_size = Vector2(120, 34)
	btns.add_child(play_btn)
	btns.add_child(_button("Step layer", _step_layer))
	btns.add_child(_button("Reset", _reset))

	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 8)
	col.add_child(speed_row)
	speed_row.add_child(_label("Speed", 12, C_DIM))
	var sl := HSlider.new()
	sl.min_value = 0.25
	sl.max_value = 6.0
	sl.step = 0.25
	sl.value = 1.0
	sl.custom_minimum_size = Vector2(230, 0)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.value_changed.connect(_on_speed_changed)
	speed_row.add_child(sl)
	var sv := _label("1.0x", 12, C_TEXT)
	stat_labels["speed"] = sv
	speed_row.add_child(sv)

	var opts := GridContainer.new()
	opts.columns = 2
	opts.add_theme_constant_override("h_separation", 10)
	opts.add_theme_constant_override("v_separation", 6)
	col.add_child(opts)

	opts.add_child(_label("Model", 12, C_DIM))
	model_opt = OptionButton.new()
	for n in ResinSlicer.MODEL_NAMES:
		model_opt.add_item(n)
	model_opt.selected = model_id
	model_opt.item_selected.connect(_on_model_selected)
	opts.add_child(model_opt)

	opts.add_child(_label("Layer height", 12, C_DIM))
	preset_opt = OptionButton.new()
	for p in PRESETS:
		preset_opt.add_item(p["label"])
	preset_opt.selected = preset_id
	preset_opt.item_selected.connect(_on_preset_selected)
	opts.add_child(preset_opt)

	var extra := HBoxContainer.new()
	extra.add_theme_constant_override("separation", 8)
	col.add_child(extra)
	var cb := CheckBox.new()
	cb.text = "Part labels"
	cb.button_pressed = true
	cb.add_theme_font_size_override("font_size", 12)
	cb.toggled.connect(_on_labels_toggled)
	extra.add_child(cb)
	upright_btn = _button("View part upright", _toggle_upright)
	upright_btn.toggle_mode = true
	upright_btn.disabled = true
	extra.add_child(upright_btn)


func _on_speed_changed(v: float) -> void:
	speed = v
	_refresh_stats()


func _on_model_selected(i: int) -> void:
	model_id = i
	_reset()


func _on_preset_selected(i: int) -> void:
	preset_id = i
	_reset()


func _on_labels_toggled(v: bool) -> void:
	labels_on = v


func _sep() -> HSeparator:
	var s := HSeparator.new()
	s.add_theme_constant_override("separation", 8)
	return s


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 13)
	b.custom_minimum_size = Vector2(0, 34)
	b.pressed.connect(cb)
	return b


# ------------------------------------------------------------------ simulation

func _reset() -> void:
	playing = false
	single_step = false
	phase = Phase.IDLE
	phase_t = 0.0
	layer_index = 0
	layer_count = PRESETS[preset_id]["demo_layers"]
	layer_h = ResinSlicer.MODEL_HEIGHT / float(layer_count)
	plate_y = PARK_Y
	plate_from = PARK_Y
	plate_to = PARK_Y
	rig.clear_layers()
	rig.configure(layer_h)
	rig.set_plate_y(plate_y)
	rig.set_uv(false)
	upright_btn.disabled = true
	upright_btn.button_pressed = false
	play_btn.text = "▶  Play"
	_load_layer(0)
	_refresh_stats()
	_refresh_steps(-1)
	banner.text = "Ready — %d layers to print" % layer_count


func _load_layer(i: int) -> void:
	var w := (float(i) + 0.5) / float(layer_count)
	var data := ResinSlicer.slice_layer(model_id, w)
	cur_cells = data["cells"]
	var img: Image = data["image"]
	if mask_tex == null:
		mask_tex = ImageTexture.create_from_image(img)
		mask_rect.texture = mask_tex
		rig.set_mask(mask_tex)
	else:
		mask_tex.update(img)


func _toggle_play() -> void:
	if phase == Phase.DONE:
		_reset()
	playing = not playing
	single_step = false
	play_btn.text = "❚❚  Pause" if playing else "▶  Play"


func _step_layer() -> void:
	if phase == Phase.DONE:
		return
	playing = true
	single_step = true
	play_btn.text = "❚❚  Pause"


func _toggle_upright() -> void:
	rig.show_finished(upright_btn.button_pressed)


func _process(delta: float) -> void:
	var dt := delta * speed
	if playing and phase != Phase.DONE:
		_advance(dt)
	rig.fade_fresh_layers(dt)
	rig.follow(plate_y, delta)
	_update_callouts()


func _advance(dt: float) -> void:
	phase_t += dt
	match phase:
		Phase.IDLE:
			_begin_layer(0)
		Phase.LOWER:
			var t := clampf(phase_t / DUR_LOWER, 0.0, 1.0)
			plate_y = lerpf(plate_from, plate_to, ease(t, 0.4))
			if t >= 1.0:
				_set_phase(Phase.EXPOSE)
				rig.set_uv(true, 1.0)
		Phase.EXPOSE:
			var t2 := clampf(phase_t / DUR_EXPOSE, 0.0, 1.0)
			# pulse a little so the exposure reads as "light is on"
			rig.set_uv(true, 0.75 + 0.25 * sin(t2 * TAU * 3.0))
			if t2 >= 1.0:
				rig.set_uv(false)
				rig.add_layer(cur_cells, layer_index)
				_set_phase(Phase.CURE)
		Phase.CURE:
			if phase_t >= DUR_CURE:
				plate_from = plate_y
				plate_to = plate_y + PEEL_LIFT
				_set_phase(Phase.LIFT)
		Phase.LIFT:
			var t3 := clampf(phase_t / DUR_LIFT, 0.0, 1.0)
			plate_y = lerpf(plate_from, plate_to, ease(t3, 0.6))
			if t3 >= 1.0:
				if layer_index + 1 >= layer_count:
					plate_from = plate_y
					plate_to = PARK_Y
					_set_phase(Phase.FINISH)
				else:
					_begin_layer(layer_index + 1)
					if single_step:
						playing = false
						single_step = false
						play_btn.text = "▶  Play"
		Phase.FINISH:
			var t4 := clampf(phase_t / 1.4, 0.0, 1.0)
			plate_y = lerpf(plate_from, plate_to, ease(t4, 0.5))
			if t4 >= 1.0:
				phase = Phase.DONE
				playing = false
				play_btn.text = "▶  Play"
				upright_btn.disabled = false
				banner.text = "Print complete — %d layers" % layer_count
				_refresh_steps(-1)
				if _selftest:
					rig.show_finished(true)
					rig.show_finished(false)
					print("SELFTEST OK: %d layers, %d voxels in last layer" % [
						layer_count, cur_cells.size()])
					get_tree().quit()
	rig.set_plate_y(plate_y)
	_refresh_stats()


func _set_phase(p: int) -> void:
	phase = p
	phase_t = 0.0
	_refresh_steps(_step_of(p))
	match p:
		Phase.LOWER:
			banner.text = "Lowering build plate to layer %d" % (layer_index + 1)
		Phase.EXPOSE:
			banner.text = "Exposing layer %d — UV through the mask" % (layer_index + 1)
		Phase.CURE:
			banner.text = "Layer %d cured and bonded" % (layer_index + 1)
		Phase.LIFT:
			banner.text = "Peeling layer %d off the film" % (layer_index + 1)
		Phase.FINISH:
			banner.text = "Raising build plate"


func _begin_layer(i: int) -> void:
	layer_index = i
	_load_layer(i)
	plate_from = plate_y
	plate_to = float(i + 1) * layer_h     # gap of exactly one layer above the glass
	_set_phase(Phase.LOWER)


func _step_of(p: int) -> int:
	match p:
		Phase.LOWER: return 0
		Phase.EXPOSE: return 1
		Phase.CURE: return 2
		Phase.LIFT: return 3
	return -1


# ------------------------------------------------------------------ readouts

func _refresh_steps(active: int) -> void:
	for i in step_rows.size():
		var on := i == active
		step_rows[i]["panel"].add_theme_stylebox_override("panel",
			_stylebox(Color("2a2140") if on else C_PANEL2,
				C_UV if on else Color(0, 0, 0, 0), 2 if on else 0, 4))
		step_rows[i]["title"].add_theme_color_override("font_color", C_UV if on else C_DIM)
		step_rows[i]["desc"].add_theme_color_override("font_color", C_TEXT if on else C_DIM)


func _refresh_stats() -> void:
	var done := layer_index if phase != Phase.DONE else layer_count
	if phase in [Phase.CURE, Phase.LIFT]:
		done = layer_index + 1
	stat_labels["head"].text = "Layer %d / %d" % [mini(layer_index + 1, layer_count), layer_count]
	progress.value = float(done) / float(layer_count)

	var mm_per_layer := ResinSlicer.MODEL_HEIGHT * 10.0 / float(layer_count)
	stat_labels["z"].text = "%.1f mm of %.0f mm" % [done * mm_per_layer, ResinSlicer.MODEL_HEIGHT * 10.0]

	var px_mm := ResinSlicer.CELL * 10.0
	stat_labels["area"].text = "%.0f mm²  (%d lit pixels)" % [
		cur_cells.size() * px_mm * px_mm, cur_cells.size()]
	stat_labels["px"].text = "%d x %d px  ·  %.2f mm pixel" % [
		ResinSlicer.MASK_W, ResinSlicer.MASK_H, px_mm]

	var real_um: float = PRESETS[preset_id]["real_um"]
	var real_layers := int(round(ResinSlicer.MODEL_HEIGHT * 10000.0 / real_um))
	stat_labels["real"].text = "%d layers at %.3f mm" % [real_layers, real_um / 1000.0]

	var frac := float(done) / float(layer_count)
	var total := real_layers * REAL_LAYER_TIME
	stat_labels["time"].text = "%s of %s" % [_hms(frac * total), _hms(total)]
	stat_labels["speed"].text = "%.2fx" % speed


@warning_ignore("integer_division")
func _hms(sec: float) -> String:
	var s := int(sec)
	return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]


func _update_callouts() -> void:
	var cam := rig.camera
	var used := 0
	if labels_on:
		for entry in rig.markers:
			if used >= callout_labels.size() or entry["hidden"]:
				continue
			var p: Vector3 = (entry["node"] as Node3D).global_position
			if cam.is_position_behind(p):
				continue
			var l := callout_labels[used]
			l.visible = true
			l.text = "— " + str(entry["text"])
			l.position = cam.unproject_position(p) + Vector2(6, -8)
			used += 1
	for i in range(used, callout_labels.size()):
		callout_labels[i].visible = false


func _on_view_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT):
		rig.orbit(ev.relative.x, ev.relative.y)
	elif ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			rig.zoom(-1.6)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			rig.zoom(1.6)


func _unhandled_key_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey and ev.pressed and not ev.echo):
		return
	match ev.keycode:
		KEY_SPACE: _toggle_play()
		KEY_S: _step_layer()
		KEY_R: _reset()
