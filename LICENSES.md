# Licenses & Third-Party Attributions

This document contains licensing and copyright notices for **Mochi-Puff — 3D GPU Fur Simulation**, its dependencies, typography, and foundational computer graphics algorithms.

---

## 1. Project License

**Mochi-Puff (fursim)** is released under the **MIT License**.

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

---

## 2. Direct Runtime Dependencies

### Three.js (`three`)
- **License**: MIT License
- **Copyright**: Copyright (c) 2010-2024 Three.js Authors (mrdoob and contributors)
- **Repository**: https://github.com/mrdoob/three.js
- **Description**: WebGL 3D rendering library and scene graph.

### React & React-DOM (`react`, `react-dom`)
- **License**: MIT License
- **Copyright**: Copyright (c) Meta Platforms, Inc. and affiliates
- **Repository**: https://github.com/facebook/react
- **Description**: Declarative UI library.

### Vite & Vite React Plugin (`vite`, `@vitejs/plugin-react`)
- **License**: MIT License
- **Copyright**: Copyright (c) 2019-present Evan You & Vite Contributors
- **Repository**: https://github.com/vitejs/vite
- **Description**: Frontend dev server, bundler, and JSX HMR integration.

### Google GenAI SDK (`@google/genai`)
- **License**: Apache License, Version 2.0
- **Copyright**: Copyright 2024-present Google LLC
- **Repository**: https://github.com/googleapis/genai-js
- **Description**: Official SDK for Google Gemini models and APIs.

---

## 3. Development Dependencies

### TypeScript (`typescript`)
- **License**: Apache License, Version 2.0
- **Copyright**: Copyright (c) Microsoft Corporation
- **Repository**: https://github.com/microsoft/TypeScript

### DefinitelyTyped Type Definitions (`@types/node`, `@types/react`, `@types/react-dom`)
- **License**: MIT License
- **Copyright**: Copyright (c) DefinitelyTyped Contributors
- **Repository**: https://github.com/DefinitelyTyped/DefinitelyTyped

---

## 4. Typography & Fonts

### Google Sans & Google Sans Text
- **Source**: Google Fonts
- **License**: SIL Open Font License, 1.1 / Apache License 2.0 / Google Fonts Terms of Service
- **Copyright**: Copyright Google LLC

---

## 5. Algorithmic & Scientific References

The real-time shader pipelines and simulation dynamics implemented in this project are based on the following published research:

1. **Marschner Hair Scattering Model**:
   - *Reference*: Marschner, S. R., Jensen, H. W., Cammarano, M., Worley, S., & Hanrahan, P. (2003). *"Light scattering from human hair fibers."* ACM Transactions on Graphics (TOG) / SIGGRAPH 2003.
   - *Usage*: Dual-specular longitudinal R / TRT lobes and TT transmission highlights.

2. **Kajiya-Kay Anisotropic Hair Reflection**:
   - *Reference*: Kajiya, J. T., & Kay, T. L. (1989). *"Rendering fur with three dimensional textures."* ACM SIGGRAPH Computer Graphics, 23(3), 271-280.
   - *Usage*: Tangent-space cylindrical hair specularity.

3. **Volumetric Shells & Fins Fur**:
   - *Reference*: Lengyel, J., Praun, E., Finkelstein, A., & Hoppe, H. (2001). *"Real-time fur over arbitrary surfaces."* ACM SIGGRAPH 2001.
   - *Usage*: Multi-layer concentric shells with alpha erosion.

4. **Simplex Noise & 3D Procedural Dynamics**:
   - *Reference*: Stefan Gustavson (Linköping University) / Ian McEwan (Ashima Arts).
   - *License*: Public Domain / MIT-compatible academic use.
