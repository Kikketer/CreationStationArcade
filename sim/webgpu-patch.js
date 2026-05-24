/**
 * WebGPU Patch for MakeCode Arcade Simulator
 * 
 * This script patches the existing simulator to use WebGPU instead of Canvas 2D.
 * Include this after sim.js and it will override the GamePlayer.draw() method.
 */

(function() {
    'use strict';

    let webgpuRenderer = null;
    let originalDraw = null;
    let isInitialized = false;

    /**
     * Initialize WebGPU and patch the GamePlayer
     */
    async function initWebGPU() {
        if (isInitialized) return true;
        
        const canvas = document.getElementById('game-screen');
        console.log('WebGPU init: canvas found =', !!canvas);
        
        if (!canvas) {
            console.warn('Game canvas not found');
            // Still patch even without canvas, for safety checks
            patchGamePlayer();
            isInitialized = true;
            return false;
        }
        
        // Check WebGPU support
        console.log('WebGPU init: navigator.gpu =', !!navigator.gpu);

        try {
            webgpuRenderer = new MakeCodeWebGPURenderer(canvas);
            await webgpuRenderer.init();
            
            // Patch the GamePlayer.draw method
            patchGamePlayer();
            
            isInitialized = true;
            console.log('WebGPU patch applied successfully');
            return true;
        } catch (e) {
            console.warn('WebGPU not available, using Canvas 2D:', e.message);
            webgpuRenderer = null;
            // Still patch for safety checks on original draw
            patchGamePlayer();
            isInitialized = true;
            return false;
        }
    }

    /**
     * Patch the GamePlayer class draw method
     */
    function patchGamePlayer() {
        // Find the GamePlayer class in the pxsim.visuals namespace
        if (typeof pxsim === 'undefined' || !pxsim.visuals || !pxsim.visuals.GamePlayer) {
            console.warn('GamePlayer not found in pxsim.visuals');
            return;
        }

        const GamePlayer = pxsim.visuals.GamePlayer;
        
        // Already patched?
        if (GamePlayer.prototype._webgpuPatched) {
            console.log('GamePlayer already patched, skipping');
            return;
        }
        
        // Hook into constructor to log when GamePlayer is created
        const OriginalConstructor = GamePlayer;
        pxsim.visuals.GamePlayer = function(scale) {
            console.log('GamePlayer constructed, scale =', scale);
            const instance = new OriginalConstructor(scale);
            console.log('GamePlayer screen =', !!instance.screen);
            return instance;
        };
        pxsim.visuals.GamePlayer.prototype = OriginalConstructor.prototype;
        
        // Store original draw method for fallback
        if (!originalDraw) {
            originalDraw = GamePlayer.prototype.draw;
            console.log('Stored original GamePlayer.draw method');
        }

        // Override draw method
        GamePlayer.prototype.draw = function(state) {
            if (this.isDisposed) return;
            
            // Safety check: ensure screen/canvas is available
            if (!this.screen) {
                console.warn('GamePlayer.draw: this.screen is null, skipping draw');
                return;
            }

            // If WebGPU isn't ready, fall back to original
            if (!webgpuRenderer || !webgpuRenderer.device) {
                try {
                    return originalDraw.call(this, state);
                } catch (e) {
                    console.error('Original draw failed:', e);
                    return;
                }
            }

            // Use WebGPU for rendering
            try {
                // Update scale factor if needed
                if (this.scaleFactor !== webgpuRenderer.scaleFactor) {
                    webgpuRenderer.setScaleFactor(this.scaleFactor);
                }

                // Handle scale factor changes for canvas size
                const targetWidth = state.width * this.scaleFactor;
                const targetHeight = state.height * this.scaleFactor;
                
                if (this.screen.width !== targetWidth || this.screen.height !== targetHeight) {
                    this.screen.width = targetWidth;
                    this.screen.height = targetHeight;
                    this.screen.className = '';
                }

                // Render via WebGPU
                webgpuRenderer.draw(state);
                
                // Show debug stats if enabled
                if (state.stats && this.stats) {
                    const webgpuStats = getWebGPUStats();
                    if (webgpuStats) {
                        this.stats.textContent = `${state.stats} | GPU ${webgpuStats.fps}fps`;
                    } else {
                        this.stats.textContent = state.stats;
                    }
                }
            } catch (e) {
                console.error('WebGPU draw failed, falling back to Canvas 2D:', e);
                return originalDraw.call(this, state);
            }
        };

        // Mark as patched
        GamePlayer.prototype._webgpuPatched = true;
        
        console.log('GamePlayer.draw patched for WebGPU');
    }

    // Auto-initialize when DOM is ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initWebGPU);
    } else {
        // DOM already loaded, try init
        initWebGPU();
    }

    // Also try patching when pxsim is ready (it loads asynchronously)
    const checkAndPatch = setInterval(() => {
        if (typeof pxsim !== 'undefined' && pxsim.visuals && pxsim.visuals.GamePlayer) {
            clearInterval(checkAndPatch);
            if (!isInitialized) {
                initWebGPU();
            }
        }
    }, 100);

    // Stop checking after 10 seconds
    setTimeout(() => clearInterval(checkAndPatch), 10000);

    // Export for manual control
    window.WebGPUPatch = {
        init: initWebGPU,
        isActive: () => webgpuRenderer !== null && webgpuRenderer.device !== null,
        getStats: () => webgpuRenderer ? {
            fps: webgpuRenderer.getFPS(),
            width: webgpuRenderer.screenWidth,
            height: webgpuRenderer.screenHeight
        } : null,
        disable: () => {
            if (originalDraw && pxsim.visuals && pxsim.visuals.GamePlayer) {
                pxsim.visuals.GamePlayer.prototype.draw = originalDraw;
                console.log('WebGPU patch removed, restored Canvas 2D');
            }
        }
    };
})();
