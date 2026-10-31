# Third-party notice: shell fur (FurCoat.gd, fur_shell.gdshader)

Parts of `fur_shell.gdshader` and `FurCoat.gd` are ported from **Mochi-Puff — 3D GPU Fur Simulation**:
- Repository: github.com/sector-blaster-devs/3D-GPU-Fur-Simulation (private)
- Revision ported from: `c5d295f8663997ba4a6dfbc6de5a3ac797ea4baf` (2026-10-27)
- License: MIT. Its full LICENSE text, unchanged, is reproduced below.

## What was derived (upstream file → here)

| Upstream | Ported into | What |
|---|---|---|
| `src/furShaders.js`: `COMMON_HAIR_BSDF_GLSL` | `fur_shell.gdshader` `hair_lobe()` / `light()` | Kajiya-Kay/Marschner-style R + TRT lobes, Beer-Lambert coat shadow, wrapped diffuse, TT transmission. Rewritten for Godot's `light()` |
| `src/furShaders.js`: `SHELL_VERTEX_SHADER` / `SHELL_FRAGMENT_SHADER` | `fur_shell.gdshader` `vertex()`, `strand()`, `fragment()` | Shell displacement with bend, wind wave, per-cell strand profile, curl and clumping, height-limited strands |
| `src/main.js` (WebGL-mode inertia spring) | `FurCoat.gd` `_process()` | Spring-damper drag (constants 1.65 / 24.0 / 5.5 / 0.8 clamp) |

## Written new for Sector (not from upstream)

- Fur on arbitrary rigged meshes: shell baking that keeps bone weights, the welded normals, and the triplanar strand layout on the bind pose.
- Grooming from the skeleton, the mesh-thickness fur cap, and bald areas by material name, size and brightness.
- The distance fade, presets, the shared bake cache, and the VFX tiers.

Upstream GPGPU simulation (`gpuPhysics.js`), instanced strands, the creature, environments and UI were **not** used.

## Upstream LICENSE (verbatim)

```text
MIT License

Copyright (c) 2026 Mochi-Puff Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
