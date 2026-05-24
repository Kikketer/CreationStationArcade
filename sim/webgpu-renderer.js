/**
 * WebGPU Renderer for MakeCode Arcade Simulator
 * 
 * Replaces Canvas 2D rendering with WebGPU for improved performance.
 * Handles 8-bit palette-based screen rendering using GPU shaders.
 * 
 * Architecture:
 * - Screen buffer (Uint8Array) uploaded as texture each frame
 * - Palette uploaded as uniform buffer or 1D texture
 * - Full-screen quad with shader doing palette lookup
 * - Handles scaling via GPU sampler, not CPU loops
 */

class MakeCodeWebGPURenderer {
    constructor(canvas) {
        this.canvas = canvas;
        this.device = null;
        this.context = null;
        this.pipeline = null;
        this.bindGroup = null;
        this.sampler = null;
        this.screenTexture = null;
        this.paletteBuffer = null;
        this.uniformBuffer = null;
        this.vertexBuffer = null;
        this.renderPassDescriptor = null;
        
        // Screen dimensions
        this.screenWidth = 0;
        this.screenHeight = 0;
        this.scaleFactor = 1;
        
        // Palette cache
        this.cachedPalette = null;
        this.paletteChanged = true;
        
        // Stats
        this.frameCount = 0;
        this.lastTime = performance.now();
        this.fps = 0;
    }

    async init() {
        // Check WebGPU support first
        if (!navigator.gpu) {
            throw new Error('WebGPU not supported - navigator.gpu is undefined');
        }
        
        // Log Chrome version info
        const ua = navigator.userAgent;
        const chromeMatch = ua.match(/Chrome\/(\d+)/);
        console.log('WebGPU init: Chrome version =', chromeMatch ? chromeMatch[1] : 'unknown');

        // First test if we can get WebGPU context on a TEMP canvas
        // (We must NOT touch the real canvas until we know WebGPU works)
        console.log('WebGPU init: testing context on temp canvas...');
        const testCanvas = document.createElement('canvas');
        testCanvas.width = 1;
        testCanvas.height = 1;
        const testContext = testCanvas.getContext('webgpu');
        
        if (!testContext) {
            throw new Error(`WebGPU API available but canvas context not supported. ` +
                `Chrome ${chromeMatch ? chromeMatch[1] : 'unknown'}. ` +
                `Try: chrome://flags/#enable-unsafe-webgpu or --enable-unsafe-webgpu flag`);
        }
        console.log('WebGPU init: temp canvas context works');

        const adapter = await navigator.gpu.requestAdapter({
            powerPreference: 'high-performance'
        });
        
        if (!adapter) {
            throw new Error('No WebGPU adapter found');
        }
        
        console.log('WebGPU init: adapter acquired');

        this.device = await adapter.requestDevice();
        console.log('WebGPU init: device created');
        
        // NOW try to get WebGPU context from the REAL canvas
        // (We're confident it should work since temp canvas worked)
        this.context = this.canvas.getContext('webgpu');
        if (!this.context) {
            throw new Error(`Could not get WebGPU context from game canvas (unexpected - temp canvas worked)`);
        }
        
        const canvasFormat = navigator.gpu.getPreferredCanvasFormat();
        
        this.context.configure({
            device: this.device,
            format: canvasFormat,
            alphaMode: 'premultiplied',
            usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.COPY_DST
        });

        await this.createPipeline(canvasFormat);
        this.createVertexBuffer();
        
        return true;
    }

    async createPipeline(format) {
        // Vertex shader - full screen quad
        const vertexShaderCode = `
            @vertex
            fn main(@location(0) position: vec2<f32>) -> @builtin(position) vec4<f32> {
                return vec4<f32>(position, 0.0, 1.0);
            }
        `;

        // Fragment shader - palette lookup
        const fragmentShaderCode = `
            @group(0) @binding(0) var screenSampler: sampler;
            @group(0) @binding(1) var screenTexture: texture_2d<f32>;
            @group(0) @binding(2) var<storage, read> palette: array<vec4<f32>>;
            @group(0) @binding(3) var<uniform> params: Params;
            
            struct Params {
                screenWidth: f32,
                screenHeight: f32,
                paletteSize: f32,
                _padding: f32,
            };
            
            @fragment
            fn main(@builtin(position) fragCoord: vec4<f32>) -> @location(0) vec4<f32> {
                // Calculate UV coordinates
                let uv = fragCoord.xy / vec2<f32>(params.screenWidth, params.screenHeight);
                
                // Sample the screen texture (contains palette indices)
                let paletteIndex = textureSample(screenTexture, screenSampler, uv).r;
                
                // Look up the color in the palette
                let index = u32(paletteIndex * 255.0 + 0.5) % u32(params.paletteSize);
                return palette[index];
            }
        `;

        // Create shader modules
        const vertexModule = this.device.createShaderModule({
            code: vertexShaderCode
        });

        const fragmentModule = this.device.createShaderModule({
            code: fragmentShaderCode
        });

        // Create uniform buffer for parameters
        this.uniformBuffer = this.device.createBuffer({
            size: 16, // 4 floats * 4 bytes
            usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST
        });

        // Create palette buffer (max 256 colors * 4 floats * 4 bytes = 4096 bytes)
        this.paletteBuffer = this.device.createBuffer({
            size: 4096,
            usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST
        });

        // Create pipeline layout
        const bindGroupLayout = this.device.createBindGroupLayout({
            entries: [
                {
                    binding: 0,
                    visibility: GPUShaderStage.FRAGMENT,
                    sampler: { type: 'filtering' }
                },
                {
                    binding: 1,
                    visibility: GPUShaderStage.FRAGMENT,
                    texture: { sampleType: 'float' }
                },
                {
                    binding: 2,
                    visibility: GPUShaderStage.FRAGMENT,
                    buffer: { type: 'read-only-storage' }
                },
                {
                    binding: 3,
                    visibility: GPUShaderStage.FRAGMENT,
                    buffer: { type: 'uniform' }
                }
            ]
        });

        const pipelineLayout = this.device.createPipelineLayout({
            bindGroupLayouts: [bindGroupLayout]
        });

        // Create render pipeline
        this.pipeline = this.device.createRenderPipeline({
            layout: pipelineLayout,
            vertex: {
                module: vertexModule,
                entryPoint: 'main',
                buffers: [{
                    arrayStride: 8, // 2 floats * 4 bytes
                    attributes: [{
                        shaderLocation: 0,
                        offset: 0,
                        format: 'float32x2'
                    }]
                }]
            },
            fragment: {
                module: fragmentModule,
                entryPoint: 'main',
                targets: [{
                    format: format,
                    blend: {
                        color: {
                            srcFactor: 'one',
                            dstFactor: 'one-minus-src-alpha',
                            operation: 'add'
                        },
                        alpha: {
                            srcFactor: 'one',
                            dstFactor: 'one-minus-src-alpha',
                            operation: 'add'
                        }
                    }
                }]
            },
            primitive: {
                topology: 'triangle-list'
            }
        });

        // Create sampler for screen texture
        this.sampler = this.device.createSampler({
            magFilter: 'nearest',
            minFilter: 'nearest',
            addressModeU: 'clamp-to-edge',
            addressModeV: 'clamp-to-edge'
        });

        // Store the bind group layout for later
        this.bindGroupLayout = bindGroupLayout;
        
        // Note: bindGroup will be created in createScreenTexture() when we have the texture
    }

    createVertexBuffer() {
        // Full screen quad (two triangles)
        const vertices = new Float32Array([
            -1, -1,  // Bottom-left
             1, -1,  // Bottom-right
            -1,  1,  // Top-left
            -1,  1,  // Top-left
             1, -1,  // Bottom-right
             1,  1   // Top-right
        ]);

        this.vertexBuffer = this.device.createBuffer({
            size: vertices.byteLength,
            usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST
        });

        this.device.queue.writeBuffer(this.vertexBuffer, 0, vertices);
    }

    createScreenTexture(width, height) {
        // Destroy old texture if exists
        if (this.screenTexture) {
            this.screenTexture.destroy();
        }

        // Create new texture for screen buffer
        this.screenTexture = this.device.createTexture({
            size: { width, height },
            format: 'r8unorm', // Single channel for palette indices
            usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST
        });

        // Create bind group with the texture
        this.bindGroup = this.device.createBindGroup({
            layout: this.bindGroupLayout,
            entries: [
                { binding: 0, resource: this.sampler },
                { binding: 1, resource: this.screenTexture.createView() },
                { binding: 2, resource: { buffer: this.paletteBuffer } },
                { binding: 3, resource: { buffer: this.uniformBuffer } }
            ]
        });

        this.screenWidth = width;
        this.screenHeight = height;
    }

    updatePalette(palette) {
        if (!palette || palette.length === 0) return;

        // Convert palette to RGBA floats
        const paletteData = new Float32Array(256 * 4);
        for (let i = 0; i < palette.length && i < 256; i++) {
            const c = palette[i];
            paletteData[i * 4 + 0] = (c & 0xff) / 255.0;         // R
            paletteData[i * 4 + 1] = ((c >> 8) & 0xff) / 255.0;  // G
            paletteData[i * 4 + 2] = ((c >> 16) & 0xff) / 255.0; // B
            paletteData[i * 4 + 3] = 1.0;                        // A
        }

        this.device.queue.writeBuffer(this.paletteBuffer, 0, paletteData);
        this.paletteChanged = false;
    }

    draw(screenState) {
        if (!this.device) return;

        const { width, height, screen, palette, lastImage } = screenState;

        // Check if we need to resize OR if we haven't created texture/bindGroup yet
        if (width !== this.screenWidth || height !== this.screenHeight || !this.bindGroup) {
            this.createScreenTexture(width, height);
            // Update canvas size for proper scaling
            this.canvas.width = width * this.scaleFactor;
            this.canvas.height = height * this.scaleFactor;
        }
        
        // Safety check: must have bindGroup to render
        if (!this.bindGroup) {
            console.warn('WebGPU: No bindGroup available, skipping draw');
            return;
        }

        // Check if palette changed
        if (this.paletteDidChange(palette)) {
            this.updatePalette(palette);
            this.cachedPalette = palette.slice();
        }

        // Upload screen buffer to texture
        // screen is a Uint32Array but we need Uint8Array for r8unorm texture
        const screenData = new Uint8Array(screen.buffer);
        this.device.queue.writeTexture(
            { texture: this.screenTexture },
            screenData,
            { bytesPerRow: width },
            { width, height }
        );

        // Update uniform buffer
        const params = new Float32Array([
            this.canvas.width,
            this.canvas.height,
            palette.length,
            0 // padding
        ]);
        this.device.queue.writeBuffer(this.uniformBuffer, 0, params);

        // Render
        const commandEncoder = this.device.createCommandEncoder();
        const textureView = this.context.getCurrentTexture().createView();

        const renderPass = commandEncoder.beginRenderPass({
            colorAttachments: [{
                view: textureView,
                clearValue: { r: 0, g: 0, b: 0, a: 1 },
                loadOp: 'clear',
                storeOp: 'store'
            }]
        });

        renderPass.setPipeline(this.pipeline);
        renderPass.setBindGroup(0, this.bindGroup);
        renderPass.setVertexBuffer(0, this.vertexBuffer);
        renderPass.draw(6, 1, 0, 0);
        renderPass.end();

        this.device.queue.submit([commandEncoder.finish()]);

        // Update FPS
        this.frameCount++;
        const now = performance.now();
        if (now - this.lastTime >= 1000) {
            this.fps = Math.round((this.frameCount * 1000) / (now - this.lastTime));
            this.frameCount = 0;
            this.lastTime = now;
        }
    }

    paletteDidChange(palette) {
        if (!this.cachedPalette || this.cachedPalette.length !== palette.length) {
            return true;
        }
        for (let i = 0; i < this.cachedPalette.length; i++) {
            if (this.cachedPalette[i] !== palette[i]) {
                return true;
            }
        }
        return false;
    }

    setScaleFactor(scale) {
        this.scaleFactor = scale;
    }

    getFPS() {
        return this.fps;
    }

    destroy() {
        if (this.screenTexture) this.screenTexture.destroy();
        if (this.paletteBuffer) this.paletteBuffer.destroy();
        if (this.uniformBuffer) this.uniformBuffer.destroy();
        if (this.vertexBuffer) this.vertexBuffer.destroy();
        if (this.device) this.device.destroy();
    }
}

// Global instance
let webgpuRenderer = null;

/**
 * Initialize WebGPU renderer
 * Returns true if successful, false if WebGPU not available
 */
async function initWebGPURenderer(canvas, scaleFactor = 1) {
    try {
        webgpuRenderer = new MakeCodeWebGPURenderer(canvas);
        webgpuRenderer.setScaleFactor(scaleFactor);
        await webgpuRenderer.init();
        console.log('WebGPU renderer initialized successfully');
        return true;
    } catch (e) {
        console.warn('WebGPU initialization failed, falling back to Canvas 2D:', e);
        webgpuRenderer = null;
        return false;
    }
}

/**
 * Draw using WebGPU
 * Called from modified GamePlayer.draw()
 */
function drawWebGPU(screenState) {
    if (webgpuRenderer) {
        webgpuRenderer.draw(screenState);
    }
}

/**
 * Check if WebGPU is active
 */
function isWebGPUActive() {
    return webgpuRenderer !== null;
}

/**
 * Get WebGPU stats
 */
function getWebGPUStats() {
    if (!webgpuRenderer) return null;
    return {
        fps: webgpuRenderer.getFPS(),
        width: webgpuRenderer.screenWidth,
        height: webgpuRenderer.screenHeight
    };
}

// Export for use in other modules
if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
        MakeCodeWebGPURenderer,
        initWebGPURenderer,
        drawWebGPU,
        isWebGPUActive,
        getWebGPUStats
    };
}
