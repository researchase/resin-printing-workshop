class_name ScreenSafety
extends Control

# Why resin printing needs real safety discipline - and what that looks like in practice.

const INTRO := "Uncured resin is a reactive chemical, not an ink. The acrylate groups that bond to each other under UV will just as happily react with the proteins in your skin — that is exactly why resin is a sensitiser. Cured, washed and post-cured plastic is inert and safe to handle. Everything below is about the liquid stage."

# tag, tag colour, title, body, why
const CARDS := [
	["SKIN", UIKit.C_DANGER, "Nitrile gloves, every time",
		"Wear nitrile gloves (latex is permeable to resin) and keep sleeves down. Change gloves as soon as they get resin on them, and never handle a wet print bare-handed.",
		"Resin is a sensitiser: reactions build up silently over months, then appear as sudden dermatitis that can end the hobby for good."],
	["SKIN", UIKit.C_DANGER, "Never clean skin with IPA",
		"If resin touches skin, wash with soap and plenty of water. Isopropyl alcohol dissolves resin into the skin and carries it through the barrier instead of removing it.",
		"The solvent that cleans your prints is the worst thing to put on your hands."],
	["EYES / UV", UIKit.C_WARN, "Glasses on, lid closed",
		"Safety glasses whenever resin or IPA is open — a splash is corrosive to the eye. Keep the printer lid on while it runs and never defeat the interlock to watch the LEDs.",
		"405 nm is at the edge of visible light; it is bright enough to damage the retina and you will not feel the exposure."],
	["AIR", UIKit.C_WARN, "Ventilate the room",
		"Print in a ventilated space with the lid closed, and keep the door open or a window fan running. Wear a P2/N95 mask when sanding or drilling cured parts.",
		"Resins release VOCs while printing, and cured resin dust is a respiratory irritant."],
	["FIRE", UIKit.C_WARN, "IPA is flammable",
		"Keep isopropyl alcohol in a closed container, away from heaters, soldering irons and sparks. Do not fill a big open tub in a small unventilated room.",
		"IPA vapour is heavier than air, pools at bench level and ignites easily."],
	["WASTE", UIKit.C_OK, "Cure everything before you bin it",
		"Uncured resin, dirty paper towels, failed prints and used gloves all go under a UV lamp or in sunlight until fully hard, then into normal waste. Dirty IPA goes to hazardous waste collection.",
		"Liquid resin is very toxic to aquatic life — it must never go down a drain or into household rubbish while it is still liquid."],
	["SPILLS", UIKit.C_OK, "Cover the bench first",
		"Work over a wipeable tray or a sheet of card. Wipe spills with paper towel, cure the towel, then bin it. Keep a roll of towel and a spare pair of gloves within reach before you start.",
		"Nearly every resin injury happens during a rushed clean-up, not during printing."],
	["PARTS", UIKit.C_OK, "Wash, then post-cure",
		"A part straight off the plate is coated in liquid resin. Wash in IPA, then post-cure under UV until the surface is dry to the touch. Only then is it safe to hand round the room.",
		"Green parts feel solid but still carry uncured resin on every surface."],
	["PEOPLE", UIKit.C_DANGER, "No food, no kids, no pets",
		"Never eat, drink or vape at the resin bench. Label every container clearly — resin and IPA look like drinks in a bottle. Keep the printer somewhere children and animals cannot reach.",
		"Ingestion is a medical emergency; a curious hand in the vat is a hospital trip."],
]

const CHECKLIST := [
	"Nitrile gloves on, sleeves down",
	"Safety glasses on",
	"Bench covered, paper towel within reach",
	"Ventilation on or window open",
	"IPA closed and away from heat",
	"Waste tub and UV lamp ready for curing waste",
	"No food, drink, pets or children in the area",
	"Safety data sheet for this resin to hand",
]

const FIRST_AID := [
	["Skin contact", "Wash with soap and water — not IPA. If a rash appears, stop working with resin and see a doctor."],
	["Eye contact", "Rinse with clean water for 15 minutes, holding the eye open. Seek medical advice."],
	["Breathed in", "Move to fresh air. Get medical help if breathing stays uncomfortable."],
	["Swallowed", "Do not induce vomiting. Seek medical help immediately and take the resin bottle with you."],
]


func _ready() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for s in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(s, 34)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 30)
	scroll.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	col.add_child(UIKit.label("safety — and why it is not optional", 13, UIKit.C_UV, true))
	col.add_child(UIKit.label("Handling resin", 34))

	var intro := UIKit.card(Color("241a20"), UIKit.C_DANGER, 1)
	intro.add_child(UIKit.wrap_label(INTRO, 14, UIKit.C_TEXT, 900))
	col.add_child(intro)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	col.add_child(grid)
	for c in CARDS:
		grid.add_child(_card(c[0], c[1], c[2], c[3], c[4]))

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 14)
	col.add_child(bottom)
	bottom.add_child(_checklist())
	bottom.add_child(_first_aid())

	col.add_child(UIKit.wrap_label(
		"One line to remember: uncured resin is a chemical, cured resin is a plastic. Every rule above exists to keep the two apart.",
		15, UIKit.C_CURE, 900))


func _card(tag: String, tag_color: Color, title: String, body: String, why: String) -> PanelContainer:
	var card := UIKit.card(UIKit.C_PANEL, UIKit.C_PANEL2, 1)
	card.custom_minimum_size = Vector2(370, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)

	var tag_box := PanelContainer.new()
	tag_box.add_theme_stylebox_override("panel",
		UIKit.stylebox(Color(tag_color, 0.16), tag_color, 1, 4, 8))
	tag_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tag_box.add_child(UIKit.label(tag, 10, tag_color, true))
	v.add_child(tag_box)

	v.add_child(UIKit.wrap_label(title, 17, UIKit.C_TEXT, 380))
	v.add_child(UIKit.wrap_label(body, 12, UIKit.C_DIM, 380))

	var why_row := HBoxContainer.new()
	why_row.add_theme_constant_override("separation", 8)
	var bar := ColorRect.new()
	bar.color = tag_color
	bar.custom_minimum_size = Vector2(3, 0)
	why_row.add_child(bar)
	why_row.add_child(UIKit.wrap_label(why, 12, tag_color.lightened(0.25), 360))
	v.add_child(why_row)

	card.add_child(v)
	return card


func _checklist() -> PanelContainer:
	var card := UIKit.card(UIKit.C_PANEL, UIKit.C_OK, 1)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.add_child(UIKit.label("before you open the bottle", 12, UIKit.C_OK, true))
	v.add_child(UIKit.spacer(4))
	for item in CHECKLIST:
		var cb := CheckBox.new()
		cb.text = item
		cb.add_theme_font_size_override("font_size", 13)
		cb.add_theme_color_override("font_color", UIKit.C_TEXT)
		v.add_child(cb)
	card.add_child(v)
	return card


func _first_aid() -> PanelContainer:
	var card := UIKit.card(UIKit.C_PANEL, UIKit.C_DANGER, 1)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.add_child(UIKit.label("if something goes wrong", 12, UIKit.C_DANGER, true))
	for fa in FIRST_AID:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 1)
		row.add_child(UIKit.label(fa[0], 13, UIKit.C_TEXT))
		row.add_child(UIKit.wrap_label(fa[1], 12, UIKit.C_DIM, 380))
		v.add_child(row)
	card.add_child(v)
	return card
