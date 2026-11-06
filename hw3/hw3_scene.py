import json
import numpy as np
import buffer
import math
import os
import slangpy as spy
import trimesh

SPHERE = 0  # Must match Slang's ShapeType in hw3_common.slang
TRIANGLE_MESH = 1

def parse_triangle_mesh(filename):
    if filename.lower().endswith('.ply'):
        mesh = trimesh.load_mesh(filename, process=False)

        vertices = np.asarray(mesh.vertices, dtype=np.float32)
        faces = np.asarray(mesh.faces, dtype=np.uint32)
        vertex_normals = np.asarray(
            mesh.vertex_normals, dtype=np.float32)

    else:
        with open(filename) as f:
            mesh = json.load(f)

        vertices = np.array(mesh['vertices'], dtype=np.float32)
        faces = np.array(mesh['faces'], dtype=np.uint32)

        if 'vertex_normals' in mesh:
            vertex_normals = np.array(
                mesh['vertex_normals'], dtype=np.float32)
        else:
            # Generate smooth vertex normals.
            tri_mesh = trimesh.Trimesh(
                vertices=vertices,
                faces=faces,
                process=False)
            vertex_normals = np.asarray(
                tri_mesh.vertex_normals, dtype=np.float32)

    return vertices, faces, vertex_normals

def compose_transformations(transformations):
    """
        Given a list of transformations, compose them into a matrix.
    """
    # HW 3.4: copy paste your HW2.3 code here
    F = np.eye(4, dtype=np.float32)
    
    for transform in transformations:
        # transformation is list of objects where key is the type of the transformation, value is an object 
    
        # HW 2.3 TODO: your code here
        # e.g. lookAt, { targe}
        key, value = list(transform.keys())[0], list(transform.values())[0]
    
        if key == "scale":
            scale_x, scale_y, scale_z = value
            mat = np.array([
                [scale_x, 0, 0, 0],
                [0, scale_y, 0, 0],
                [0, 0, scale_z, 0],
                [0, 0, 0, 1],
            ], dtype=np.float32)
    
        elif key == "translate":
            shift_x, shift_y, shift_z = value
            mat = np.array([
                [1, 0, 0, shift_x],
                [0, 1, 0, shift_y],
                [0, 0, 1, shift_z],
                [0, 0, 0, 1],
            ], dtype=np.float32)
    
        elif key == "rotate_x":
            rot = math.radians(value[0])
            mat = np.array([
                [1, 0, 0, 0],
                [0, math.cos(rot), -math.sin(rot), 0],
                [0, math.sin(rot),  math.cos(rot), 0],
                [0, 0, 0, 1],
            ], dtype=np.float32)
    
        elif key == "rotate_y":
            rot = math.radians(value[0])
            mat = np.array([
                [math.cos(rot), 0, math.sin(rot), 0],
                [0, 1, 0, 0],
                [-math.sin(rot), 0, math.cos(rot), 0],
                [0, 0, 0, 1],
            ], dtype=np.float32)
    
        elif key == "rotate_z":
            rot = math.radians(value[0])
            mat = np.array([
                [math.cos(rot), -math.sin(rot), 0, 0],
                [math.sin(rot), math.cos(rot), 0, 0],
                [0, 0, 1, 0],
                [0, 0, 0, 1],
            ], dtype=np.float32)
    
        elif key == "lookat":
            pos_x, pos_y, pos_z = value["position"]
            target_x, target_y, target_z = value["target"]
            up_x, up_y, up_z = value["up"]
    
            # d=normalize(t-p)
            dir_x = target_x - pos_x
            dir_y = target_y - pos_y
            dir_z = target_z - pos_z
    
            # normalize them
            dir_len = math.sqrt(dir_x * dir_x 
                                + dir_y * dir_y 
                                + dir_z * dir_z)
            dir_x /= dir_len
            dir_y /= dir_len
            dir_z /= dir_len
    
            # LLM usage:
            # Model: ChatGPT, GPT-6
            # I forgot how the cross product formula worked and had ChatGPT explain it conceptually and the formula.
            # r=normalize(d x u)
            right_x = dir_y * up_z - dir_z * up_y
            right_y = dir_z * up_x - dir_x * up_z
            right_z = dir_x * up_y - dir_y * up_x
    
            right_len = math.sqrt(right_x * right_x 
                                + right_y * right_y 
                                + right_z * right_z)
            right_x /= right_len
            right_y /= right_len
            right_z /= right_len
    
            # u' = r x d
            up_p_x = right_y * dir_z - right_z * dir_y
            up_p_y = right_z * dir_x - right_x * dir_z
            up_p_z = right_x * dir_y - right_y * dir_x
    
            mat = np.array([
                [right_x, up_p_x, -dir_x, pos_x],
                [right_y, up_p_y, -dir_y, pos_y],
                [right_z, up_p_z, -dir_z, pos_z],
                [0,       0,      0,      1],
            ], dtype=np.float32)
    
        F = mat @ F   # same left-multiply idea as hw1
    return F

def interpolate_transformation(transform_keyframes, t):
    # HW 3.4: copy your HW2.4 code here.

    # create a new transform from the two keyframes
    if not transform_keyframes:
        return None
        
        #find the two keyframes surrounding t
        k0 = transform_keyframes[-1]
        k1= transform_keyframes[0]
    
    for i in range(len(transform_keyframes) - 1):
        if transform_keyframes[i]["time"] <= t <= transform_keyframes[i+1]["time"]:
            k0 = transform_keyframes[i]
            k1 = transform_keyframes[i+1]
            break
                
    t0 = k0["time"]
    t1 = k1["time"]
        
    # compute normalized interpolation weight w
    if t1 == t0:
        w = 0.0
    else:
        w = (t - t0) / (t1 - t0)
            
    interp_transforms = []
    for t_prev, t_next in zip(k0["transform"], k1["transform"]):
        key = list(t_prev.keys())[0]
        val0 = t_prev[key]
        val1 = t_next[key]
        
        def interpolate_value(v0, v1, w):
            if isinstance(v0, list):
                return [x * (1 - w) + y * w for x, y in zip(v0, v1)]
            elif isinstance(v0, dict):
                return {sub_k: interpolate_value(v0[sub_k], v1[sub_k], w) for sub_k in v0.keys()}
            else:
                return v0 * (1 - w) + v1 * w
                
        val_interp = interpolate_value(val0, val1, w)
        interp_transforms.append({key: val_interp})
            
    return interp_transforms

def get_transformation(obj, t):
    transforms = obj.get('transform', [])
    if 'transform_keyframes' in obj:
        transforms = interpolate_transformation(
            obj['transform_keyframes'], t)
    return compose_transformations(transforms)

def build_bvh(vertices, faces, triangle_offset, bvh_nodes):
    # A recursive BVH builder that split the longest axis
    # using the median of the centroids. The leaf nodes
    # have maximum of 4 triangles.

    assert(len(faces) > 0)
    # Needs a copy because we will sort them during the recursion
    faces = faces.copy()
    centers = vertices[faces].mean(axis=1)

    def build(begin, end):
        node_id = len(bvh_nodes)
        # Important: append a node first
        # before the recursion, so that the order
        # is "preorder" 
        bvh_nodes.append(None)

        # Bounding box of all triangles in this node
        points = vertices[faces[begin:end]].reshape(-1, 3)
        bbox_min = points.min(axis=0)
        bbox_max = points.max(axis=0)

        # Stop recursion if the node has fewer than 4 triangles
        is_leaf = end - begin <= 4
        if not is_leaf:
            # Find the longest axis
            c = centers[begin:end]
            axis = np.argmax(c.max(axis=0) - c.min(axis=0))

            # Sort triangles by their centroids
            order = np.argsort(c[:, axis])
            faces[begin:end] = faces[begin:end][order]
            centers[begin:end] = c[order]

            # Split
            mid = (begin + end) // 2
            build(begin, mid)
            build(mid, end)

        bvh_nodes[node_id] = {
            'bbox_min': bbox_min,
            'bbox_max': bbox_max,
            'next_index': len(bvh_nodes),
            'triangle_begin': triangle_offset + begin,
            'triangle_end': triangle_offset + end,
            'is_leaf': is_leaf
        }

        return node_id

    root = build(0, len(faces))
    return root, faces

def upload_scene(filename, module, slang_device, use_bvh = False):
    with open(filename) as f:
        scene = json.load(f)

    background = scene.get('background', (0.5, 0.5, 0.5))

    camera = {'cam_to_world': np.eye(4, dtype=np.float32),
              'fov_x': 90.0}

    if 'camera' in scene:
        camera['cam_to_world'] = \
            get_transformation(scene['camera'], 0.0)
        camera['fov_x'] = scene['camera'].get('fov_x', 90.0)

    # Triangle meshes loading + BVH building
    mesh_descs = []
    vertices_list = []
    normals_list = []
    triangles_list = []
    bvh_nodes = []

    vertex_offset = 0
    triangle_offset = 0

    scene_dir = os.path.dirname(filename)

    for mesh_data in scene.get('meshes', []):
        mesh_filename = os.path.join(
            scene_dir, mesh_data['filename'])
        vertices, faces, vertex_normals = \
            parse_triangle_mesh(mesh_filename)

        # Construct the BVH and reorder triangles
        # The returned faces is a copy of our
        # original faces.
        if use_bvh:
            bvh_root_index, faces = build_bvh(
                vertices, faces, triangle_offset, bvh_nodes)
        else:
            bvh_root_index = 0

        mesh_descs.append({
            'vertex_offset': vertex_offset,
            'triangle_begin': triangle_offset,
            'triangle_end': triangle_offset + len(faces),
            'bvh_root_index': bvh_root_index
        })

        vertices_list.append(vertices)
        normals_list.append(vertex_normals)
        triangles_list.append(faces)

        vertex_offset += len(vertices)
        triangle_offset += len(faces)

    # Merge into global arrays
    if len(mesh_descs) > 0:
        vertices = np.concatenate(vertices_list).astype(np.float32)
        normals = np.concatenate(normals_list).astype(np.float32)
        triangles = np.concatenate(triangles_list).astype(np.uint32)
    else:
        # Use dummy entries if the scene has no meshes
        vertices = np.zeros((1, 3), dtype=np.float32)
        normals = np.zeros((1, 3), dtype=np.float32)
        triangles = np.zeros((1, 3), dtype=np.uint32)

    # Parse object instances.
    spheres = []
    shapes = []

    for obj in scene['objects']:
        if obj['type'] == 'sphere':
            shape_type = SPHERE
            shape_index = len(spheres)
            spheres.append({
                'center': obj['center'],
                'radius': obj['radius']
            })
        elif obj['type'] == 'mesh':
            shape_type = TRIANGLE_MESH
            shape_index = obj['index']
        else:
            raise ValueError(f"Unknown shape type: {obj['type']}")

        obj_to_world = get_transformation(obj, 0.0)
        world_to_obj = np.linalg.inv(obj_to_world)

        shapes.append({
            'type': shape_type,
            'index': shape_index,
            'Kd': obj['Kd'],
            'Kr': obj['Kr'],
            'world_to_obj': world_to_obj,
            'obj_to_world': obj_to_world
        })

    lights = scene['lights']

    max_depth = scene.get('max_depth', 20)

    bindings = {
        'background': spy.float3(background),
        'camera': camera,
        'shapes': buffer.create_structured_buffer(
            slang_device, module.Shape, shapes),
        'num_shapes': len(shapes),
        'spheres': buffer.create_structured_buffer(
            slang_device, module.Sphere, spheres),
        'meshes': buffer.create_structured_buffer(
            slang_device, module.TriangleMesh, mesh_descs),
        'vertices': buffer.structured_typed_buffer_from_numpy(
            slang_device, vertices, 'float3'),
        'vertex_normals': buffer.structured_typed_buffer_from_numpy(
            slang_device, normals, 'float3'),
        'triangles': buffer.structured_typed_buffer_from_numpy(
            slang_device, triangles, 'uint3'),
        'bvh_nodes': buffer.create_structured_buffer(
            slang_device, module.BVHNode, bvh_nodes),
        'lights': buffer.create_structured_buffer(
            slang_device, module.PointLight, lights),
        'num_lights': len(lights),
        'max_depth': max_depth
    }

    return bindings, scene, shapes
