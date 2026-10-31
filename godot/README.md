# Shell fur for Godot 4 (Compatibility / WebGL2)

A Godot port of this repo's shell-fur shader, made to work on **any rigged or static mesh**. It was built for [Sector](https://roundup.studio) by Round Up Studio.

- `FurCoat.gd`: add it as a child of a model. It bakes the fur layers, keeping the bone weights so the fur animates with the skeleton. Fur direction comes from the bones, fur is shorter on thin parts (ears, legs), and eyes and noses stay bald. Copies of one model share a single bake.
- `fur_shell.gdshader`: the strand pattern, Kajiya-Kay/Marschner-style hair lighting, and a distance fade that stops sparkle.
- `FUR_THIRD_PARTY.md`: what was derived from this repo's Three.js code, with its full MIT license.

```gdscript
var coat = preload("res://godot/FurCoat.gd").new()   # keep the three files together
coat.shells = 12
model.add_child(coat)
```

`PRESETS` in `FurCoat.gd` holds the settings checked on Quaternius (CC0) animals; `FurCoat.for_model(path, shells, range)` applies them by file name. The header of `FurCoat.gd` lists the limitations.

MIT, like the rest of this repo.
