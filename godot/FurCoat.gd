extends Node
## FurCoat — shell fur on any rigged (or static) model, Compatibility/WebGL safe.
##
##     var coat = preload("res://godot/FurCoat.gd").new()
##     coat.shells = 12
##     model.add_child(coat)      # builds on _ready; model = the loaded GLB root
##
## For every MeshInstance3D under the parent it bakes ONE extra mesh holding `shells`
## copies of the furry surfaces, each copy tagged with its height in the coat. The copy
## keeps the original bone weights and skin, so the engine skins the fur with the body —
## any animation the model has just works, and it is one draw call per surface.
## The original mesh stays visible underneath as the skin.
##
## Surfaces that should stay bald (eyes, noses, hooves...) are picked by material name,
## then by size: the Quaternius animals name their eye/nose materials, except the Husky,
## whose tiny unnamed ones are caught by the size rule.
##
## Motion: the shader adds wind and gravity itself; this node adds drag when the model
## moves, with the spring-damper from the original repo's "WebGL mode" (no GPU sim).
##
## Limits: any Mesh with triangle surfaces and normals works (ArrayMesh from glTF,
## PrimitiveMesh). The coat copies positions, normals, UVs and 4/8 bone weights; blend
## shapes and vertex colours are not carried over, and the coat takes its colour from the
## source's StandardMaterial3D albedo colour/texture (RGB only; a ShaderMaterial source
## gives a plain white coat). The coat's meshes are shared between copies of one model
## (see _baked_for) and freed with the coat.
##
## Third-party notice (MIT, Mochi-Puff Contributors): FUR_THIRD_PARTY.md, next to this file.
##
## Deliberately NO class_name — new class_name scripts have broken the web export
## before; callers use preload() on this path.

const FUR_SHADER := preload("fur_shell.gdshader")

## Lowercase substrings of material names that never grow fur.
const BARE := ["eye", "nose", "hoof", "hooves", "muzzle", "black", "pupil", "teeth",
	"tooth", "tongue", "horn", "antler", "claw", "beak", "mouth", "lip"]
## Lowercase substrings that always grow fur, even on a small surface.
const FURRY := ["main", "fur", "hair", "body", "wool", "coat", "mane"]
## A surface with an unknown name and less than this share of the mesh's vertices is
## treated as a detail (eye, nose) and stays bald.
const DETAIL_SHARE := 0.04
## Fur shortens wherever the body part is thinner than this many coat lengths (measured
## through the mesh, see _thickness), down to `thin_part_floor` of full length.
const THIN_RATIO := 2.0

## Layers in the coat. More = denser, smoother fur and more vertices to skin.
## 8-12 for crowds / mobile, 16-24 for a hero close-up.
@export var shells := 16
## Fur length as a fraction of the model's longest side.
@export var length_frac := 0.03
## Strand cells across the model's longest side. Higher = finer fur.
@export var cells_across := 520.0
## Strand radius in cell units (0.5 = neighbours touch).
@export var strand_width := 0.36
@export var density := 0.85
@export var clumping := 0.20
@export var curliness := 0.15
@export var roughness := 0.6
@export var specular := 0.35
@export var tip_lift := 0.2
@export var groom := 0.35
@export var gravity := 0.25
@export var wind_strength := 0.5
## Fallback direction the coat lies toward (mesh space) for models without a skin or a
## head bone; rigged models get a per-vertex field from their skeleton instead.
## glTF animals face +Z, so tail-ward is -Z.
@export var groom_dir := Vector3(0.0, -0.4, -1.0)
## Shortest coat allowed on a bone-thin part. Lower this only for a model whose
## ears need to read as clean geometry rather than as a fuzzy silhouette.
@export_range(0.02, 0.5, 0.01) var thin_part_floor: float = 0.12
## How strongly movement drags the coat back.
@export var drag := 1.0
## Per-material length multipliers, matched as lowercase substrings, e.g. {"hair": 3.0}
## for a long horse mane.
@export var length_by_material := {}
## Per-material "falls to the ground" amount 0..1, matched like length_by_material, e.g.
## {"hair": 1.0} so a horse's mane hangs to one side instead of following the neck.
@export var fall_by_material := {}
## Single-texture models (eyes, nose, headphones all in one atlas) can't be kept bald
## by material name. Texels whose brightest channel (linear) is below this stay bald.
## 0 = off; ~0.03 catches black eyes and noses, ~0.15 dark-grey gear on a coloured
## coat. Don't use it on a black-furred animal.
@export var bald_below_brightness := 0.0
## Optional painted mask on the model's UVs: R = how much coat may grow (black = bald).
@export var fur_mask: Texture2D

## Fur is hidden beyond this camera distance in metres (0 = always drawn). At range the
## coat is a sub-pixel velvet anyway, and the shells are the expensive part.
@export var visible_range := 0.0

## Species the fur has been visually checked on (Doc/fur_review/after_v7), by model file
## name, with the settings it was checked with. Anything else stays bare.
const PRESETS := {
	"wolf.glb": {},
	"husky.glb": {},
	"fox.glb": {"tip_lift": 0.3, "thin_part_floor": 0.07},
	"shibainu.glb": {},
	"alpaca.glb": {"length_frac": 0.05, "curliness": 0.6, "clumping": 0.7, "groom": 0.15},
	"horse.glb": {"length_frac": 0.008, "cells_across": 780.0,
		"length_by_material": {"hair": 7.5, "mane": 7.5}, "fall_by_material": {"hair": 1.0, "mane": 1.0}},
	"horse_white.glb": {"length_frac": 0.008, "cells_across": 780.0,
		"length_by_material": {"hair": 7.5, "mane": 7.5}, "fall_by_material": {"hair": 1.0, "mane": 1.0}},
	"bear.glb": {"length_frac": 0.035, "cells_across": 560.0, "bald_below_brightness": 0.03},
	"characters_pug.glb": {"length_frac": 0.02, "bald_below_brightness": 0.03},
}

## Baked coat meshes shared between animals of the same model. See _baked_for.
static var _bake_cache := {}

var _shells: Array[MeshInstance3D] = []
var _materials: Array[ShaderMaterial] = []
var _body: Node3D
var _world_extent := 1.0
var _last_pos := Vector3.ZERO
var _disp := Vector3.ZERO
var _vel := Vector3.ZERO


## A coat for the model at `model_path` (any path or URL ending in its file name), set up
## for this device's VFX tier, or null when the species has no checked preset or the tier
## has fur off. Add the result as a child of the model's root node.
static func for_model(model_path: String, shell_count: int, range_m: float) -> Node:
	var preset: Variant = PRESETS.get(model_path.get_file().uri_decode().to_lower())
	if preset == null or shell_count <= 0:
		return null
	var coat: Node = load(FUR_SHADER.resource_path.get_base_dir().path_join("FurCoat.gd")).new()
	coat.shells = shell_count
	coat.visible_range = range_m
	for k in preset:
		coat.set(k, preset[k])
	return coat


## The coat's meshes are siblings of the model's meshes (they must share its skeleton),
## not children of the coat, so they go explicitly when the coat is freed. Not on
## _exit_tree: Prey re-parents a live model, which exits and re-enters the tree.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		clear()


func _ready() -> void:
	_body = get_parent() as Node3D
	if _body == null:
		push_error("FurCoat: parent must be a Node3D")
		return
	# Deferred: when the model enters the tree with the coat already attached (how
	# spawn_creatures does it), its root is still busy readying children and refuses the
	# shells a mesh directly under it would need.
	build.call_deferred()


## (Re)build the coat. Needed after changing anything baked into the mesh: `shells`,
## `length_frac`, `length_by_material`, `fall_by_material`, `thin_part_floor`, `groom_dir`.
## Everything else only needs apply_params(). `shells` <= 0 leaves an empty coat.
func build() -> void:
	clear()
	if shells <= 0 or _body == null:
		return
	var meshes: Array[MeshInstance3D] = []
	_collect(_body, meshes)
	var extent := 0.0
	var world_extent := 0.0
	for mi in meshes:
		var box := mi.mesh.get_aabb()
		var e := maxf(box.size.x, maxf(box.size.y, box.size.z))
		extent = maxf(extent, e)
		world_extent = maxf(world_extent, e * _max_scale(mi))
	_world_extent = maxf(world_extent, 0.001)
	if extent <= 0.0:
		return
	for mi in meshes:
		_build_shells(mi, extent)
	_last_pos = _body.global_position
	apply_params()


func clear() -> void:
	for s in _shells:
		if is_instance_valid(s):
			if s.get_parent():
				s.get_parent().remove_child(s)
			s.queue_free()
	_shells.clear()
	_materials.clear()


func set_visible(on: bool) -> void:
	for s in _shells:
		s.visible = on


## Push the non-baked exported values (shading, density, wind, mask, visible_range...)
## into the coat. For the baked ones, see build().
func apply_params() -> void:
	var max_mul := 1.0
	for m in _materials:
		var extent: float = m.get_meta("extent")
		m.set_shader_parameter("fur_length", extent * length_frac * float(m.get_meta("length_mul")))
		m.set_shader_parameter("cell_size", extent / cells_across)
		m.set_shader_parameter("cell_world", extent / cells_across * float(m.get_meta("world_scale")))
		m.set_shader_parameter("strand_width", strand_width)
		m.set_shader_parameter("bald_below_brightness", bald_below_brightness)
		# Always set, so clearing the mask (null) falls back to the shader's white default.
		m.set_shader_parameter("fur_mask", fur_mask)
		max_mul = maxf(max_mul, float(m.get_meta("length_mul")))
		m.set_shader_parameter("body_scale", 1.0 / extent)
		m.set_shader_parameter("density", density)
		m.set_shader_parameter("clumping", clumping)
		m.set_shader_parameter("curliness", curliness)
		m.set_shader_parameter("roughness", roughness)
		m.set_shader_parameter("specular", specular)
		m.set_shader_parameter("tip_lift", tip_lift)
		# Falling hair (a mane) lies flat along its flow instead of standing out.
		m.set_shader_parameter("groom", maxf(groom, float(m.get_meta("fall", 0.0)) * 0.85))
		m.set_shader_parameter("gravity", gravity)
		m.set_shader_parameter("wind_strength", wind_strength)
	# The stored mesh has undisplaced positions, so culling needs room for the longest
	# coat on the model, plus its lean (groom, gravity, drag, wind) - 3x covers those.
	for s in _shells:
		s.extra_cull_margin = _world_extent * length_frac * max_mul * 3.0
		s.visibility_range_end = visible_range if visible_range > 0.0 else 0.0
		s.visibility_range_end_margin = visible_range * 0.1 if visible_range > 0.0 else 0.0


func _process(delta: float) -> void:
	if _body == null or _shells.is_empty() or delta <= 0.0:
		return
	var dt := minf(delta, 0.05)
	var pos := _body.global_position
	var velocity := (pos - _last_pos) / delta
	_last_pos = pos
	# The original's WebGL-mode spring, with velocity measured in body lengths per
	# second so a horse and a pug drag the same way at the same relative speed.
	var force := -velocity / _world_extent * 1.65 * drag - _disp * 24.0
	_vel = (_vel + force * dt) * exp(-5.5 * dt)
	_disp += _vel * dt
	if _disp.length_squared() > 0.64:
		_disp = _disp.normalized() * 0.8

	for s in _shells:
		if not s.is_inside_tree():
			continue
		var to_mesh := s.global_basis.orthonormalized().inverse()
		var down := to_mesh * Vector3.DOWN
		var drift := to_mesh * _disp
		for i in s.get_surface_override_material_count():
			var m := s.get_surface_override_material(i) as ShaderMaterial
			m.set_shader_parameter("mesh_down", down)
			m.set_shader_parameter("inertia", drift)


## Largest axis scale: a coat on a stretched model must cover its longest axis.
func _max_scale(node: Node3D) -> float:
	var sc := node.global_basis.get_scale().abs()
	return maxf(sc.x, maxf(sc.y, sc.z))


func _collect(node: Node, out: Array[MeshInstance3D]) -> void:
	var mi := node as MeshInstance3D
	if mi and mi.mesh and not mi.has_meta("fur_shell"):
		out.append(mi)
	for child in node.get_children():
		_collect(child, out)


func _build_shells(mi: MeshInstance3D, extent: float) -> void:
	var baked := _baked_for(mi, extent)
	var out: ArrayMesh = baked.get("mesh")
	if out == null:
		return
	var shell := MeshInstance3D.new()
	shell.name = mi.name + "_Fur"
	shell.set_meta("fur_shell", true)
	shell.mesh = out
	shell.skin = mi.skin
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell.transform = mi.transform
	# The mesh is shared by every animal of this model; materials are per animal, because
	# each carries its own drag and gravity direction.
	var world_scale := _max_scale(mi)
	var i := 0
	for info in baked["surfaces"]:
		var m := _make_material(mi.get_active_material(int(info[0])), extent, float(info[1]), world_scale)
		m.set_meta("fall", float(info[2]))
		shell.set_surface_override_material(i, m)
		i += 1
	mi.get_parent().add_child(shell)
	var skeleton := mi.get_node_or_null(mi.skeleton)
	if skeleton:
		shell.skeleton = shell.get_path_to(skeleton)
	_shells.append(shell)


## The coat mesh for `mi`, baked once per source mesh and bake settings and then shared:
## a herd is copies of one model that share its mesh, so animal 2..40 costs no bake.
## Returns {"mesh": ArrayMesh or null, "surfaces": [[source surface, length mul, fall]]}.
func _baked_for(mi: MeshInstance3D, extent: float) -> Dictionary:
	var src := mi.mesh
	# Everything _bake reads from the instance, not just the mesh: surface material names
	# pick bald/furry surfaces and their length, and the skin drives the groom. Copies of
	# one model share all of these, so a herd still bakes once.
	var names := PackedStringArray()
	for s in src.get_surface_count():
		names.append(_material_name(mi.get_active_material(s), src, s))
	var skin_id := mi.skin.get_instance_id() if mi.skin else 0
	var key := "%d|%d|%d|%s" % [src.get_instance_id(), skin_id, shells, var_to_str([extent,
		length_frac, length_by_material, fall_by_material, thin_part_floor, groom_dir, names])]
	var hit: Dictionary = _bake_cache.get(key, {})
	if not hit.is_empty() and (hit["source"] as WeakRef).get_ref() == src:
		return hit
	# Drop entries whose model is gone (a previous world), so the cache can't grow forever.
	for k in _bake_cache.keys():
		if (_bake_cache[k]["source"] as WeakRef).get_ref() == null:
			_bake_cache.erase(k)
	var baked := _bake(mi, extent)
	baked["source"] = weakref(src)
	_bake_cache[key] = baked
	return baked


func _bake(mi: MeshInstance3D, extent: float) -> Dictionary:
	var src := mi.mesh
	var surfaces: Array = []
	var total_verts := 0
	# Low-poly packs are flat-shaded: every hard edge splits its vertices, each copy with
	# its own face normal. Shells pushed out along those normals tear open at every edge
	# and the skin shows through as bright lines, so the coat grows along normals
	# averaged over every vertex at the same spot (across surfaces too, so colour
	# borders don't crack). Only the shell copy gets them; the source mesh is untouched.
	var welded := {}
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		surfaces.append(arrays)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		total_verts += verts.size()
		if arrays[Mesh.ARRAY_NORMAL] == null:
			continue
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in verts.size():
			var key := verts[i].snappedf(extent * 1e-4)
			welded[key] = welded.get(key, Vector3.ZERO) + normals[i]

	var max_mul := 1.0
	for key in length_by_material:
		max_mul = maxf(max_mul, float(length_by_material[key]))
	var thick := _thickness(welded, extent * length_frac * max_mul * THIN_RATIO)
	var rig := _rig_groom(mi, surfaces)
	var out := ArrayMesh.new()
	var info: Array = []
	for s in src.get_surface_count():
		var source_mat := mi.get_active_material(s)
		var mat_name := _material_name(source_mat, src, s)
		var arrays: Array = surfaces[s]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var share := float(verts.size()) / maxf(1.0, float(total_verts))
		var length_mul := _length_for(mat_name, share)
		if length_mul <= 0.0 or arrays[Mesh.ARRAY_NORMAL] == null:
			continue
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var smooth := PackedVector3Array()
		smooth.resize(verts.size())
		var thin := PackedFloat32Array()
		thin.resize(verts.size())
		for i in verts.size():
			var key := verts[i].snappedf(extent * 1e-4)
			var sum: Vector3 = welded[key]
			var avg := sum.normalized() if sum.length_squared() > 1e-8 else normals[i]
			# Thin parts (ears): front and back faces share the rim vertices, so the
			# average points sideways and the coat splays out as spikes. Where it
			# disagrees that much with the face, the face's own normal wins.
			smooth[i] = avg if avg.dot(normals[i]) > 0.35 else normals[i]
			thin[i] = thick.get(key, INF)
		var fall := _fall_for(mat_name)
		var flow := _groom_field(arrays, smooth, rig, extent * length_frac * length_mul, fall, thin)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _shell_arrays(arrays, smooth, flow),
			[], {}, _shell_format((src as ArrayMesh).surface_get_format(s) if src is ArrayMesh else 0))
		info.append([s, length_mul, fall])
	return {"mesh": out if out.get_surface_count() > 0 else null, "surfaces": info}


## Which way the coat lies, per skeleton bone, in mesh space: along the bone, pointed
## AWAY from the face. Spine and neck run to the tail, legs to the paws, ears to their
## tips; vertices on the head itself flow back from the snout (or down from the crown on
## an upright character). Empty when the model has no skin or no head bone; the coat
## then lies along `groom_dir`.
func _rig_groom(mi: MeshInstance3D, surfaces: Array) -> Dictionary:
	var skel := mi.get_node_or_null(mi.skeleton) as Skeleton3D
	var skin := mi.skin
	if skel == null or skin == null or skin.get_bind_count() == 0:
		return {}
	var bind_bone := PackedInt32Array()
	for i in skin.get_bind_count():
		var b := skin.get_bind_bone(i)
		bind_bone.append(b if b >= 0 else skel.find_bone(skin.get_bind_name(i)))
	if bind_bone[0] < 0:
		return {}

	var to_mesh := (skel.get_bone_global_rest(bind_bone[0]) * skin.get_bind_pose(0)).affine_inverse()
	var count := skel.get_bone_count()
	var joints := PackedVector3Array()
	joints.resize(count)
	for b in count:
		joints[b] = to_mesh * skel.get_bone_global_rest(b).origin
	var axes := PackedVector3Array()
	axes.resize(count)
	for b in count:
		var axis := Vector3.ZERO
		for c in skel.get_bone_children(b):
			axis += joints[c] - joints[b]
		if axis.length_squared() < 1e-10 and skel.get_bone_parent(b) >= 0:
			axis = joints[b] - joints[skel.get_bone_parent(b)]  # leaf: carry on the parent's way
		axes[b] = axis.normalized() if axis.length_squared() > 1e-10 else Vector3.DOWN

	var head := -1
	for b in count:
		var bn := skel.get_bone_name(b).to_lower()
		if bn.contains("head") and not bn.contains("end") and not bn.contains("top"):
			head = b
			break
	if head < 0:
		return {}
	# A head well ahead of the root is an animal's: the face is the snout tip. Otherwise
	# it is an upright character and the coat flows down from the crown.
	var reach := joints[head] - joints[0]
	var snout := Vector2(reach.x, reach.z).length() > absf(reach.y) * 0.5
	var forward := Vector3(reach.x, 0.0, reach.z).normalized() if snout else Vector3.UP
	var anchor := joints[head]
	var best := -INF
	for arrays in surfaces:
		if arrays[Mesh.ARRAY_BONES] == null or arrays[Mesh.ARRAY_WEIGHTS] == null:
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var stride := int(bones.size() / float(maxi(1, verts.size())))
		for i in verts.size():
			var top := 0
			for k in stride:
				if weights[i * stride + k] > weights[i * stride + top]:
					top = k
			var bind := bones[i * stride + top]
			if bind >= bind_bone.size() or bind_bone[bind] != head:
				continue
			var score := verts[i].dot(forward)
			if score > best:
				best = score
				anchor = verts[i]
	if best == -INF:
		return {}
	for b in count:
		if axes[b].dot(joints[b] - anchor) < 0.0:
			axes[b] = -axes[b]
	return {"bind_bone": bind_bone, "axes": axes, "head": head, "anchor": anchor,
		"head_len": maxf(anchor.distance_to(joints[head]), 1e-4), "snout": snout}


## How thick the body is under each surface point: the distance to the nearest point
## behind it that faces the other way (the back of an ear, the far side of a leg).
## Only distances under `reach` matter, so the search stays inside a grid of
## reach-sized cells. Keys are the welded (snapped) positions; points with nothing
## behind them within reach get INF. Measured on the mesh, not the bones: the
## Quaternius ears are weighted to the head bone, so bone distances called them thick.
func _thickness(welded: Dictionary, reach: float) -> Dictionary:
	var out := {}
	if reach <= 0.0:
		return out
	# Packed arrays and integer indices: Vector3-keyed Dictionary lookups in the inner
	# loop made a dense mesh (Wumpus, ~8k points) take 1.4 s.
	var keys := welded.keys()
	var count := keys.size()
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	pos.resize(count)
	nrm.resize(count)
	var inv := 1.0 / reach
	var cells := {}
	# On a dense mesh every point is still measured, but only against every `stride`-th
	# point: their spacing stays well under a coat length, so the answer barely moves.
	var stride := maxi(1, ceili(count / 2000.0))
	for i in count:
		var p: Vector3 = keys[i]
		pos[i] = p
		nrm[i] = (welded[p] as Vector3).normalized()
		if i % stride != 0:
			continue
		var c := Vector3i((p * inv).floor())
		if not cells.has(c):
			cells[c] = PackedInt32Array()
		cells[c].append(i)
	var reach_sq := reach * reach
	for i in count:
		var p := pos[i]
		var n := nrm[i]
		var best_sq := reach_sq
		var c := Vector3i((p * inv).floor())
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					var bucket = cells.get(c + Vector3i(dx, dy, dz))
					if bucket == null:
						continue
					for j in (bucket as PackedInt32Array):
						if nrm[j].dot(n) > -0.3:
							continue
						var d := pos[j] - p
						if d.dot(n) >= 0.0:
							continue  # in front: a neighbouring part, not this one's back
						var dist_sq := d.length_squared()
						if dist_sq < best_sq:
							best_sq = dist_sq
		out[keys[i]] = sqrt(best_sq) if best_sq < reach_sq else INF
	return out


## Per vertex: the direction the coat lies (packed as TANGENT, so the engine skins it
## with the body) and a length factor: shorter toward an animal's nose, and never much
## longer than the body part is thick (`thin`, from _thickness). Full-length fur on an
## ear or a thin leg stands out as a spiky tuft. `fur_len` is the coat length in mesh
## units; `fall` (0..1) turns the flow toward the ground, for manes.
func _groom_field(arrays: Array, normals: PackedVector3Array, rig: Dictionary,
		fur_len: float, fall: float, thin: PackedFloat32Array) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n := verts.size()
	var tangents := PackedFloat32Array()
	tangents.resize(n * 4)
	var lengths := PackedFloat32Array()
	lengths.resize(n)
	var rigged := not rig.is_empty() and arrays[Mesh.ARRAY_BONES] != null \
		and arrays[Mesh.ARRAY_WEIGHTS] != null
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var bind_bone := PackedInt32Array()
	var axes := PackedVector3Array()
	var head := -1
	var anchor := Vector3.ZERO
	var head_len := 1.0
	var snout := false
	if rigged:
		bones = arrays[Mesh.ARRAY_BONES]
		weights = arrays[Mesh.ARRAY_WEIGHTS]
		bind_bone = rig["bind_bone"]
		axes = rig["axes"]
		head = rig["head"]
		anchor = rig["anchor"]
		head_len = rig["head_len"]
		snout = rig["snout"]
	var stride := int(bones.size() / float(maxi(1, n)))
	# A mane falls to one side of the crest, not straight down onto it. The sideward
	# bias keeps a long mane visible in profile instead of collapsing into a dark ridge.
	var down := Vector3(0.7, -1.0, 0.0).normalized()

	for i in n:
		var v := verts[i]
		var flow := groom_dir
		var length := 1.0
		if rigged:
			flow = Vector3.DOWN * 0.3
			for k in stride:
				var w := weights[i * stride + k]
				var bind := bones[i * stride + k]
				if w <= 0.0 or bind >= bind_bone.size() or bind_bone[bind] < 0:
					continue
				var b := bind_bone[bind]
				flow += ((v - anchor).normalized() if b == head else axes[b]) * w
			if snout:
				# Face fur is short: it grows from 30% at the nose to full length past the ears.
				length = lerpf(0.3, 1.0, smoothstep(0.0, head_len * 1.2, v.distance_to(anchor)))
		length *= clampf(thin[i] / (fur_len * THIN_RATIO), thin_part_floor, 1.0)
		flow = flow.lerp(down * maxf(flow.length(), 1.0), fall)
		var nr := normals[i]
		var t := flow - nr * flow.dot(nr)
		if t.length_squared() < 1e-6:
			t = groom_dir - nr * groom_dir.dot(nr)
		if t.length_squared() < 1e-6:
			t = nr.cross(Vector3.RIGHT if absf(nr.x) < 0.9 else Vector3.UP)
		t = t.normalized()
		tangents[i * 4] = t.x
		tangents[i * 4 + 1] = t.y
		tangents[i * 4 + 2] = t.z
		tangents[i * 4 + 3] = 1.0
		lengths[i] = length
	return [tangents, lengths]


## `shells` copies of the surface, stacked in one vertex buffer. Each copy carries its
## height in the coat and the bind-pose position/normal the fur pattern is pinned to.
## `flow` = [TANGENT floats, per-vertex length factors] from _groom_field.
func _shell_arrays(arrays: Array, normals: PackedVector3Array, flow: Array) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var tangents: PackedFloat32Array = flow[0]
	var lengths: PackedFloat32Array = flow[1]
	var n := verts.size()
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null \
		else PackedInt32Array(range(n))

	var rest0 := PackedFloat32Array()
	var rest1 := PackedFloat32Array()
	rest0.resize(n * 4)
	rest1.resize(n * 4)
	for i in n:
		var v := verts[i]
		var nr := normals[i]
		rest0[i * 4] = v.x
		rest0[i * 4 + 1] = v.y
		rest0[i * 4 + 2] = v.z
		rest1[i * 4] = nr.x
		rest1[i * 4 + 1] = nr.y
		rest1[i * 4 + 2] = nr.z
		rest1[i * 4 + 3] = lengths[i]

	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var custom0 := PackedFloat32Array()
	var custom1 := PackedFloat32Array()
	var out_index := PackedInt32Array()
	for k in shells:
		var h := float(k + 1) / float(shells)
		for i in n:
			rest0[i * 4 + 3] = h
		custom0.append_array(rest0)
		custom1.append_array(rest1)
		var shifted := index.duplicate()
		var offset := k * n
		for j in shifted.size():
			shifted[j] += offset
		out_index.append_array(shifted)

	var stacked_normals := PackedVector3Array()
	var stacked_tangents := PackedFloat32Array()
	for k in shells:
		stacked_normals.append_array(normals)
		stacked_tangents.append_array(tangents)
	out[Mesh.ARRAY_NORMAL] = stacked_normals
	out[Mesh.ARRAY_TANGENT] = stacked_tangents
	for slot in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
		if arrays[slot] == null:
			continue
		var stacked = arrays[slot].duplicate()
		for k in shells - 1:
			stacked.append_array(arrays[slot])
		out[slot] = stacked
	out[Mesh.ARRAY_CUSTOM0] = custom0
	out[Mesh.ARRAY_CUSTOM1] = custom1
	out[Mesh.ARRAY_INDEX] = out_index
	return out


func _shell_format(source_format: int) -> int:
	var fmt := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	if source_format & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS:
		fmt |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	return fmt


func _make_material(source: Material, extent: float, length_mul: float, world_scale: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FUR_SHADER
	m.set_meta("extent", extent)
	m.set_meta("length_mul", length_mul)
	m.set_meta("world_scale", world_scale)
	var base := source as BaseMaterial3D
	if base:
		m.set_shader_parameter("base_color", base.albedo_color)
		if base.albedo_texture:
			m.set_shader_parameter("albedo_tex", base.albedo_texture)
	_materials.append(m)
	return m


func _material_name(mat: Material, mesh: Mesh, surface: int) -> String:
	var n := ""
	if mat:
		n = mat.resource_name
	if n == "" and mesh is ArrayMesh:
		n = (mesh as ArrayMesh).surface_get_name(surface)
	return n.to_lower()


func _fall_for(mat_name: String) -> float:
	var fall := 0.0
	for key in fall_by_material:
		if mat_name.contains(String(key).to_lower()):
			fall = clampf(float(fall_by_material[key]), 0.0, 1.0)
	return fall


## Fur length multiplier for a surface; 0 = bald.
func _length_for(mat_name: String, share: float) -> float:
	for key in BARE:
		if mat_name.contains(key):
			return 0.0
	var mul := 1.0
	for key in length_by_material:
		if mat_name.contains(String(key).to_lower()):
			mul = float(length_by_material[key])
	for key in FURRY:
		if mat_name.contains(key):
			return mul
	return 0.0 if share < DETAIL_SHARE else mul
