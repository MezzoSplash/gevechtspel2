class_name NavBaker
extends RefCounted
## Bakes a map's NavigationRegion3D from its Arena collision at load (#104, #106).

const GROUP := &"_nav_source"


## Runtime navmesh from arena collision (not GPU meshes).
static func bake(map_node: Node) -> void:
	if map_node == null:
		return
	var region := map_node.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	var arena := map_node.get_node_or_null("Arena") as Node3D
	if region == null or arena == null:
		return
	var nav_mesh := NavigationMesh.new()
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.agent_radius = 0.5
	nav_mesh.agent_height = 1.75
	nav_mesh.agent_max_climb = 0.5
	nav_mesh.agent_max_slope = 46.0
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	# #104: CSG shapes get parsed from their visual mesh (a GPU readback + warning), so the parser only
	# sees the non-CSG static bodies (group GROUP) and the CSG faces come from their collision shape.
	var t0 := Time.get_ticks_usec()
	nav_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nav_mesh.geometry_source_group_name = GROUP
	var csgs: Array[CSGShape3D] = []
	if arena is CSGShape3D and (arena as CSGShape3D).use_collision:
		csgs.append(arena as CSGShape3D) # the whole arena is one CSG tree
	collect_sources(arena, csgs)
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav_mesh, source, arena)
	for csg in csgs:
		var shape := csg.bake_collision_shape()
		if shape:
			source.add_faces(shape.get_faces(), csg.global_transform)
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source)
	region.navigation_mesh = nav_mesh
	print("NAV: baked in %d ms (%d csg, %d polys)" % [(Time.get_ticks_usec() - t0) / 1000, csgs.size(), nav_mesh.get_polygon_count()])


## Tags every static body outside a CSG tree for the parser and lists the CSG roots with collision.
static func collect_sources(node: Node, csgs: Array[CSGShape3D]) -> void:
	for child in node.get_children():
		if child is CSGShape3D:
			var csg := child as CSGShape3D
			if csg.is_root_shape() and csg.use_collision:
				csgs.append(csg)
			collect_sources(child, csgs) # static bodies can sit inside a CSG tree
			continue
		if child is StaticBody3D:
			child.add_to_group(GROUP)
			continue
		collect_sources(child, csgs)
