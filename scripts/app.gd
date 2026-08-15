extends Control

# Workshop deck: four screens with a nav bar across the top.
#   0 Home   1 Chemistry   2 Printer   3 Safety

const NAV_H := 46.0

const TABS := [
	{"key": "1", "name": "Welcome"},
	{"key": "2", "name": "The chemistry"},
	{"key": "3", "name": "The printer"},
	{"key": "4", "name": "Safety"},
]

var screens: Array[Control] = []
var tab_buttons: Array[Button] = []
var host: Control
var current := 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UIKit.C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_build_nav()

	host = Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.offset_top = NAV_H
	add_child(host)

	for s in [ScreenHome.new(), ScreenChem.new(), ScreenPrinter.new(), ScreenSafety.new()]:
		s.set_anchors_preset(Control.PRESET_FULL_RECT)
		host.add_child(s)
		screens.append(s)

	(screens[0] as ScreenHome).start_pressed.connect(func(): go_to(1))

	var start := 0
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--screen="):
			start = clampi(int(a.get_slice("=", 1)), 0, screens.size() - 1)
	go_to(start)
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a == "--shotall":
			_shot_all()
		elif a == "--shotchem":
			_shot_chem()


# Debug helper: cure each resin type, then pull it, and capture the result.
func _shot_chem() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	if dir == "":
		dir = "user://"
	go_to(1)
	var chem := screens[1] as ScreenChem
	for r in [0, 2]:
		chem._on_resin_selected(r)
		chem._toggle_uv()
		await get_tree().create_timer(14.0).timeout
		chem._start_pull()
		await get_tree().create_timer(2.6).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/chem_pull_%d.png" % [dir, r])
	get_tree().quit()


# Debug helper: one screenshot per screen, then quit.
func _shot_all() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	if dir == "":
		dir = "user://"
	for i in screens.size():
		go_to(i)
		if i == 1:
			(screens[1] as ScreenChem)._toggle_uv()
			await get_tree().create_timer(9.0).timeout
		else:
			await get_tree().create_timer(2.0).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/screen_%d.png" % [dir, i])
	get_tree().quit()


func _build_nav() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.custom_minimum_size = Vector2(0, NAV_H)
	bar.offset_bottom = NAV_H
	bar.add_theme_stylebox_override("panel",
		UIKit.stylebox(UIKit.C_PANEL, Color(0, 0, 0, 0), 0, 0, 14))
	add_child(bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	bar.add_child(row)

	var brand := UIKit.label("RESEARCHASE", 13, UIKit.C_UV, true)
	brand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(brand)
	var div := UIKit.label("│", 13, UIKit.C_PANEL2)
	div.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(div)

	for i in TABS.size():
		var b := UIKit.button("%s  %s" % [TABS[i]["key"], TABS[i]["name"]], Callable(), 13, 30)
		b.pressed.connect(go_to.bind(i))
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(b)
		tab_buttons.append(b)

	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)

	var back := UIKit.button("◀", func(): go_to(current - 1), 13, 30)
	back.focus_mode = Control.FOCUS_NONE
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(back)
	var next := UIKit.button("Next  ▶", func(): go_to(current + 1), 13, 30)
	next.focus_mode = Control.FOCUS_NONE
	next.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(next)


func go_to(index: int) -> void:
	current = clampi(index, 0, screens.size() - 1)
	for i in screens.size():
		var on := i == current
		screens[i].visible = on
		# Hidden screens stop simulating so they cost nothing while off-stage.
		screens[i].process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
		tab_buttons[i].add_theme_color_override("font_color",
			UIKit.C_UV if on else UIKit.C_DIM)
		tab_buttons[i].add_theme_stylebox_override("normal",
			UIKit.stylebox(UIKit.C_PANEL2 if on else Color(0, 0, 0, 0),
				UIKit.C_UV if on else Color(0, 0, 0, 0), 1 if on else 0, 5, 12))
	if screens[current].has_method("on_shown"):
		screens[current].call("on_shown")


func _unhandled_key_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey and ev.pressed and not ev.echo):
		return
	match ev.keycode:
		KEY_1: go_to(0)
		KEY_2: go_to(1)
		KEY_3: go_to(2)
		KEY_4: go_to(3)
		KEY_RIGHT, KEY_PAGEDOWN: go_to(current + 1)
		KEY_LEFT, KEY_PAGEUP: go_to(current - 1)
		KEY_ESCAPE: get_tree().quit()
