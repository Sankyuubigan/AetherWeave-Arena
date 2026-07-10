import bpy
import sys
import os

TARGET_TRIANGLES = 15000
TEXTURE_MAX_SIZE = 1024
BAKE_IMAGE_SIZE = 1024
SKIP_BAKE = False
USE_REMESH = False
REMESH_VOXEL_SIZE = 0.035


def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)


def delete_collection(name):
    coll = bpy.data.collections.get(name)
    if coll:
        for obj in list(coll.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.collections.remove(coll)


def resize_textures(max_size):
    for img in bpy.data.images:
        if img.size[0] > max_size or img.size[1] > max_size:
            old_size = f"{img.size[0]}x{img.size[1]}"
            ratio = min(max_size / img.size[0], max_size / img.size[1])
            new_w = max(4, int(img.size[0] * ratio))
            new_h = max(4, int(img.size[1] * ratio))
            img.scale(new_w, new_h)
            print(f"  '{img.name}': {old_size} -> {new_w}x{new_h}")


def build_material_with_arm(lp_obj, tex_diff, tex_rough):
    mat = bpy.data.materials.new(name=f"{lp_obj.name}_mat")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    out = nodes.new('ShaderNodeOutputMaterial')
    out.location = (500, 0)
    bsdf = nodes.new('ShaderNodeBsdfPrincipled')
    bsdf.location = (0, 0)
    links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])

    if tex_diff:
        n = nodes.new('ShaderNodeTexImage')
        n.image = tex_diff
        n.location = (-400, 200)
        links.new(n.outputs['Color'], bsdf.inputs['Base Color'])

    if tex_rough:
        n = nodes.new('ShaderNodeTexImage')
        n.image = tex_rough
        n.location = (-400, -100)
        n.image.colorspace_settings.name = 'Non-Color'
        name_lower = tex_rough.name.lower()
        if 'arm' in name_lower:
            sep = nodes.new('ShaderNodeSeparateColor')
            sep.location = (-200, -100)
            sep.mode = 'RGB'
            links.new(n.outputs['Color'], sep.inputs['Color'])
            links.new(sep.outputs['Green'], bsdf.inputs['Roughness'])
            links.new(sep.outputs['Blue'], bsdf.inputs['Metallic'])
        else:
            links.new(n.outputs['Color'], bsdf.inputs['Roughness'])

    if lp_obj.data.materials:
        lp_obj.data.materials[0] = mat
    else:
        lp_obj.data.materials.append(mat)
    return mat, nodes, links, bsdf


def bake_normal_map(lp_obj, hp_obj, nodes, links, bsdf):
    img_name = f"{lp_obj.name}_baked_normal"
    baked_img = bpy.data.images.new(
        name=img_name, width=BAKE_IMAGE_SIZE, height=BAKE_IMAGE_SIZE, alpha=False
    )
    baked_img.colorspace_settings.name = 'Non-Color'

    tex_node = nodes.new('ShaderNodeTexImage')
    tex_node.location = (-400, 500)
    tex_node.image = baked_img
    tex_node.select = True
    nodes.active = tex_node

    norm_node = nodes.new('ShaderNodeNormalMap')
    norm_node.location = (-200, 500)
    links.new(tex_node.outputs['Color'], norm_node.inputs['Color'])
    links.new(norm_node.outputs['Normal'], bsdf.inputs['Normal'])

    bpy.ops.object.select_all(action='DESELECT')
    hp_obj.select_set(True)
    lp_obj.select_set(True)
    bpy.context.view_layer.objects.active = lp_obj

    bpy.context.scene.render.bake.use_selected_to_active = True
    bpy.context.scene.render.bake.cage_extrusion = 0.01
    bpy.context.scene.render.bake.max_ray_distance = 0.5
    bpy.context.scene.render.bake.margin = 8
    try:
        bpy.ops.object.bake(type='NORMAL')
        baked_img.pack()
        print(f"    Baked OK")
    except Exception as e:
        print(f"    Bake FAILED: {e}")


def process_model(filepath, output_dir, skip_decimate=False):
    base_name = os.path.splitext(os.path.basename(filepath))[0]
    print(f"\n{'='*60}")
    print(f"STEP 1: IMPORT: {filepath}")
    print(f"{'='*60}")

    clear_scene()
    bpy.ops.import_scene.gltf(filepath=filepath)

    highpoly_objects = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
    if not highpoly_objects:
        print("ERROR: No mesh objects found!")
        return False

    total_before = sum(
        len(obj.evaluated_get(bpy.context.evaluated_depsgraph_get()).data.loop_triangles)
        for obj in highpoly_objects
    )
    print(f"Total tris: {total_before:,}")

    hp_coll = bpy.data.collections.new("HighPoly")
    bpy.context.scene.collection.children.link(hp_coll)
    for obj in highpoly_objects:
        for coll in obj.users_collection:
            coll.objects.unlink(obj)
        hp_coll.objects.link(obj)

    print(f"\nSTEP 1b: RESIZE TEXTURES TO {TEXTURE_MAX_SIZE}x{TEXTURE_MAX_SIZE}")
    resize_textures(TEXTURE_MAX_SIZE)

    if skip_decimate:
        lowpoly_objects = list(highpoly_objects)
        lp_coll = bpy.data.collections.new("LowPoly")
        bpy.context.scene.collection.children.link(lp_coll)
        for obj in lowpoly_objects:
            for coll in obj.users_collection:
                coll.objects.unlink(obj)
            lp_coll.objects.link(obj)
        print("DECIMATION SKIPPED")
    else:
        print(f"\nSTEP 2: {'REMESH (VOXEL)' if USE_REMESH else 'DECIMATE'}")
        print(f"{'='*60}")

        lowpoly_objects = []
        for obj in highpoly_objects:
            new_obj = obj.copy()
            new_obj.data = obj.data.copy()
            bpy.context.scene.collection.objects.link(new_obj)
            lowpoly_objects.append(new_obj)

        lp_coll = bpy.data.collections.new("LowPoly")
        bpy.context.scene.collection.children.link(lp_coll)
        for obj in lowpoly_objects:
            bpy.context.scene.collection.objects.unlink(obj)
            lp_coll.objects.link(obj)

        bpy.ops.object.select_all(action='DESELECT')

        mesh_tris = []
        for obj in lowpoly_objects:
            depsgraph = bpy.context.evaluated_depsgraph_get()
            eval_obj = obj.evaluated_get(depsgraph)
            ct = len(eval_obj.data.loop_triangles)
            mesh_tris.append((obj, ct))

        total_before_lp = sum(t for _, t in mesh_tris)

        for obj, current_tris in mesh_tris:
            if total_before_lp <= TARGET_TRIANGLES:
                print(f"  '{obj.name}': {current_tris:,} tris — total already under budget")
                continue
            target_for_mesh = max(4, round(TARGET_TRIANGLES * current_tris / total_before_lp))
            if current_tris <= target_for_mesh:
                print(f"  '{obj.name}': {current_tris:,} tris — already under target")
                continue

            print(f"  '{obj.name}': {current_tris:,} -> target {target_for_mesh:,} tris")

            bpy.context.view_layer.objects.active = obj
            bpy.ops.object.select_all(action='DESELECT')
            obj.select_set(True)

            if USE_REMESH:
                mod = obj.modifiers.new(name='Remesh', type='REMESH')
                mod.mode = 'VOXEL'
                mod.voxel_size = REMESH_VOXEL_SIZE
                mod.adaptivity = 0.0
                bpy.ops.object.modifier_apply(modifier=mod.name)

                bpy.ops.object.mode_set(mode='EDIT')
                bpy.ops.mesh.select_all(action='SELECT')
                bpy.ops.uv.smart_project(angle_limit=66, island_margin=0.02)
                bpy.ops.mesh.normals_make_consistent(inside=False)
                bpy.ops.object.mode_set(mode='OBJECT')

                tex_diff = tex_rough = None
                for img in bpy.data.images:
                    name_lower = img.name.lower()
                    if 'diff' in name_lower and img.size[0] > 1:
                        tex_diff = img
                    elif ('rough' in name_lower or 'arm' in name_lower) and img.size[0] > 1:
                        tex_rough = img

                bpy.context.scene.render.engine = 'CYCLES'
                bpy.context.scene.cycles.device = 'GPU'
                mat, nodes, links, bsdf = build_material_with_arm(obj, tex_diff, tex_rough)
                bake_normal_map(obj, hp_coll.objects[0], nodes, links, bsdf)
            else:
                ratio = target_for_mesh / current_tris
                if ratio >= 1.0:
                    print(f"    already at target ratio {ratio:.3f}, skipping")
                    continue

                mod = obj.modifiers.new(name='Decimate', type='DECIMATE')
                mod.ratio = ratio
                mod.use_collapse_triangulate = False
                mod.delimit = {'NORMAL', 'UV', 'SEAM', 'SHARP'}
                bpy.ops.object.modifier_apply(modifier=mod.name)

                bpy.ops.object.mode_set(mode='EDIT')
                bpy.ops.mesh.select_all(action='SELECT')
                bpy.ops.mesh.normals_make_consistent(inside=False)
                bpy.ops.object.mode_set(mode='OBJECT')

            depsgraph = bpy.context.evaluated_depsgraph_get()
            eval_obj = obj.evaluated_get(depsgraph)
            new_tris = len(eval_obj.data.loop_triangles)
            reduction = 1.0 - (new_tris / current_tris) if current_tris > 0 else 0
            print(f"    {current_tris:,} -> {new_tris:,} ({reduction*100:.1f}%)")
            print(f"  final: {current_tris:,} -> {new_tris:,} tris (target was {target_for_mesh:,})")

    if not SKIP_BAKE and not USE_REMESH:
        print(f"\nSTEP 3: BAKE NORMAL MAPS (High-Poly -> Low-Poly)")
        hp_list = list(hp_coll.objects)
        lp_list = list(lp_coll.objects)

        if len(hp_list) != len(lp_list):
            print(f"WARNING: High-poly count ({len(hp_list)}) != Low-poly count ({len(lp_list)}).")

        bpy.context.scene.render.engine = 'CYCLES'
        bpy.context.scene.cycles.device = 'GPU'

        for idx, lp_obj in enumerate(lp_list):
            hp_obj = hp_list[idx] if idx < len(hp_list) else None
            if not hp_obj:
                print(f"  No matching high-poly for '{lp_obj.name}', skipping")
                continue

            print(f"\n  Baking: '{lp_obj.name}' <- '{hp_obj.name}'")

            mat = lp_obj.data.materials[0] if lp_obj.data.materials else None
            if not mat:
                mat = bpy.data.materials.new(name=f"{lp_obj.name}_mat")
                lp_obj.data.materials.append(mat)
            mat.use_nodes = True
            nodes = mat.node_tree.nodes
            links = mat.node_tree.links

            img_name = f"{lp_obj.name}_baked_normal"
            baked_img = bpy.data.images.new(
                name=img_name, width=BAKE_IMAGE_SIZE, height=BAKE_IMAGE_SIZE, alpha=False
            )
            baked_img.colorspace_settings.name = 'Non-Color'

            tex_node = nodes.new('ShaderNodeTexImage')
            tex_node.location = (-600, 300)
            tex_node.image = baked_img
            tex_node.select = True
            nodes.active = tex_node

            norm_node = None
            for node in nodes:
                if node.type == 'NORMAL_MAP':
                    norm_node = node
                    break
            if not norm_node:
                norm_node = nodes.new('ShaderNodeNormalMap')
                norm_node.location = (-400, 300)

            principled = None
            for node in nodes:
                if node.type == 'BSDF_PRINCIPLED':
                    principled = node
                    break

            if principled:
                try:
                    links.new(tex_node.outputs['Color'], norm_node.inputs['Color'])
                    links.new(norm_node.outputs['Normal'], principled.inputs['Normal'])
                except Exception:
                    pass

            bpy.ops.object.select_all(action='DESELECT')
            hp_obj.select_set(True)
            lp_obj.select_set(True)
            bpy.context.view_layer.objects.active = lp_obj

            hp_coll.hide_viewport = False
            hp_coll.hide_render = False
            lp_coll.hide_viewport = False
            lp_coll.hide_render = False

            bpy.context.scene.render.bake.use_selected_to_active = True
            bpy.context.scene.render.bake.cage_extrusion = 0.01
            bpy.context.scene.render.bake.max_ray_distance = 0.5
            bpy.context.scene.render.bake.margin = 8
            try:
                bpy.ops.object.bake(type='NORMAL')
                baked_img.pack()
                print(f"    Baked OK")
            except Exception as e:
                print(f"    Bake FAILED: {e}")

    elif SKIP_BAKE and not USE_REMESH:
        print(f"\nSTEP 3: SKIPPED (--no-bake)")

    print(f"\nSTEP 4: EXPORT")
    hp_coll.hide_viewport = True
    hp_coll.hide_render = True

    bpy.ops.object.select_all(action='DESELECT')
    for obj in lowpoly_objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = lowpoly_objects[0] if lowpoly_objects else None

    os.makedirs(output_dir, exist_ok=True)
    out_gltf_path = os.path.join(output_dir, base_name + "_baked.gltf")

    bpy.ops.export_scene.gltf(
        filepath=out_gltf_path,
        export_format='GLTF_SEPARATE',
        export_image_format='WEBP',
        export_texcoords=True,
        export_normals=True,
        export_materials='EXPORT',
        export_keep_originals=False,
        use_selection=True
    )

    total_after = sum(
        len(obj.evaluated_get(bpy.context.evaluated_depsgraph_get()).data.loop_triangles)
        for obj in lowpoly_objects
    )

    print(f"\n{'='*60}")
    print(f"SUMMARY for {base_name}")
    print(f"{'='*60}")
    print(f"  Tris before: {total_before:,}")
    print(f"  Tris after:  {total_after:,}")
    print(f"  Reduction:   {(1 - total_after/total_before)*100:.1f}%")
    print(f"  Output:      {out_gltf_path}")

    out_size = 0
    for root_dir, dirs, files in os.walk(output_dir):
        for f in files:
            out_size += os.path.getsize(os.path.join(root_dir, f))
    print(f"  Output size: {out_size / (1024*1024):.1f} MB")
    return True


if __name__ == "__main__":
    argv = sys.argv
    idx = len(argv) - 1
    for i, arg in enumerate(argv):
        if arg == "--":
            idx = i + 1
            break

    if idx >= len(argv):
        print("Usage: blender --background --python optimize_triangles.py -- <input_gltf_path> [--no-bake] [--no-decimate] [--remesh]")
        sys.exit(1)

    input_path = argv[idx]
    output_dir = os.path.join(os.path.dirname(input_path), "..", "..", "..", "..", "..", "decimated_baked")

    if '--no-bake' in argv:
        SKIP_BAKE = True
        print("Normal bake SKIPPED (--no-bake)")
    if '--no-decimate' in argv:
        skip_decimate = True
        print("Decimation SKIPPED (--no-decimate)")
    else:
        skip_decimate = False
    if '--remesh' in argv:
        USE_REMESH = True
        print("Using REMESH (Voxel) mode")

    output_dir = os.path.abspath(output_dir)

    if not os.path.exists(input_path):
        print(f"ERROR: Input file not found: {input_path}")
        sys.exit(1)

    success = process_model(input_path, output_dir, skip_decimate=skip_decimate)
    sys.exit(0 if success else 1)
