import trimesh
import numpy as np

#loading pumpkin.glb (free model "Pumpkin Orange Jacko" by Kay Lousberg on poly pizza https://poly.pizza/m/W4ocHnjsOS)
scene_or_mesh = trimesh.load("Pumpkin Orange Jacko by Kay Lousberg - W4oChnjsOS.glb")

if isinstance(scene_or_mesh, trimesh.Scene):
    mesh = scene_or_mesh.dump(concatenate=True)
else:
    mesh = scene_or_mesh

#ensure the colors exist, if not we will paint it orange and green
if mesh.visual.kind == 'texture' or mesh.visual.vertex_colors is None:
    #create a default orange color
    colors = np.ones((len(mesh.vertices), 4), dtype=np.uint8) * 255
    colors[:, :3] = [255, 130, 20]  #pumpkin orange RGB
    y_min, y_max = mesh.vertices[:, 1].min(), mesh.vertices[:, 1].max()
    stem_threshold = y_max - (y_max - y_min) * 0.15
    stem_mask = mesh.vertices[:, 1] >= stem_threshold
    colors[stem_mask, :3] = [40, 160, 40]  #stem green RGB
    
    mesh.visual.vertex_colors = colors

mesh.export("scenes/hw2/pumpkin.ply", file_type='ply')
print("Converted and colored pumpkin.ply successfully!")