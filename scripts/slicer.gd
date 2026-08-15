class_name ResinSlicer
extends RefCounted

# The "slicer": turns a 3D shape into one black & white bitmap per layer.
# White = UV passes through the LCD = resin cures there. Black = LCD blocks the light.
#
# World units: 1 unit = 1 cm. Build area = 12 x 8 units = 120 x 80 mm.

const MASK_W := 144                    # demo LCD pixel columns
const MASK_H := 96                     # demo LCD pixel rows
const BUILD_W := 12.0                  # build area width  (world units)
const BUILD_D := 8.0                   # build area depth  (world units)
const CELL := BUILD_W / float(MASK_W)  # size of one LCD pixel (world units)
const MODEL_HALF := 2.5                # model bounding box half-width
const MODEL_HEIGHT := 5.0              # model height (world units) = 50 mm

enum Model { VASE, ROOK, STAR }

const MODEL_NAMES := ["Hollow vase", "Chess rook", "Twisted star"]

# Radius profiles sampled from bottom (0.0) to top (1.0) of the model.
const VASE_PROFILE := [0.52, 0.60, 0.70, 0.78, 0.76, 0.66, 0.52, 0.40, 0.34, 0.35, 0.42, 0.48]
const ROOK_PROFILE := [0.80, 0.76, 0.62, 0.48, 0.42, 0.40, 0.40, 0.42, 0.50, 0.64, 0.74, 0.74]

const SOLID_COLOR := Color(1.0, 1.0, 1.0)
const EMPTY_COLOR := Color(0.02, 0.02, 0.04)


static func _profile(p: Array, w: float) -> float:
	var t: float = clampf(w, 0.0, 1.0) * float(p.size() - 1)
	var i: int = int(floor(t))
	if i >= p.size() - 1:
		return float(p[p.size() - 1])
	return lerpf(float(p[i]), float(p[i + 1]), t - float(i))


# Is the point solid? u,v in [-1,1] across the model footprint, w in [0,1] bottom to top.
static func is_solid(model: int, u: float, v: float, w: float) -> bool:
	var r := sqrt(u * u + v * v)
	if model == Model.VASE:
		var r_vase := _profile(VASE_PROFILE, w)
		if w < 0.10:
			return r <= r_vase          # solid base
		return r <= r_vase and r >= r_vase - 0.14   # walls only -> ring shaped masks
	elif model == Model.ROOK:
		var r_rook := _profile(ROOK_PROFILE, w)
		if r > r_rook:
			return false
		if w > 0.84 and r < r_rook - 0.18:
			return false                # hollowed out top
		if w > 0.90 and cos(4.0 * atan2(v, u)) > 0.45:
			return false                # four crenellation notches
		return true
	else:
		var ang := atan2(v, u) - 2.6 * w
		var r_star := (0.34 + 0.26 * cos(5.0 * ang)) * (1.0 - 0.22 * w)
		return r <= r_star


# Slice one layer. Returns the LCD bitmap plus the list of lit pixels.
# w = height through the model, 0 at the first layer printed.
static func slice_layer(model: int, w: float) -> Dictionary:
	var img := Image.create_empty(MASK_W, MASK_H, false, Image.FORMAT_RGB8)
	img.fill(EMPTY_COLOR)
	var cells := PackedInt32Array()
	var half_w := float(MASK_W) * 0.5
	var half_h := float(MASK_H) * 0.5
	for gy in MASK_H:
		# World position of this LCD pixel, relative to the centre of the build area.
		var wz := (float(gy) + 0.5 - half_h) * CELL
		var v := wz / MODEL_HALF
		if absf(v) > 1.0:
			continue
		for gx in MASK_W:
			var wx := (float(gx) + 0.5 - half_w) * CELL
			var u := wx / MODEL_HALF
			if absf(u) > 1.0:
				continue
			# The part prints upside-down in the vat, so the model is flipped:
			# machine +Z corresponds to model -Y.
			if is_solid(model, u, -v, w):
				cells.append(gy * MASK_W + gx)
				img.set_pixel(gx, gy, SOLID_COLOR)
	return {"cells": cells, "image": img}
