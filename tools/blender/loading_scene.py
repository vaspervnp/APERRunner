"""Blender scene of the loading screen (prompts/blender_loading_screen.md):
sunset over Athens, three electric tracks into the distance, a green train
with the runner jumping on its roof after a row of coins, the avenue on the
left, pines on the right, a footbridge, Piraeus' cranes on the horizon (the
Acropolis silhouette is painted with the sky, where it stays readable at
192x168).

Low-poly boxes and cones in flat colours near the CPC ones, Workbench flat
render with outlines, transparent sky (tools/quantize_loading.py paints the
sky and the sun with the CPC dither and adds the logo).

    blender -b --factory-startup -P tools/blender/loading_scene.py -- OUT_DIR

writes OUT_DIR/loading_scene.blend and OUT_DIR/loading_4x.png (1536x672:
4x the 384x168 square-pixel picture = 192x168 mode 0 pixels).
"""

import math
import os
import sys

import bpy

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else os.getcwd()

# colours (CPC palette, linear values for the Standard view transform)
CPC = {
    "black": "000000", "blue": "000080", "bblue": "0000FF", "red": "800000", "bred": "FF0000",
    "orange": "FF8000", "olive": "808000", "yellow": "FFFF00", "green": "008000",
    "bgreen": "00FF00", "lime": "80FF00", "sky": "0080FF", "grey": "808080", "white": "FFFFFF",
    "pink": "FF8080", "mauve": "8000FF", "magenta": "800080", "pyellow": "FFFF80",
}


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


MATERIALS = {}


def material(name):
    if name not in MATERIALS:
        m = bpy.data.materials.new("APER_" + name)
        value = CPC[name]
        rgb = [srgb_to_linear(int(value[i:i + 2], 16) / 255) for i in (0, 2, 4)]
        m.diffuse_color = (*rgb, 1.0)
        MATERIALS[name] = m
    return MATERIALS[name]


COLLECTION = None


def add(obj, colour):
    obj.data.materials.append(material(colour))
    for c in obj.users_collection:
        c.objects.unlink(obj)
    COLLECTION.objects.link(obj)
    return obj


def box(x, y, z, sx, sy, sz, colour, rot=0.0):
    """Box with its base centre at (x, y, z) and full size sx, sy, sz."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y, z + sz / 2), rotation=(0, 0, rot))
    o = bpy.context.active_object
    o.scale = (sx, sy, sz)
    return add(o, colour)


def cone(x, y, z, r, h, colour, vertices=6):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=r, depth=h, location=(x, y, z + h / 2))
    return add(bpy.context.active_object, colour)


def cylinder(x, y, z, r, depth, colour, rot=(0, 0, 0), vertices=12):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=r, depth=depth, location=(x, y, z), rotation=rot)
    return add(bpy.context.active_object, colour)


def scene():
    global COLLECTION
    sc = bpy.data.scenes.new("APER_Loading")
    bpy.context.window.scene = sc
    COLLECTION = bpy.data.collections.new("APER")
    sc.collection.children.link(COLLECTION)

    # --- ground ---------------------------------------------------------------
    box(0, 150, -0.4, 400, 400, 0.2, "olive")                 # far land (below the rest)
    box(19, 120, -0.1, 26, 260, 0.1, "green")                 # forest floor (right)
    box(-15, 120, -0.1, 16, 260, 0.1, "grey")                 # avenue (left)
    box(0, 120, -0.15, 14, 260, 0.1, "olive")                 # between the tracks
    for lane in (-20, -17.5, -12.5, -10):                     # lane dashes
        for k in range(30):
            box(lane, 4 + k * 8, 0.0, 0.25, 3.0, 0.02, "white")
    box(-15, 120, 0.0, 0.5, 260, 0.03, "pyellow")             # median

    # --- three tracks along +Y ------------------------------------------------
    for tx in (-4.0, 0.0, 4.0):
        box(tx, 120, 0.0, 3.4, 260, 0.15, "red")              # ballast
        for k in range(200):                                  # sleepers
            box(tx, -2 + k * 1.3, 0.15, 2.6, 0.35, 0.08, "black")
        for side in (-0.75, 0.75):                            # rails
            box(tx + side, 120, 0.23, 0.18, 260, 0.14, "white")
    for tx in (-6.2, 6.2):                                    # catenary masts
        for k in range(10):
            box(tx, 30 + k * 18, 0.0, 0.3, 0.3, 6.0, "grey")
    for tx in (-4.0, 0.0, 4.0):                               # contact wires
        box(tx, 150, 5.6, 0.05, 240, 0.05, "black")
    for k in range(10):                                       # cross beams
        box(0, 30 + k * 18, 5.9, 12.6, 0.25, 0.25, "grey")

    # --- the train on the middle track: 3 cars ----------------------------------
    for car in range(3):
        y0 = 4 + car * 9.6
        box(0, y0 + 4.5, 0.4, 2.9, 9.0, 3.0, "green")          # body
        box(0, y0 + 4.5, 1.9, 2.95, 9.05, 0.35, "white")       # stripe
        for side in (-1.48, 1.48):                            # windows
            for w in range(4):
                box(side, y0 + 1.6 + w * 2.0, 2.4, 0.05, 1.2, 0.7, "blue")
        box(0, y0 + 4.5, 3.4, 2.4, 8.4, 0.15, "grey")          # roof
    box(0, 26.0, 3.55, 0.15, 0.15, 2.0, "black")               # pantograph (on car 3)
    box(0, 26.0, 5.5, 1.8, 0.3, 0.1, "black")

    # --- the runner, in the air above the first car (back to the camera) ------
    ry, rz, k = 7.0, 4.4, 1.6                                 # (k: scaled up to read)
    box(-0.25 * k, ry, rz, 0.32 * k, 0.4 * k, 0.95 * k, "bblue")          # legs, mid stride
    box(0.25 * k, ry + 0.35 * k, rz + 0.15 * k, 0.32 * k, 0.4 * k, 0.8 * k, "bblue")
    box(0, ry, rz + 0.9 * k, 0.95 * k, 0.5 * k, 0.95 * k, "bred")         # shirt
    box(0, ry - 0.3 * k, rz + 1.0 * k, 0.75 * k, 0.3 * k, 0.75 * k, "black")  # backpack
    box(-0.6 * k, ry + 0.1 * k, rz + 1.4 * k, 0.25 * k, 0.25 * k, 0.7 * k, "pink", 0.4)  # arms
    box(0.6 * k, ry + 0.1 * k, rz + 1.4 * k, 0.25 * k, 0.25 * k, 0.7 * k, "pink", -0.4)
    box(0, ry, rz + 1.85 * k, 0.55 * k, 0.5 * k, 0.55 * k, "pink")        # head
    box(0, ry - 0.05 * k, rz + 2.3 * k, 0.6 * k, 0.55 * k, 0.15 * k, "black")  # hair

    # --- coins: an arc ahead of the runner ------------------------------------
    for k in range(6):
        cylinder(-3.5 + k * 1.4, 12 + k * 1.5, 7.2 + 1.8 * math.sin(math.pi * k / 5), 0.75, 0.2,
                 "yellow", rot=(math.pi / 2, 0, 0))

    # --- footbridge across the tracks -----------------------------------------
    box(0, 62, 6.0, 24, 2.4, 0.6, "white")
    for px in (-11, 11):
        box(px, 62, 0.0, 0.8, 0.8, 6.0, "grey")
    box(0, 61.0, 6.6, 24, 0.15, 1.0, "bblue")                  # railings
    box(0, 63.0, 6.6, 24, 0.15, 1.0, "bblue")

    # --- the avenue: cars, a taxi, a bus; buildings behind ----------------------
    cars = [(-20, 8, "white"), (-17.5, 22, "bred"), (-12.5, 14, "yellow"), (-10, 34, "bblue"),
            (-20, 44, "grey"), (-12.5, 52, "white")]
    for cx, cy, c in cars:
        box(cx, cy, 0.0, 1.8, 4.0, 1.2, c)
        box(cx, cy - 0.2, 1.2, 1.6, 2.0, 0.6, "black")
    box(-17.5, 30, 0.0, 2.4, 11.0, 3.0, "bblue")               # bus
    box(-17.5, 30, 1.8, 2.45, 10.0, 0.7, "white")
    for k in range(8):                                        # apartment blocks (near ones)
        h = 6 + (k * 37) % 7
        c = ("white", "pink", "grey", "pyellow")[k % 4]
        box(-30 - (k % 2) * 7, 6 + k * 14, 0.0, 8, 11, h, c)
        for f in range(int(h // 3)):
            box(-25.9 - (k % 2) * 7, 6 + k * 14, 1.5 + f * 3, 0.1, 9, 0.9, "blue")

    # --- pine forest on the right ---------------------------------------------
    for k in range(70):
        x = 9 + (k * 53) % 28
        y = 4 + (k * 29) % 150
        h = 6 + (k * 7) % 5
        cone(x, y, 0.0, 1.8, h, "green" if k % 3 else "bgreen")
        box(x, y, 0.0, 0.35, 0.35, 1.0, "red")

    # --- horizon: Piraeus (the sea, harbour cranes) ----------------------------
    # (the Acropolis is painted with the sky: tools/quantize_loading.py)
    box(70, 240, -1, 200, 120, 1.2, "blue")                    # the sea (right)
    for k in range(3):                                         # harbour cranes
        cx = 55 + k * 18
        box(cx, 205, 0, 1.5, 1.5, 22, "blue")
        box(cx - 6, 205, 21, 16, 1.2, 1.4, "blue")
        box(cx - 13, 205, 12, 0.4, 0.4, 9, "black")

    # --- camera, render --------------------------------------------------------
    bpy.ops.object.camera_add(location=(0, -6.0, 8.5), rotation=(math.radians(83), 0, 0))
    cam = bpy.context.active_object
    cam.data.lens = 17
    sc.camera = cam
    r = sc.render
    r.engine = "BLENDER_WORKBENCH"
    r.resolution_x, r.resolution_y, r.resolution_percentage = 1536, 672, 100
    r.film_transparent = True
    sh = sc.display.shading
    sh.light = "FLAT"
    sh.color_type = "MATERIAL"
    sh.show_object_outline = True
    sh.object_outline_color = (0, 0, 0)
    sc.display_settings.display_device = "sRGB"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.view_settings.exposure = 0
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.filepath = os.path.join(OUT, "loading_4x.png")
    bpy.ops.render.render(write_still=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "loading_scene.blend"))


scene()
