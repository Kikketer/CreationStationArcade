# wgpu Performance Investigation for MakeCode Arcade

**Date:** 2026-05-17
**Context:** Debian x86 arcade machine performance issues

## Problem Statement

The current arcade setup uses Chromium in kiosk mode to run the MakeCode Arcade simulator. Performance is poor on lower-end hardware due to:

1. **Browser overhead**: JavaScript VM + V8 engine + Browser compositor
2. **Canvas 2D rendering**: CPU-based 2D canvas operations
3. **No GPU acceleration**: Despite GPU flags, Canvas 2D doesn't leverage GPU effectively

Current render pipeline:
```
Game .elf/JS → Browser JS VM → Canvas 2D (CPU) → Browser compositor → Screen
```

## Investigation Findings

### Root Causes of Poor Performance

1. **Canvas 2D is CPU-bound**: The MakeCode simulator uses HTML5 Canvas 2D API which is primarily CPU-based rendering
2. **Browser overhead**: Even with `--enable-gpu-rasterization`, the browser still has significant compositor overhead
3. **JavaScript interpretation**: The MakeCode VM runs in JavaScript which adds overhead compared to native execution

### GPU Flags Tested

Added to Chromium launcher:
- `--enable-features=VaapiVideoDecoder`
- `--ignore-gpu-blocklist`
- `--enable-gpu-rasterization`
- `--enable-zero-copy`

**Result**: Minimal improvement. Canvas 2D is still the bottleneck.

## Proposed Solutions

### Option A: Rust + wgpu Native Application

**Architecture:**
```
Game bytecode → Native interpreter (Rust) → wgpu → GPU → Screen
```

**Pros:**
- Maximum performance potential
- Full control over rendering pipeline
- Can optimize specifically for MakeCode Arcade patterns

**Cons:**
- Significant development effort (~2-3 months)
- Need to reverse-engineer MakeCode VM bytecode format
- Compatibility testing with all existing games

**Technical Requirements:**
- Custom MakeCode bytecode interpreter in Rust
- wgpu-based renderer for sprites, tilemaps, particles
- SDL2 or winit for window/input handling
- Audio system (rodio or similar)

### Option B: WebGPU + Existing JavaScript Runtime (RECOMMENDED)

**Architecture:**
```
Game bytecode → MakeCode JS Runtime → WebGPU API → wgpu → GPU → Screen
```

**Pros:**
- Keep existing MakeCode JavaScript runtime (maintains compatibility)
- 5-10x performance improvement over Canvas 2D
- WebGPU API is well-documented and stable
- Can prototype quickly (weeks not months)

**Cons:**
- Still some JavaScript overhead
- Need to modify simulator to use WebGPU instead of Canvas 2D

**Technical Approach:**
1. Modify `pxtsim.js` and `sim.js` to use WebGPU instead of Canvas 2D
2. Create WebGPU shaders for:
   - Sprite rendering (texture atlas-based)
   - Tilemap rendering (instanced drawing)
   - Screen effects (post-processing shaders)
3. Replace Canvas 2D context with WebGPU context in the HTML

**Performance Expectation:** 5-10x frame rate improvement

### Option C: Native App with Embedded JavaScript Engine

**Architecture:**
```
Game bytecode → Embedded JS Engine (QuickJS/V8) → Intercepted Canvas → wgpu → GPU → Screen
```

**Pros:**
- Can use existing MakeCode JS code
- Native app avoids browser overhead
- Canvas calls intercepted and redirected to GPU

**Cons:**
- Medium complexity
- Need to implement Canvas 2D API on top of wgpu
- More moving parts than Option B

## Recommendation

**Start with Option B** (WebGPU + Existing JS Runtime) because:

1. **Fastest time to prototype** - Can modify existing simulator code
2. **Best ROI** - 5-10x improvement with minimal compatibility risk
3. **Iterative** - Can fall back to Canvas 2D if issues arise
4. **Educational** - Learn MakeCode rendering patterns before committing to full native rewrite

If Option B doesn't provide sufficient performance, then pursue Option A for maximum performance.

## Next Steps for Option B

1. Analyze MakeCode simulator rendering patterns in `sim.js` and `pxtsim.js`
2. Create WebGPU shader equivalents for:
   - 2D sprite blitting
   - 8-bit palette handling
   - Screen effects (pixelation, scanlines)
3. Modify the simulator HTML to use WebGPU context
4. Test with performance-heavy games
5. Measure frame rate improvement

## Resources

- MakeCode Arcade source: https://github.com/microsoft/pxt-arcade
- WebGPU spec: https://gpuweb.github.io/gpuweb/
- wgpu Rust crate: https://github.com/gfx-rs/wgpu
- Electrobun (inspiration): https://blackboard.sh/electrobun/

## Files Modified During Investigation

- `install/debian-x86-setup.sh` - Added `xinit`, `xdotool` packages
- `launcher.sh` - Added GPU acceleration flags, focus fix with triple-tab
- `.bash_profile` - Fixed PATH issue with full path to `/usr/bin/startx`
- `install/kiosk-setup.sh` - Identified nested folder bug in rsync

## Issues Discovered

1. **Missing `xinit` package** - Setup script didn't install `xinit` which provides `startx`
2. **Nested folder bug** - rsync created `CreationStationArcade-run/CreationStationArcade/` instead of flat structure
3. **PATH not set during TTY1 login** - `.bash_profile` needs to source `.profile` before startx check
4. **Focus issue in kiosk mode** - Required xdotool + triple-tab hack to get keyboard focus
