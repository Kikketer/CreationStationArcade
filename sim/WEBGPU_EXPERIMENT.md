# WebGPU Simulator Experiment

This is an experimental WebGPU-based renderer for the MakeCode Arcade simulator, designed to improve performance on low-powered hardware like the Raspberry Pi 3 and older x86 machines.

## The Problem

The current simulator uses HTML5 Canvas 2D API which is **CPU-bound**:

```javascript
// Current Canvas 2D approach (sim.js:1382-1412)
draw(state) {
    const context = this.screen.getContext("2d", { willReadFrequently: true });
    
    if (this.scaleFactor === 1) {
        // Path 1: Direct pixel blit (fastest Canvas 2D can do)
        let img = context.getImageData(0, 0, state.width, state.height);
        new Uint32Array(img.data.buffer).set(state.screen);
        context.putImageData(img, 0, 0);  // CPU → GPU copy
    } else {
        // Path 2: CPU-per-pixel loop (SLOW! O(n²) operations)
        for (let x = 0; x < state.width; x++) {
            for (let y = 0; y < state.height; y++) {
                context.fillStyle = this.palette[state.lastImage.data[x + y * state.width] & mask];
                context.fillRect(x * this.scaleFactor, y * this.scaleFactor, 
                               this.scaleFactor, this.scaleFactor);  // 1 call per pixel!
            }
        }
    }
}
```

**Performance Bottlenecks:**
1. `putImageData()` requires a full CPU → GPU texture copy every frame
2. The `fillRect()` scaling path does **N×M** JavaScript → Canvas API calls per frame
3. Canvas 2D operations are serialized through the browser's compositor thread

## The WebGPU Solution

```
┌─────────────────┐     ┌─────────────┐     ┌─────────────┐     ┌──────────┐
│ Game Bytecode   │────▶│ MakeCode VM │────▶│ ScreenState │────▶│ WebGPU   │
│   (JavaScript)  │     │  (JavaScript)│     │(Uint8 buffer)│     │ Renderer │
└─────────────────┘     └─────────────┘     └─────────────┘     └────┬─────┘
                                                                       │
                               ┌───────────────────────────────────────┘
                               ▼
                    ┌─────────────────────┐
                    │ GPU Shader Pipeline │
                    │ ─────────────────── │
                    │ • Upload screen as    │
                    │   R8 texture (1 byte  │
                    │   per pixel)          │
                    │ • Upload palette as   │
                    │   storage buffer      │
                    │ • Vertex shader:      │
                    │   full-screen quad    │
                    │ • Fragment shader:    │
                    │   texture sample +    │
                    │   palette lookup      │
                    └──────────┬──────────┘
                               │
                               ▼
                    ┌─────────────────────┐
                    │ Display (scaled by  │
                    │ GPU sampler, not    │
                    │ CPU loops!)         │
                    └─────────────────────┘
```

**Key Improvements:**
1. **Single texture upload** per frame (not N×M fillRect calls)
2. **Palette lookup on GPU** via fragment shader
3. **Scaling handled by GPU sampler** with nearest-neighbor filtering
4. **No JavaScript → Canvas API bottleneck**

## Architecture

### Files

- **`webgpu-renderer.js`** - Core WebGPU renderer class
  - `MakeCodeWebGPURenderer` - Manages WebGPU device, pipeline, and rendering
  - `initWebGPURenderer()` - Async initialization with fallback
  - `drawWebGPU()` - Draw function to be called from patched code

- **`webgpu-patch.js`** - Runtime patch for the existing simulator
  - Automatically patches `pxsim.visuals.GamePlayer.prototype.draw`
  - Falls back to Canvas 2D if WebGPU unavailable
  - Provides `window.WebGPUPatch` API for manual control

- **`webgpu.html`** - Modified simulator HTML
  - Includes WebGPU renderer and patch scripts
  - Shows status indicator (WebGPU vs Canvas 2D)
  - Otherwise identical to standard simulator

### Shader Pipeline

**Vertex Shader:**
```wgsl
@vertex
fn main(@location(0) position: vec2<f32>) -> @builtin(position) vec4<f32> {
    return vec4<f32>(position, 0.0, 1.0);
}
```

**Fragment Shader:**
```wgsl
@fragment
fn main(@builtin(position) fragCoord: vec4<f32>) -> @location(0) vec4<f32> {
    // Sample screen texture (contains palette indices)
    let paletteIndex = textureSample(screenTexture, screenSampler, uv).r;
    
    // Look up color in palette (GPU-side)
    let index = u32(paletteIndex * 255.0 + 0.5) % u32(params.paletteSize);
    return palette[index];
}
```

## Usage

### Testing the WebGPU Simulator

1. Open `webgpu.html` in a WebGPU-capable browser:
   ```bash
   # From the sim directory
   npx serve . --port 3001
   
   # Then open http://localhost:3001/webgpu.html
   ```

2. Check the indicator in top-right:
   - **Green "WebGPU"** - GPU rendering active
   - **Orange "Canvas 2D"** - Fallback mode (WebGPU unavailable)

3. Load a game by sending a postMessage (same as standard simulator):
   ```javascript
   // From browser console or parent frame
   document.querySelector('iframe').contentWindow.postMessage({
       type: "run",
       code: "/* game JS bundle */",
       parts: [],
       dependencies: {}
   }, "*");
   ```

### Integration with Arcade Setup

To use in the kiosk setup, modify `public/play.html` or create a WebGPU variant:

```html
<!-- Instead of sim/index.html -->
<iframe src="sim/webgpu.html?hideSimButtons&noExtraPadding" id="sim"></iframe>
```

Or enable via query parameter in standard setup:

```javascript
// In play.html or launcher
const useWebGPU = new URLSearchParams(window.location.search).get('webgpu') === '1';
const simUrl = useWebGPU ? 'sim/webgpu.html' : 'sim/index.html';
```

## Performance Expectations

| Metric | Canvas 2D | WebGPU | Expected Gain |
|--------|-----------|--------|---------------|
| 160x120 → 640x480 render | ~8-12ms (CPU) | ~1-2ms (GPU) | **5-10x faster** |
| CPU usage during gameplay | 60-80% | 20-30% | **3-4x lower** |
| Frame drops on Pi 3 | Frequent | Rare | **Smoother** |

**Why this matters for the arcade:**
- Pi 3 can maintain 60fps on games that previously struggled
- i3 x86 machine from your Debian test should see significant improvement
- CPU freed up for audio and game logic

## Browser Compatibility

WebGPU is supported in:
- ✅ Chrome 113+ (Linux, Windows, macOS)
- ✅ Edge 113+
- ✅ Firefox Nightly (behind flag)
- ❌ Safari (in development)

**For the arcade machine (Debian + Chromium):**
```bash
# Ensure recent Chromium
chromium --version  # Should be 113+

# Launch with WebGPU enabled (usually default now)
chromium --enable-unsafe-webgpu --enable-features=Vulkan
```

## Known Issues / TODO

1. **Shader compilation** - The inline WGSL might need external file loading for complex scenarios
2. **Multiple framebuffers** - Games with screen effects (shake, fade) may need special handling
3. **Pixel-perfect scaling** - Current shader uses nearest-neighbor; verify this matches expected output
4. **Color palette validation** - Need to verify exact color output matches Canvas 2D

## Testing Checklist

- [ ] Load and run `Gelb.js` - verify visual output matches Canvas 2D
- [ ] Check FPS on target hardware (Pi 3 / i3 x86)
- [ ] Verify all 4 players render correctly
- [ ] Test games with screen effects
- [ ] Test with different scale factors (1x, 2x, 4x)
- [ ] Verify fallback to Canvas 2D works when WebGPU unavailable
- [ ] Check memory usage (GPU texture memory vs CPU buffer)

## Further Optimizations

If this proves successful, consider:

1. **Sprite batching** - Upload sprite atlases to GPU, render sprites via instanced drawing
2. **Tilemap shader** - Render tilemaps on GPU instead of CPU blitting
3. **Screen effects** - Implement fade/flash/shake as GPU shaders
4. **Double buffering** - Use WebGPU's swap chain efficiently

## References

- [WebGPU Spec](https://gpuweb.github.io/gpuweb/)
- [WebGPU Fundamentals](https://webgpufundamentals.org/)
- [MakeCode Arcade Source](https://github.com/microsoft/pxt-arcade)
- Original investigation: `../plans/wgpu-performance-investigation.md`
