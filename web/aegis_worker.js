// AEGIS Web Worker — carrega uma instância WASM independente (uma ilha por Worker).
// Spawned pelo coordenador em aegis_wasm_loader.js via new Worker(url).
// Comunicação via postMessage: {type, id, payload} nos dois sentidos.

/* global createAegisModule */
'use strict';

var Module = null;
var pipeline = 0;

// ── Helpers de string UTF-8 ───────────────────────────────────────────────────

function getString(ptrFn) {
  var ptr = ptrFn();
  if (!ptr) return '';
  var s = Module.UTF8ToString(ptr);
  Module._aegis_free_string(ptr);
  return s;
}

function allocString(s) {
  var len = Module.lengthBytesUTF8(s) + 1;
  var ptr = Module._malloc(len);
  Module.stringToUTF8(s, ptr, len);
  return ptr;
}

function freePtr(ptr) {
  Module._free(ptr);
}

// ── Resposta ao coordenador ───────────────────────────────────────────────────

function reply(id, payload) {
  self.postMessage({ id: id, payload: payload || {} });
}

// ── Handler de mensagens ──────────────────────────────────────────────────────

self.onmessage = function (e) {
  var msg = e.data;
  var type = msg.type;
  var id = msg.id;
  var payload = msg.payload || {};

  if (type === 'init') {
    // Carrega aegis_wasm.js e inicializa o módulo Emscripten
    self.importScripts(payload.wasmJsUrl);
    createAegisModule({
      locateFile: function (p) { return payload.baseDir + p; },
    }).then(function (mod) {
      Module = mod;
      reply(id, { ok: true });
    }).catch(function (err) {
      reply(id, { ok: false, error: String(err) });
    });
    return;
  }

  // Todas as demais mensagens precisam do Module carregado
  if (!Module) { reply(id, { rc: -1, error: 'module not ready' }); return; }

  switch (type) {

    case 'loadData': {
      // Cria pipeline e carrega dados
      if (pipeline) { Module._aegis_destroy_pipeline(pipeline); }
      pipeline = Module._aegis_create_pipeline();
      if (!pipeline) { reply(id, { rc: -1 }); break; }

      var flat = new Float64Array(payload.buffer);
      var byteLen = flat.byteLength;
      var ptr = Module._malloc(byteLen);
      Module.HEAPF64.set(flat, ptr >>> 3);
      var rc = Module._aegis_load_data(pipeline, ptr, payload.rows, payload.cols);
      Module._free(ptr);
      reply(id, { rc: rc });
      break;
    }

    case 'configure': {
      // Força numIslands=1 e desabilita WebSocket
      var cfg;
      try { cfg = JSON.parse(payload.config); } catch (_) { cfg = {}; }
      cfg.numIslands = 1;
      cfg.webSocketPort = 0;
      var cfgStr = JSON.stringify(cfg);
      var cfgPtr = allocString(cfgStr);
      var rc2 = Module._aegis_configure(pipeline, cfgPtr);
      freePtr(cfgPtr);
      reply(id, { rc: rc2 });
      break;
    }

    case 'start': {
      var rc3 = Module._aegis_start(pipeline);
      reply(id, { rc: rc3 });
      break;
    }

    case 'step': {
      var ran = Module._aegis_step(pipeline, payload.n);
      var snapshot  = getString(function () { return Module._aegis_get_snapshot(pipeline); });
      var bestModel = getString(function () { return Module._aegis_get_best_model(pipeline); });
      reply(id, { ran: ran, snapshot: snapshot, bestModel: bestModel, done: ran === 0 });
      break;
    }

    case 'inject': {
      // Injeta um cromossomo (best_model_json de outro Worker) como migrante
      var injPtr = allocString(payload.json);
      Module._aegis_inject_individual(pipeline, injPtr);
      freePtr(injPtr);
      reply(id, { ok: true });
      break;
    }

    case 'pause': {
      Module._aegis_pause(pipeline);
      reply(id, { ok: true });
      break;
    }

    case 'resume': {
      Module._aegis_resume(pipeline);
      reply(id, { ok: true });
      break;
    }

    case 'stop': {
      Module._aegis_stop(pipeline);
      reply(id, { ok: true });
      break;
    }

    case 'destroy': {
      if (pipeline) { Module._aegis_destroy_pipeline(pipeline); pipeline = 0; }
      reply(id, { ok: true });
      break;
    }

    default:
      reply(id, { error: 'unknown message type: ' + type });
  }
};
