# Custom scene (HW4): cloth drop on a procedural water bottle
# uv run python main.py 4_6 scenes/hw4/cloth_water_bottle.py
# uv run python main.py 4_6 scenes/hw4/cloth_water_bottle.py \
#     -output outputs/hw4_custom_cloth_bottle.mp4 -duration 5 -fps 30

import numpy as np
import trimesh
from scenes.hw4.geometry import make_cloth_grid, make_cloth_constraints

# trimesh.creation.cylinder is aligned along +Z; bottle uses +Y as up.
_CYLINDER_ALIGN_Y = trimesh.transformations.rotation_matrix(
    np.pi / 2.0, [1.0, 0.0, 0.0])


def _cylinder_up_y(radius, height, sections):
    mesh = trimesh.creation.cylinder(
        radius=radius, height=height, sections=sections)
    mesh.apply_transform(_CYLINDER_ALIGN_Y)
    return mesh


def make_bottle():
    # LLM Usage:
    # Model: ChatGPT, GPT-6
    # I used ChatGPT to better understand the code in other scene files to help with making our own for a simple rendering, which was just a cloth falling on top of a water bottle.
    body_height = 1.0
    body_radius = 0.32
    neck_height = 0.22
    neck_radius = 0.11
    sections_body = 24
    sections_neck = 16

    body = _cylinder_up_y(body_radius, body_height, sections_body)
    body.apply_translation([0.0, body_height / 2.0, 0.0])

    neck = _cylinder_up_y(neck_radius, neck_height, sections_neck)
    # Neck base meets body top at y = body_height.
    neck.apply_translation([0.0, body_height + neck_height / 2.0, 0.0])

    bottle = trimesh.util.concatenate([body, neck])
    vertices = np.ascontiguousarray(
        bottle.vertices, dtype=np.float32)
    triangles = np.ascontiguousarray(
        bottle.faces, dtype=np.uint32)
    normals = np.ascontiguousarray(
        bottle.vertex_normals, dtype=np.float32)

    return {
        'vertices': vertices,
        'triangles': triangles,
        'vertex_normals': normals,
    }


def make_scene():
    bottle = make_bottle()
    bottle_top = float(bottle['vertices'][:, 1].max())

    nx, ny = 30, 30
    sx, sy = 1.8, 1.8
    positions, cloth_triangles, dx, dy = make_cloth_grid(nx, ny, sx, sy)
    positions[:, 1] = bottle_top + 0.2
    edges, rest_lengths = make_cloth_constraints(nx, ny, dx, dy)

    target_y = bottle_top * 0.45

    return {
        'positions': positions.astype(np.float32),
        'velocities': np.zeros_like(positions),
        'inv_masses': np.ones(len(positions), dtype=np.float32),

        'constraint_edges': edges,
        'rest_lengths': rest_lengths,
        'triangles': cloth_triangles,
        'cloth_grid_size': (nx, ny),
        'spacing': (dx, dy),

        'collision_mesh': bottle,

        'planes': np.array([
            [0, 1, 0, 0],
        ], dtype=np.float32),
        'spheres': np.zeros((0, 4), dtype=np.float32),

        'collision_distance': 0.03,
        'contact_margin': 0.04,
        'static_friction': 1.2,
        'kinetic_friction': 0.8,

        'substeps': 8,
        'iterations': 16,

        'cam_pos': (2.8, 1.8, -3.2),
        'cam_target': (0.0, target_y, 0.0),
        'cam_up': (0.0, 1.0, 0.0),
    }