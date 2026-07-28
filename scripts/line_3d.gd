# line_3d.gd
extends MeshInstance3D
class_name Line3D

@export var width: float = 0.02:
	set(new_width):
		width = new_width
		_draw_line()

@export var points: Array[Vector3] = []:
	set(new_points):
		points.clear()
		for p in new_points:
			if p is Vector3:
				points.append(p)
		_draw_line()

@export var material: Material:
	set(new_mat):
		material = new_mat
		material_override = new_mat
		_draw_line()

func _ready() -> void:
	if not mesh:
		mesh = ImmediateMesh.new()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_draw_line()

func _draw_line() -> void:
	if not is_inside_tree() or not mesh or points.size() < 2:
		return

	var imm: ImmediateMesh = mesh as ImmediateMesh
	imm.clear_surfaces()

	imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(points.size() - 1):
		var p1 = points[i]
		var p2 = points[i+1]
		var dir = (p2 - p1).normalized()

		# Find an orthogonal vector to define thickness
		var ortho = Vector3.UP
		if abs(dir.dot(Vector3.UP)) > 0.99:
			ortho = Vector3.RIGHT
		var right = dir.cross(ortho).normalized() * (width * 0.5)
		var up = dir.cross(right).normalized() * (width * 0.5)

		# Build a 4-sided prism (box-like tube) along the segment.
		# Vertices at p1:
		var v1_0 = p1 - right - up
		var v1_1 = p1 + right - up
		var v1_2 = p1 + right + up
		var v1_3 = p1 - right + up

		# Vertices at p2:
		var v2_0 = p2 - right - up
		var v2_1 = p2 + right - up
		var v2_2 = p2 + right + up
		var v2_3 = p2 - right + up

		# Side 1
		imm.surface_add_vertex(v1_0)
		imm.surface_add_vertex(v1_1)
		imm.surface_add_vertex(v2_1)

		imm.surface_add_vertex(v1_0)
		imm.surface_add_vertex(v2_1)
		imm.surface_add_vertex(v2_0)

		# Side 2
		imm.surface_add_vertex(v1_1)
		imm.surface_add_vertex(v1_2)
		imm.surface_add_vertex(v2_2)

		imm.surface_add_vertex(v1_1)
		imm.surface_add_vertex(v2_2)
		imm.surface_add_vertex(v2_1)

		# Side 3
		imm.surface_add_vertex(v1_2)
		imm.surface_add_vertex(v1_3)
		imm.surface_add_vertex(v2_3)

		imm.surface_add_vertex(v1_2)
		imm.surface_add_vertex(v2_3)
		imm.surface_add_vertex(v2_2)

		# Side 4
		imm.surface_add_vertex(v1_3)
		imm.surface_add_vertex(v1_0)
		imm.surface_add_vertex(v2_0)

		imm.surface_add_vertex(v1_3)
		imm.surface_add_vertex(v2_0)
		imm.surface_add_vertex(v2_3)

	imm.surface_end()
