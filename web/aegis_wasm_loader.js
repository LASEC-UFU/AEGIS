// AEGIS WebAssembly loader — exposes window.AegisWasm bridge for Dart interop.
// Loaded by index.html before flutter_bootstrap.js.

(function () {
  'use strict';

  // Resolve the WASM file next to this script (respects --base-href).
  const scriptSrc = document.currentScript
    ? document.currentScript.src
    : '';
  const baseDir = scriptSrc.substring(0, scriptSrc.lastIndexOf('/') + 1);

  async function loadAegisWasm() {
    let Module;
    try {
      // createAegisModule is the Emscripten factory function from aegis_wasm.js
      Module = await createAegisModule({
        locateFile: function (path) {
          return baseDir + path;
        },
      });
    } catch (err) {
      console.warn('[AEGIS] WASM load failed:', err);
      window.AegisWasm = { isReady: function () { return false; } };
      window.dispatchEvent(new Event('AegisWasmReady'));
      return;
    }

    // ── localStorage helpers ───────────────────────────────────────────────
    window.aegisGetLocalStorage = function (key) {
      try { return localStorage.getItem(key) || ''; } catch (_) { return ''; }
    };
    window.aegisSetLocalStorage = function (key, value) {
      try { localStorage.setItem(key, value); } catch (_) {}
    };

    // ── Bridge object ──────────────────────────────────────────────────────
    window.AegisWasm = {

      isReady: function () { return true; },

      // Pipeline lifecycle
      createPipeline: function () {
        return Module._aegis_create_pipeline();
      },
      destroyPipeline: function (p) {
        Module._aegis_destroy_pipeline(p);
      },

      // Load data from a JS Float64Array (row-major, rows × cols)
      loadData: function (p, jsFloat64Array, rows, cols) {
        var byteLen = jsFloat64Array.byteLength;
        var ptr = Module._malloc(byteLen);
        Module.HEAPF64.set(jsFloat64Array, ptr >>> 3);
        var rc = Module._aegis_load_data(p, ptr, rows, cols);
        Module._free(ptr);
        return rc;
      },

      // Configure from JSON string
      configure: function (p, jsonStr) {
        var len  = Module.lengthBytesUTF8(jsonStr) + 1;
        var ptr  = Module._malloc(len);
        Module.stringToUTF8(jsonStr, ptr, len);
        var rc   = Module._aegis_configure(p, ptr);
        Module._free(ptr);
        return rc;
      },

      start:  function (p) { return Module._aegis_start(p);  },
      pause:  function (p) { return Module._aegis_pause(p);  },
      resume: function (p) { return Module._aegis_resume(p); },
      stop:   function (p) { return Module._aegis_stop(p);   },

      // Drive n synchronous generations; returns count actually run
      step: function (p, n) { return Module._aegis_step(p, n); },

      // Query helpers — handle malloc / free internally, return JS strings
      getStatus: function (p) {
        var ptr = Module._aegis_get_status(p);
        if (!ptr) return '';
        var s = Module.UTF8ToString(ptr);
        Module._aegis_free_string(ptr);
        return s;
      },
      getSnapshot: function (p) {
        var ptr = Module._aegis_get_snapshot(p);
        if (!ptr) return '';
        var s = Module.UTF8ToString(ptr);
        Module._aegis_free_string(ptr);
        return s;
      },
      getBestModel: function (p) {
        var ptr = Module._aegis_get_best_model(p);
        if (!ptr) return '';
        var s = Module.UTF8ToString(ptr);
        Module._aegis_free_string(ptr);
        return s;
      },

      // Apply agent tuning
      applyTuning: function (p, paramName, value, reason) {
        var pLen = Module.lengthBytesUTF8(paramName) + 1;
        var rLen = Module.lengthBytesUTF8(reason)    + 1;
        var pPtr = Module._malloc(pLen);
        var rPtr = Module._malloc(rLen);
        Module.stringToUTF8(paramName, pPtr, pLen);
        Module.stringToUTF8(reason,    rPtr, rLen);
        var rc = Module._aegis_apply_tuning(p, pPtr, value, rPtr);
        Module._free(pPtr);
        Module._free(rPtr);
        return rc;
      },
    };

    window.dispatchEvent(new Event('AegisWasmReady'));
    console.log('[AEGIS] WASM ready:', Module.UTF8ToString(Module._aegis_version()));
  }

  // Start loading immediately; Flutter waits on AegisWasmReady event
  loadAegisWasm();
})();
