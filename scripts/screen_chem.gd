class_name ScreenChem
extends Control

# Why UV light turns liquid resin solid, simulated molecule by molecule.
#
# Liquid resin = monomers/oligomers carrying a reactive C=C double bond, plus a few
# percent of photoinitiator. UV splits the initiator into radicals, radicals open the
# double bonds one after another, and the chains cross-link into one solid network.

const BOX := Vector3(9.0, 5.4, 7.0)      # the magnified drop of resin
const N_MONOMER := 130
const N_INITIATOR := 12
const GRAB_RADIUS := 2.4
const ADD_INTERVAL := 0.22               # seconds between chain additions, per radical
const PHOTON_INTERVAL := 0.7
const STARVE_TIME := 2.5

enum Stage { ABSORB, INITIATE, PROPAGATE, CROSSLINK, TERMINATE }

# Why one resin ends up hard and another rubbery. The single biggest lever is
# cross-link density: how much loose chain sits between two junctions.
#   cross   chance of a new unit also bonding to a neighbouring chain
#   seg     length of chain between units - stands in for backbone length
#   strain  how far the cured network can be pulled
#   brittle does it snap at the end of the pull, or spring back
const RESINS := [
	{
		"name": "Rigid / standard",
		"cross": 0.75, "seg": 0.40, "xdist": 1.8, "xmax": 2, "strain": 0.07, "brittle": true,
		"verdict": "Hard, stiff, snaps rather than bends",
		"desc": "Short, stiff monomers, most of them carrying two or three acrylate ends. Almost every unit becomes a junction, so the network is dense and the segments between junctions are only a few atoms long — there is nothing left to uncoil. Aromatic rings in the backbone stiffen it further, putting the glass transition well above room temperature: glassy, dimensionally stable and brittle.",
	},
	{
		"name": "Tough / ABS-like",
		"cross": 0.30, "seg": 0.52, "xdist": 1.25, "xmax": 1, "strain": 0.22, "brittle": false,
		"verdict": "Stiff, but absorbs a hit before it fails",
		"desc": "A blend. Long flexible urethane-acrylate segments are mixed into an otherwise normal network. The long segments soak up impact energy by uncoiling, while enough cross-links remain to keep the part stiff. Trading a little stiffness for a lot more energy absorbed before failure is exactly what 'tough' resins sell.",
	},
	{
		"name": "Flexible / elastomeric",
		"cross": 0.05, "seg": 0.62, "xdist": 0.85, "xmax": 1, "strain": 0.45, "brittle": false,
		"verdict": "Rubbery — stretches a long way and springs back",
		"desc": "Long, flexible aliphatic chains between the reactive ends, and mostly two ends per molecule rather than three. The network comes out loose: long coiled segments between widely spaced junctions, free to stretch out and spring back. Its glass transition sits below room temperature, so it behaves as a rubber rather than a glass.",
	},
]

const STAGES := [
	["1  ABSORPTION",
		"A 405 nm photon hits a photoinitiator molecule. It absorbs the energy and splits — homolytic cleavage — into two free radicals, each carrying one unpaired electron."],
	["2  INITIATION",
		"A radical attacks a monomer's C=C double bond. The double bond opens: one half bonds to the radical, and the unpaired electron moves to the far end of that monomer."],
	["3  PROPAGATION",
		"The new radical attacks the next monomer, and the next. A chain thousands of units long grows in a fraction of a second."],
	["4  CROSS-LINKING",
		"Printing monomers are reactive at both ends, so chains also bond to each other into one 3-D network. That is what makes cured resin a thermoset: it cannot be melted or dissolved back."],
	["5  TERMINATION",
		"Growth stops when two radicals meet and pair their electrons. Oxygen mops up radicals as well, which is why a surface exposed to air stays tacky."],
]


class Mono:
	var node: Node3D
	var vel := Vector3.ZERO
	var spin := Vector3.ZERO
	var bonded := false
	var flying := false
	var target := Vector3.ZERO
	var rest := Vector3.ZERO      # cured position, before any pull test
	var bond_from := Vector3.ZERO
	var chain := -1
	var parts: Array[MeshInstance3D] = []


class Initiator:
	var node: Node3D
	var vel := Vector3.ZERO
	var split := false


class ChainEnd:
	var pos := Vector3.ZERO
	var dir := Vector3.ZERO
	var tip: MeshInstance3D
	var timer := 0.0
	var starve := 0.0
	var units := 0
	var chain := 0


var monos := []
var inits := []
var ends := []
var photons := []

var sphere_mesh: SphereMesh
var rod_mesh: CylinderMesh
var mat_free: StandardMaterial3D
var mat_dbl: StandardMaterial3D
var mat_bonded: StandardMaterial3D
var mat_chain: StandardMaterial3D
var mat_cross: StandardMaterial3D
var mat_radical: StandardMaterial3D
var mat_init_a: StandardMaterial3D
var mat_init_b: StandardMaterial3D
var uv_plane_mat: StandardMaterial3D
var uv_light: OmniLight3D

var world: Node3D
var mol_root: Node3D
var bond_root: Node3D
var pivot: Node3D
var camera: Camera3D
var yaw := -0.5
var pitch := -0.18
var dist := 13.5

var bonds := []                  # {mi, a, b, r} - rest endpoints, so we can deform them
var resin_id := 0
var pull_state := "idle"         # idle / stretch / hold / release / snapped
var pull_t := 0.0
var strain := 0.0
var snap_gap := 0.0

var uv_on := false
var speed := 1.0
var photon_timer := 0.0
var chain_count := 0
var cross_count := 0
var stage := Stage.ABSORB
var stage_hold := 0.0

var banner: Label
var uv_btn: Button
var pull_btn: Button
var resin_opt: OptionButton
var stat_labels := {}
var stage_rows := []
var conv_bar: ProgressBar


func _ready() -> void:
	_build_3d()
	_build_panel()
	_populate()
	_refresh()


# ------------------------------------------------------------------ 3D scene

func _build_3d() -> void:
	var left := Control.new()
	left.set_anchors_preset(Control.PRESET_FULL_RECT)
	left.offset_right = -500
	add_child(left)

	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(svc)

	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	svc.add_child(vp)

	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_view_input)
	left.add_child(overlay)

	banner = UIKit.label("", 20)
	banner.position = Vector2(22, 18)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(banner)
	var hint := UIKit.label("drag to orbit  ·  wheel to zoom  ·  space = UV on/off", 12, UIKit.C_DIM)
	hint.position = Vector2(22, 46)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(hint)

	world = Node3D.new()
	vp.add_child(world)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.006, 0.007, 0.011)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.44, 0.56)
	env.ambient_light_energy = 0.7
	env.glow_enabled = true
	env.glow_intensity = 0.75
	env.glow_hdr_threshold = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, -40, 0)
	key.light_energy = 1.1
	world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-8, 140, 0)
	fill.light_energy = 0.5
	fill.light_color = Color(0.75, 0.82, 1.0)
	world.add_child(fill)

	pivot = Node3D.new()
	world.add_child(pivot)
	camera = Camera3D.new()
	camera.fov = 45.0
	pivot.add_child(camera)
	_update_camera()

	# the same 405 nm source as the printer's LED array, one level down in scale
	uv_plane_mat = StandardMaterial3D.new()
	uv_plane_mat.albedo_color = Color(0.06, 0.04, 0.11)
	uv_plane_mat.emission_enabled = true
	uv_plane_mat.emission = Color(0.55, 0.34, 1.0)
	uv_plane_mat.emission_energy_multiplier = 0.06
	var plane := PlaneMesh.new()
	plane.size = Vector2(BOX.x, BOX.z)
	var pmi := MeshInstance3D.new()
	pmi.mesh = plane
	pmi.material_override = uv_plane_mat
	pmi.position = Vector3(0, -BOX.y * 0.5 - 1.6, 0)
	world.add_child(pmi)

	uv_light = OmniLight3D.new()
	uv_light.position = Vector3(0, -BOX.y * 0.5 - 0.6, 0)
	uv_light.light_color = Color(0.66, 0.42, 1.0)
	uv_light.omni_range = 14.0
	uv_light.light_energy = 0.0
	world.add_child(uv_light)

	mol_root = Node3D.new()
	world.add_child(mol_root)
	bond_root = Node3D.new()
	world.add_child(bond_root)

	_build_materials()


func _build_materials() -> void:
	sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 1.0
	sphere_mesh.height = 2.0
	sphere_mesh.radial_segments = 12
	sphere_mesh.rings = 6
	rod_mesh = CylinderMesh.new()
	rod_mesh.top_radius = 1.0
	rod_mesh.bottom_radius = 1.0
	rod_mesh.height = 1.0
	rod_mesh.radial_segments = 8

	mat_free = _solid(UIKit.C_MONO, 0.35)
	mat_dbl = _solid(Color(0.40, 0.95, 1.0), 0.3)
	mat_dbl.emission_enabled = true
	mat_dbl.emission = Color(0.3, 0.85, 1.0)
	mat_dbl.emission_energy_multiplier = 0.35
	mat_bonded = _solid(Color(0.96, 0.78, 0.45), 0.4)
	mat_chain = _solid(Color(0.85, 0.62, 0.30), 0.45)
	mat_cross = _solid(UIKit.C_OK, 0.35)
	mat_cross.emission_enabled = true
	mat_cross.emission = UIKit.C_OK
	mat_cross.emission_energy_multiplier = 0.6
	mat_radical = _solid(Color(1.0, 0.35, 0.28), 0.3)
	mat_radical.emission_enabled = true
	mat_radical.emission = Color(1.0, 0.30, 0.20)
	mat_radical.emission_energy_multiplier = 2.2
	mat_init_a = _solid(Color(1.0, 0.85, 0.30), 0.35)
	mat_init_b = _solid(Color(1.0, 0.60, 0.20), 0.35)


func _solid(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _mi(mesh: Mesh, mat: Material, xform: Transform3D, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xform
	parent.add_child(mi)
	return mi


# A cylinder stretched from a to b. The scale has to be applied in the rod's own
# frame (basis * scale), not Basis.scaled(), which scales along the global axes.
static func _rod_xform(a: Vector3, b: Vector3, radius: float) -> Transform3D:
	var d := b - a
	var l := d.length()
	if l < 0.0001:
		return Transform3D(Basis.from_scale(Vector3(radius, 0.001, radius)), a)
	var up := d / l
	var basis := Basis()
	var axis := Vector3.UP.cross(up)
	if axis.length() > 0.0001:
		basis = Basis(axis.normalized(), acos(clampf(Vector3.UP.dot(up), -1.0, 1.0)))
	elif Vector3.UP.dot(up) < 0.0:
		basis = Basis(Vector3.RIGHT, PI)
	return Transform3D(basis * Basis.from_scale(Vector3(radius, l, radius)), (a + b) * 0.5)


static func _align_x(dir: Vector3) -> Basis:
	var x := dir.normalized()
	var ref := Vector3.UP if absf(x.dot(Vector3.UP)) < 0.9 else Vector3.FORWARD
	var z := x.cross(ref).normalized()
	return Basis(x, z.cross(x).normalized(), z)


# ------------------------------------------------------------------ molecules

func _populate() -> void:
	for m in monos:
		(m as Mono).node.queue_free()
	for i in inits:
		(i as Initiator).node.queue_free()
	for e in ends:
		if (e as ChainEnd).tip:
			(e as ChainEnd).tip.queue_free()
	for p in photons:
		(p["node"] as Node3D).queue_free()
	for b in bond_root.get_children():
		b.queue_free()
	monos.clear()
	inits.clear()
	ends.clear()
	photons.clear()
	bonds.clear()
	chain_count = 0
	cross_count = 0
	pull_state = "idle"
	strain = 0.0
	snap_gap = 0.0

	for i in N_MONOMER:
		monos.append(_make_monomer(_rand_point()))
	for i in N_INITIATOR:
		inits.append(_make_initiator(_rand_point()))


func _rand_point() -> Vector3:
	return Vector3(
		randf_range(-BOX.x, BOX.x) * 0.5,
		randf_range(-BOX.y, BOX.y) * 0.5,
		randf_range(-BOX.z, BOX.z) * 0.5)


# Two carbons joined by a DOUBLE bond - the reactive C=C group.
func _make_monomer(pos: Vector3) -> Mono:
	var m := Mono.new()
	var n := Node3D.new()
	n.position = pos
	n.basis = _align_x(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)))
	mol_root.add_child(n)
	m.node = n
	var a := Vector3(-0.17, 0, 0)
	var b := Vector3(0.17, 0, 0)
	m.parts.append(_mi(sphere_mesh, mat_free,
		Transform3D(Basis.from_scale(Vector3.ONE *0.115), a), n))
	m.parts.append(_mi(sphere_mesh, mat_free,
		Transform3D(Basis.from_scale(Vector3.ONE *0.115), b), n))
	# two parallel rods = the double bond; one of them opens up when it reacts
	m.parts.append(_mi(rod_mesh, mat_dbl,
		_rod_xform(a + Vector3(0, 0, 0.07), b + Vector3(0, 0, 0.07), 0.031), n))
	m.parts.append(_mi(rod_mesh, mat_dbl,
		_rod_xform(a - Vector3(0, 0, 0.07), b - Vector3(0, 0, 0.07), 0.031), n))
	m.vel = _rand_point().normalized() * randf_range(0.15, 0.45)
	m.spin = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.8
	return m


func _make_initiator(pos: Vector3) -> Initiator:
	var it := Initiator.new()
	var n := Node3D.new()
	n.position = pos
	mol_root.add_child(n)
	it.node = n
	var a := Vector3(-0.16, 0, 0)
	var b := Vector3(0.16, 0, 0)
	_mi(sphere_mesh, mat_init_a, Transform3D(Basis.from_scale(Vector3.ONE *0.15), a), n)
	_mi(sphere_mesh, mat_init_b, Transform3D(Basis.from_scale(Vector3.ONE *0.15), b), n)
	_mi(rod_mesh, mat_init_a, _rod_xform(a, b, 0.035), n)
	it.vel = _rand_point().normalized() * randf_range(0.1, 0.3)
	return it


# ------------------------------------------------------------------ simulation

func _process(delta: float) -> void:
	var dt := delta * speed
	if pull_state != "idle":
		_update_pull(delta)
	_drift(dt)
	_photons(dt)
	_grow(dt)
	stage_hold = maxf(0.0, stage_hold - dt)
	uv_light.light_energy = 1.2 if uv_on else 0.0
	uv_plane_mat.emission_energy_multiplier = (0.26 + 0.08 * sin(Time.get_ticks_msec() * 0.006)) \
		if uv_on else 0.06
	_refresh()


func _drift(dt: float) -> void:
	for item in monos:
		var m := item as Mono
		if m.flying:
			var to := m.target - m.node.position
			if to.length() < 0.05:
				m.node.position = m.target
				m.rest = m.target
				m.flying = false
				_add_bond(m.bond_from, m.target, 0.045, mat_chain)
			else:
				m.node.position += to.normalized() * maxf(to.length() * 6.0, 1.5) * dt
			continue
		if m.bonded:
			continue
		m.node.position += m.vel * dt
		m.node.rotate_y(m.spin.y * dt)
		m.node.rotate_x(m.spin.x * dt)
		_bounce(m.node, m)
	for item in inits:
		var it := item as Initiator
		if it.split:
			continue
		it.node.position += it.vel * dt
		it.node.rotate_y(dt * 0.7)
		_bounce_init(it)


func _bounce(n: Node3D, m: Mono) -> void:
	var p := n.position
	for axis in 3:
		var limit: float = BOX[axis] * 0.5
		if absf(p[axis]) > limit:
			p[axis] = clampf(p[axis], -limit, limit)
			m.vel[axis] = -m.vel[axis]
	n.position = p


func _bounce_init(it: Initiator) -> void:
	var p := it.node.position
	for axis in 3:
		var limit: float = BOX[axis] * 0.5
		if absf(p[axis]) > limit:
			p[axis] = clampf(p[axis], -limit, limit)
			it.vel[axis] = -it.vel[axis]
	it.node.position = p


func _photons(dt: float) -> void:
	if uv_on:
		photon_timer -= dt
		if photon_timer <= 0.0:
			photon_timer = PHOTON_INTERVAL
			_launch_photon()
	for i in range(photons.size() - 1, -1, -1):
		var ph: Dictionary = photons[i]
		ph["t"] += dt * 2.6
		var node: MeshInstance3D = ph["node"]
		node.position = (ph["from"] as Vector3).lerp(ph["to"] as Vector3, minf(ph["t"], 1.0))
		if ph["t"] >= 1.0:
			node.queue_free()
			photons.remove_at(i)
			_split_initiator(ph["target"])


func _launch_photon() -> void:
	var candidates := []
	for i in inits.size():
		if not (inits[i] as Initiator).split:
			candidates.append(i)
	if candidates.is_empty():
		return
	var idx: int = candidates[randi() % candidates.size()]
	var to: Vector3 = (inits[idx] as Initiator).node.position
	var from := Vector3(to.x, -BOX.y * 0.5 - 1.1, to.z)
	var node := _mi(sphere_mesh, mat_radical,
		Transform3D(Basis.from_scale(Vector3.ONE *0.09), from), world)
	photons.append({"node": node, "from": from, "to": to, "t": 0.0, "target": idx})


func _split_initiator(idx: int) -> void:
	var it := inits[idx] as Initiator
	if it.split:
		return
	it.split = true
	it.node.visible = false
	var base := it.node.position
	# two radicals fly apart, each one an active chain end
	var dir := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
	_spawn_end(base + dir * 0.2, dir)
	_spawn_end(base - dir * 0.2, -dir)
	_set_stage(Stage.ABSORB, 1.3)


func _spawn_end(pos: Vector3, dir: Vector3) -> void:
	var e := ChainEnd.new()
	e.pos = pos
	e.dir = dir
	e.chain = chain_count
	chain_count += 1
	e.tip = _mi(sphere_mesh, mat_radical,
		Transform3D(Basis.from_scale(Vector3.ONE *0.13), pos), world)
	ends.append(e)


func _grow(dt: float) -> void:
	for i in range(ends.size() - 1, -1, -1):
		var e := ends[i] as ChainEnd
		e.timer -= dt
		if e.timer > 0.0:
			continue
		e.timer = ADD_INTERVAL
		var m := _nearest_free(e.pos)
		if m == null:
			e.starve += ADD_INTERVAL
			if e.starve > STARVE_TIME:
				_kill_end(i)
			continue
		e.starve = 0.0
		_attach(e, m)
	# two radicals meeting cancel each other out
	for i in range(ends.size() - 1, -1, -1):
		if i >= ends.size():
			continue
		var a := ends[i] as ChainEnd
		for j in range(i - 1, -1, -1):
			var b := ends[j] as ChainEnd
			if a.pos.distance_to(b.pos) < 0.55 and a.units > 0 and b.units > 0:
				_add_bond(a.pos, b.pos, 0.045, mat_chain)
				_kill_end(i)
				_kill_end(j)
				_set_stage(Stage.TERMINATE, 1.4)
				break


func _nearest_free(from: Vector3) -> Mono:
	var best: Mono = null
	var best_d := GRAB_RADIUS
	for item in monos:
		var m := item as Mono
		if m.bonded:
			continue
		var d := m.node.position.distance_to(from)
		if d < best_d:
			best_d = d
			best = m
	return best


func _attach(e: ChainEnd, m: Mono) -> void:
	var seg := float(RESINS[resin_id]["seg"])
	var dir := e.dir
	# keep the chain inside the box by steering away from the walls
	var next := e.pos + dir * seg
	for axis in 3:
		if absf(next[axis]) > BOX[axis] * 0.5 - 0.3:
			dir[axis] = -dir[axis]
	dir = (dir + Vector3(randf_range(-0.5, 0.5), randf_range(-0.5, 0.5),
		randf_range(-0.5, 0.5))).normalized()
	next = e.pos + dir * seg

	m.bonded = true
	m.flying = true
	m.target = next
	m.bond_from = e.pos
	m.chain = e.chain
	m.node.basis = _align_x(dir)
	# the C=C double bond opens: one rod disappears, the unit turns polymer-coloured
	m.parts[3].visible = false
	m.parts[0].material_override = mat_bonded
	m.parts[1].material_override = mat_bonded
	m.parts[2].material_override = mat_bonded

	e.pos = next
	e.dir = dir
	e.units += 1
	e.tip.position = next
	_set_stage(Stage.INITIATE if e.units == 1 else Stage.PROPAGATE, 0.0)
	_try_crosslink(m)


func _try_crosslink(m: Mono) -> void:
	if randf() > float(RESINS[resin_id]["cross"]):
		return
	var made := 0
	var limit := int(RESINS[resin_id]["xmax"])
	var reach := float(RESINS[resin_id]["xdist"])
	for item in monos:
		var o := item as Mono
		if o == m or not o.bonded or o.flying or o.chain == m.chain:
			continue
		if o.rest.distance_to(m.target) < reach:
			_add_bond(m.target, o.rest, 0.038, mat_cross)
			cross_count += 1
			_set_stage(Stage.CROSSLINK, 1.2)
			made += 1
			if made >= limit:
				return


func _add_bond(a: Vector3, b: Vector3, radius: float, mat: Material) -> void:
	var mi := _mi(rod_mesh, mat, _rod_xform(a, b, radius), bond_root)
	bonds.append({"mi": mi, "a": a, "b": b, "r": radius})


func _kill_end(i: int) -> void:
	var e := ends[i] as ChainEnd
	if e.tip:
		e.tip.queue_free()
	ends.remove_at(i)


# ------------------------------------------------------------- pull test
# Stretch the cured network along X. How far it goes before it snaps back - or
# just snaps - is set entirely by how dense the cross-links are.

func _start_pull() -> void:
	if pull_state != "idle" and pull_state != "snapped":
		return
	if pull_state == "snapped":
		_restore_shape()
		return
	pull_state = "stretch"
	pull_t = 0.0


func _update_pull(dt: float) -> void:
	var max_strain := float(RESINS[resin_id]["strain"])
	match pull_state:
		"stretch":
			pull_t += dt * 0.7
			strain = max_strain * minf(pull_t, 1.0)
			if pull_t >= 1.0:
				if bool(RESINS[resin_id]["brittle"]):
					_fracture()
				else:
					pull_state = "hold"
					pull_t = 0.0
		"hold":
			pull_t += dt
			if pull_t >= 1.2:
				pull_state = "release"
				pull_t = 0.0
		"release":
			pull_t += dt * 0.9
			strain = max_strain * (1.0 - minf(pull_t, 1.0))
			if pull_t >= 1.0:
				strain = 0.0
				pull_state = "idle"
		"snapped":
			snap_gap = minf(snap_gap + dt * 0.7, 0.9)
		_:
			return
	_apply_strain()


# Break every bond crossing the middle: a dense network has no way to yield.
func _fracture() -> void:
	pull_state = "snapped"
	snap_gap = 0.0
	for b in bonds:
		var mid: Vector3 = ((b["a"] as Vector3) + (b["b"] as Vector3)) * 0.5
		if absf(mid.x) < 0.75:
			(b["mi"] as MeshInstance3D).visible = false


func _deform(p: Vector3) -> Vector3:
	# stretched along X, thinning slightly across it, plus the fracture gap
	var q := Vector3(p.x * (1.0 + strain), p.y * (1.0 - strain * 0.3),
		p.z * (1.0 - strain * 0.3))
	if pull_state == "snapped":
		q.x += signf(p.x) * snap_gap
	return q


func _apply_strain() -> void:
	for item in monos:
		var m := item as Mono
		if m.bonded and not m.flying:
			m.node.position = _deform(m.rest)
	for b in bonds:
		var mi := b["mi"] as MeshInstance3D
		if mi.visible:
			mi.transform = _rod_xform(_deform(b["a"]), _deform(b["b"]), b["r"])


func _restore_shape() -> void:
	pull_state = "idle"
	strain = 0.0
	snap_gap = 0.0
	for b in bonds:
		(b["mi"] as MeshInstance3D).visible = true
	_apply_strain()


func _set_stage(s: int, hold: float) -> void:
	if stage_hold > 0.0 and hold <= 0.0:
		return
	stage = s
	stage_hold = maxf(stage_hold, hold)


# ------------------------------------------------------------------ panel

func _build_panel() -> void:
	var side := PanelContainer.new()
	side.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	side.custom_minimum_size = Vector2(500, 0)
	side.offset_left = -500
	side.add_theme_stylebox_override("panel",
		UIKit.stylebox(UIKit.C_PANEL, Color(0, 0, 0, 0), 0, 0, 18))
	add_child(side)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 9)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)

	col.add_child(UIKit.label("photopolymerisation — live", 13, UIKit.C_UV, true))
	col.add_child(UIKit.wrap_label(
		"One drop of liquid resin, hugely magnified: %d monomer molecules and %d photoinitiators."
		% [N_MONOMER, N_INITIATOR], 12, UIKit.C_DIM, 440))

	var state := UIKit.label("LIQUID", 30, UIKit.C_MONO)
	stat_labels["state"] = state
	col.add_child(state)

	conv_bar = ProgressBar.new()
	conv_bar.custom_minimum_size = Vector2(0, 10)
	conv_bar.show_percentage = false
	conv_bar.max_value = 1.0
	conv_bar.step = 0.0001
	col.add_child(conv_bar)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 3)
	col.add_child(grid)
	for key in [["conv", "Double bonds reacted"], ["free", "Free monomers"],
			["rad", "Active radicals"], ["chain", "Chains started"],
			["cross", "Cross-links"], ["dens", "Cross-link density"]]:
		grid.add_child(UIKit.label(key[1], 12, UIKit.C_DIM))
		var v := UIKit.label("-", 12)
		grid.add_child(v)
		stat_labels[key[0]] = v

	var legend := VBoxContainer.new()
	legend.add_theme_constant_override("separation", 3)
	col.add_child(legend)
	legend.add_child(UIKit.legend_row(UIKit.C_MONO, "monomer with a C=C double bond (two rods)"))
	legend.add_child(UIKit.legend_row(Color("ffd84d"), "photoinitiator — splits under UV"))
	legend.add_child(UIKit.legend_row(Color("ff5947"), "free radical — the reactive end"))
	legend.add_child(UIKit.legend_row(Color("f5c772"), "polymer chain — bond opened, now single"))
	legend.add_child(UIKit.legend_row(UIKit.C_OK, "cross-link between two chains"))

	col.add_child(UIKit.sep())
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	col.add_child(btns)
	uv_btn = UIKit.button("UV 405 nm  ·  OFF", _toggle_uv, 14, 40)
	uv_btn.custom_minimum_size = Vector2(210, 40)
	btns.add_child(uv_btn)
	btns.add_child(UIKit.button("Reset", _reset_sim))

	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 8)
	col.add_child(srow)
	srow.add_child(UIKit.label("Speed", 12, UIKit.C_DIM))
	var sl := HSlider.new()
	sl.min_value = 0.25
	sl.max_value = 4.0
	sl.step = 0.25
	sl.value = 1.0
	sl.custom_minimum_size = Vector2(250, 0)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.value_changed.connect(_on_speed)
	srow.add_child(sl)

	col.add_child(UIKit.sep())
	col.add_child(UIKit.label("what kind of resin is in the vat?", 12, UIKit.C_UV, true))
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 8)
	col.add_child(rrow)
	var ro := OptionButton.new()
	for r in RESINS:
		ro.add_item(r["name"])
	ro.selected = 0
	ro.item_selected.connect(_on_resin_selected)
	resin_opt = ro
	ro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rrow.add_child(ro)
	pull_btn = UIKit.button("Pull it", _start_pull, 13)
	rrow.add_child(pull_btn)

	var verdict := UIKit.label(RESINS[0]["verdict"], 14, UIKit.C_CURE)
	verdict.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	verdict.custom_minimum_size = Vector2(440, 0)
	stat_labels["verdict"] = verdict
	col.add_child(verdict)
	var why := UIKit.wrap_label(RESINS[0]["desc"], 11, UIKit.C_DIM, 440)
	stat_labels["why"] = why
	col.add_child(why)
	col.add_child(UIKit.wrap_label(
		"Cross-link density is the lever. The closer the junctions, the stiffer and more brittle the part — which is also why over-post-curing makes prints snap: more leftover double bonds react and tighten the network further.",
		11, UIKit.C_DIM, 440))

	col.add_child(UIKit.sep())
	col.add_child(UIKit.label("the mechanism", 12, UIKit.C_UV, true))
	for i in STAGES.size():
		var p := UIKit.card(UIKit.C_PANEL2)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 1)
		var t := UIKit.label(STAGES[i][0], 13, UIKit.C_DIM)
		var d := UIKit.wrap_label(STAGES[i][1], 11, UIKit.C_DIM, 420)
		v.add_child(t)
		v.add_child(d)
		p.add_child(v)
		col.add_child(p)
		stage_rows.append({"panel": p, "title": t, "desc": d})

	col.add_child(UIKit.wrap_label(
		"Only about 70-90 % of the double bonds react during the print. Post-curing under UV converts more of them — that is the difference between a green part and a fully strong one.",
		11, UIKit.C_DIM, 440))
	_style_uv_button()


func _on_speed(v: float) -> void:
	speed = v


func _on_resin_selected(i: int) -> void:
	resin_id = i
	resin_opt.selected = i
	stat_labels["verdict"].text = RESINS[i]["verdict"]
	stat_labels["why"].text = RESINS[i]["desc"]
	_reset_sim()


func _toggle_uv() -> void:
	uv_on = not uv_on
	_style_uv_button()


func _style_uv_button() -> void:
	uv_btn.text = "UV 405 nm  ·  %s" % ("ON" if uv_on else "OFF")
	var bg := Color("3a2560") if uv_on else UIKit.C_PANEL2
	var border := UIKit.C_UV if uv_on else UIKit.C_PANEL2
	uv_btn.add_theme_stylebox_override("normal", UIKit.stylebox(bg, border, 2, 6, 14))
	uv_btn.add_theme_stylebox_override("hover",
		UIKit.stylebox(bg.lightened(0.08), border, 2, 6, 14))
	uv_btn.add_theme_color_override("font_color", UIKit.C_TEXT if uv_on else UIKit.C_DIM)


func _reset_sim() -> void:
	uv_on = false
	_style_uv_button()
	_populate()
	_refresh()


func _refresh() -> void:
	var bonded := 0
	for item in monos:
		if (item as Mono).bonded:
			bonded += 1
	var conv := float(bonded) / float(N_MONOMER)
	conv_bar.value = conv
	stat_labels["conv"].text = "%d %%  (%d of %d)" % [roundi(conv * 100.0), bonded, N_MONOMER]
	stat_labels["free"].text = str(N_MONOMER - bonded)
	stat_labels["rad"].text = str(ends.size())
	stat_labels["chain"].text = str(chain_count)
	stat_labels["cross"].text = str(cross_count)
	stat_labels["dens"].text = "%.1f per 100 units" % (
		100.0 * float(cross_count) / maxf(float(bonded), 1.0))

	var cured := conv > 0.35
	pull_btn.disabled = not cured
	pull_btn.text = "Reset shape" if pull_state == "snapped" else "Pull it"

	var state_text := "LIQUID"
	var state_color := UIKit.C_MONO
	if conv > 0.55:
		state_text = "SOLID"
		state_color = UIKit.C_OK
	elif conv > 0.2:
		state_text = "GEL"
		state_color = UIKit.C_CURE
	stat_labels["state"].text = state_text
	stat_labels["state"].add_theme_color_override("font_color", state_color)

	if pull_state == "snapped":
		banner.text = "SNAP — a dense network has nowhere to give"
	elif pull_state != "idle":
		banner.text = "Pulling — %.0f %% strain" % (strain * 100.0)
	elif not uv_on:
		banner.text = "UV off — molecules just drift past each other" if ends.is_empty() \
			else "UV off — radicals already made keep reacting"
	else:
		banner.text = "UV on — %d radical%s growing chains" % [
			ends.size(), "" if ends.size() == 1 else "s"]

	for i in stage_rows.size():
		var on := i == stage
		stage_rows[i]["panel"].add_theme_stylebox_override("panel",
			UIKit.stylebox(Color("2a2140") if on else UIKit.C_PANEL2,
				UIKit.C_UV if on else Color(0, 0, 0, 0), 2 if on else 0, 6, 12))
		stage_rows[i]["title"].add_theme_color_override("font_color",
			UIKit.C_UV if on else UIKit.C_DIM)
		stage_rows[i]["desc"].add_theme_color_override("font_color",
			UIKit.C_TEXT if on else UIKit.C_DIM)


# ------------------------------------------------------------------ camera

func _update_camera() -> void:
	pivot.rotation = Vector3(pitch, yaw, 0)
	camera.position = Vector3(0, 0, dist)


func _on_view_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT):
		yaw -= ev.relative.x * 0.006
		pitch = clampf(pitch - ev.relative.y * 0.006, -1.3, 1.3)
		_update_camera()
	elif ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist = clampf(dist - 1.2, 6.0, 34.0)
			_update_camera()
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist = clampf(dist + 1.2, 6.0, 34.0)
			_update_camera()


func _unhandled_key_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.keycode == KEY_SPACE:
			_toggle_uv()
		elif ev.keycode == KEY_R:
			_reset_sim()
