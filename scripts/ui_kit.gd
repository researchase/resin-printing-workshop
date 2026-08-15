class_name UIKit
extends RefCounted

# Shared look and feel for every screen in the workshop deck.

const C_BG := Color("0d0f14")
const C_PANEL := Color("141822")
const C_PANEL2 := Color("1b2030")
const C_TEXT := Color("e6e9f0")
const C_DIM := Color("8892a6")
const C_UV := Color("a06bff")
const C_CURE := Color("ffcf7a")
const C_WARN := Color("ff8a5c")
const C_DANGER := Color("ff6b6b")
const C_OK := Color("6fe0a8")
const C_MONO := Color("5fd4dd")


static func label(text: String, font_size := 15, color := C_TEXT, caps := false) -> Label:
	var l := Label.new()
	l.text = text.to_upper() if caps else text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


static func wrap_label(text: String, font_size := 12, color := C_DIM, min_width := 360.0) -> Label:
	var l := label(text, font_size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(min_width, 0)
	return l


static func stylebox(bg: Color, border_color := Color(0, 0, 0, 0), border := 0,
		radius := 6, pad := 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	if border > 0:
		sb.border_color = border_color
		sb.set_border_width_all(border)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad - 2
	sb.content_margin_bottom = pad - 2
	return sb


static func card(bg := C_PANEL2, border_color := Color(0, 0, 0, 0), border := 0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", stylebox(bg, border_color, border, 6, 12))
	return p


static func button(text: String, cb: Callable, font_size := 13, height := 34.0) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	b.custom_minimum_size = Vector2(0, height)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


static func sep() -> HSeparator:
	return HSeparator.new()


static func spacer(height := 8.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


# A coloured dot followed by text, for legends.
static func legend_row(color: Color, text: String, font_size := 11) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 7)
	var dot := ColorRect.new()
	dot.color = color
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(dot)
	h.add_child(label(text, font_size, C_DIM))
	return h
