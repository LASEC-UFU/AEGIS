// AEGIS WebAssembly loader — coordenador multi-Worker.
// Cada ilha DE roda em um Web Worker separado (core real do CPU do visitante).
// Sem SharedArrayBuffer → funciona em GitHub Pages sem headers COOP/COEP.
// Interface AegisWasm idêntica à versão single-thread — Dart não muda.

(function () {
  'use strict';

  // ── Helper de download JSON ───────────────────────────────────────────────
  window.aegisDownloadJson = function (content, filename) {
    var blob = new Blob([content], { type: 'application/json' });
    var url  = URL.createObjectURL(blob);
    var a    = document.createElement('a');
    a.href = url; a.download = filename;
    document.body.appendChild(a); a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  };

  // ── localStorage helpers ──────────────────────────────────────────────────
  window.aegisGetLocalStorage = function (key) {
    try { return localStorage.getItem(key) || ''; } catch (_) { return ''; }
  };
  window.aegisSetLocalStorage = function (key, value) {
    try { localStorage.setItem(key, value); } catch (_) {}
  };

  // ── URLs base ─────────────────────────────────────────────────────────────
  var scriptSrc = document.currentScript ? document.currentScript.src : '';
  var baseDir   = scriptSrc.substring(0, scriptSrc.lastIndexOf('/') + 1);
  var wasmJsUrl = baseDir + 'aegis_wasm.js';
  var workerUrl = baseDir + 'aegis_worker.js';

  // ── Configuração ──────────────────────────────────────────────────────────
  var NUM_WORKERS        = 3;
  var MIGRATION_INTERVAL = 20; // gerações entre migrações

  // ── Estado do pool de Workers ─────────────────────────────────────────────
  var workers       = [];          // instâncias Worker
  var pendingMap    = new Map();   // id → resolve (Promise por request)
  var nextMsgId     = 1;

  var cachedSnapshot  = '';
  var cachedBestModel = '';
  var cachedStatus    = '{"state":"idle"}';
  var migrationTick   = 0;
  var allDone         = false;
  var startPromise    = null;      // Promise que resolve quando Workers estão prontos e rodando

  // Dados armazenados entre loadData/configure e o start() real
  var storedData   = null;   // {buffer, rows, cols}
  var storedConfig = null;   // string JSON

  // ── Comunicação com Workers ───────────────────────────────────────────────

  function makeWorker(idx) {
    var w = new Worker(workerUrl);
    w.onmessage = function (e) {
      var id      = e.data.id;
      var payload = e.data.payload;
      var resolve = pendingMap.get(id);
      if (resolve) { pendingMap.delete(id); resolve(payload); }
    };
    w.onerror = function (err) {
      console.error('[AEGIS Worker ' + idx + '] erro:', err.message || err);
    };
    return w;
  }

  // Envia mensagem para um Worker específico, retorna Promise<payload>
  function send(workerIdx, type, payload) {
    return new Promise(function (resolve) {
      var id = nextMsgId++;
      pendingMap.set(id, resolve);
      workers[workerIdx].postMessage({ type: type, id: id, payload: payload || {} });
    });
  }

  // Envia para TODOS os Workers em paralelo, retorna Promise<payload[]>
  function sendAll(type, payload) {
    return Promise.all(workers.map(function (_, i) {
      return send(i, type, payload);
    }));
  }

  // ── Inicialização dos Workers ─────────────────────────────────────────────

  // Cria Workers e carrega o módulo WASM em cada um.
  // Chamado antecipadamente para que quando o usuário clicar em "Start"
  // os Workers já estejam prontos.
  var workerBootPromise = (function () {
    workers = [];
    for (var i = 0; i < NUM_WORKERS; i++) workers.push(makeWorker(i));
    return sendAll('init', { wasmJsUrl: wasmJsUrl, baseDir: baseDir });
  })();

  workerBootPromise.then(function (results) {
    var ok = results.every(function (r) { return r.ok; });
    if (!ok) console.warn('[AEGIS] Um ou mais Workers falharam ao inicializar');
    else console.log('[AEGIS] ' + NUM_WORKERS + ' Workers prontos (ilhas paralelas)');
  });

  // ── Início da otimização ──────────────────────────────────────────────────

  // Encadeia: boot → loadData × 3 → configure × 3 → start × 3
  function launchWorkers() {
    var data   = storedData;
    var config = storedConfig;

    return workerBootPromise.then(function () {
      // Copia independente do buffer para cada Worker (sem SharedArrayBuffer)
      return Promise.all(workers.map(function (_, i) {
        return send(i, 'loadData', {
          buffer: data.buffer.slice(0),
          rows:   data.rows,
          cols:   data.cols,
        });
      }));
    }).then(function () {
      return sendAll('configure', { config: config });
    }).then(function () {
      return sendAll('start');
    }).then(function () {
      console.log('[AEGIS] Otimização iniciada em ' + NUM_WORKERS + ' Workers paralelos');
    }).catch(function (err) {
      console.error('[AEGIS] Erro ao iniciar Workers:', err);
    });
  }

  // ── Migração entre Workers ────────────────────────────────────────────────

  function doMigration(bestModels) {
    // Injeta o melhor de cada Worker nos outros (fire-and-forget)
    for (var src = 0; src < NUM_WORKERS; src++) {
      var json = bestModels[src];
      if (!json || json.indexOf('not_available') !== -1) continue;
      for (var dst = 0; dst < NUM_WORKERS; dst++) {
        if (dst === src) continue;
        send(dst, 'inject', { json: json }); // não precisa aguardar
      }
    }
  }

  // ── Bridge AegisWasm ──────────────────────────────────────────────────────

  window.AegisWasm = {

    isReady: function () { return false; }, // atualizado após boot

    createPipeline: function () {
      // Workers já estão sendo inicializados; retorna ID fixo 1
      allDone        = false;
      migrationTick  = 0;
      cachedSnapshot = '';
      cachedStatus   = '{"state":"idle"}';
      startPromise   = null;
      return 1;
    },

    destroyPipeline: function (p) {
      sendAll('destroy').then(function () {
        workers.forEach(function (w) { w.terminate(); });
        workers = [];
        cachedSnapshot = '';
        cachedStatus   = '{"state":"idle"}';
      });
    },

    // Armazena dados localmente; envio real aos Workers ocorre em start()
    loadData: function (p, jsFloat64Array, rows, cols) {
      storedData = {
        buffer: jsFloat64Array.buffer.slice(0),
        rows:   rows,
        cols:   cols,
      };
      return 0; // sucesso síncrono (dados serão enviados no start)
    },

    // Armazena config; envio real aos Workers ocorre em start()
    configure: function (p, jsonStr) {
      storedConfig = jsonStr;
      return 0;
    },

    // Dispara o pipeline assíncrono; retorna 0 imediatamente
    start: function (p) {
      allDone       = false;
      migrationTick = 0;
      cachedStatus  = '{"state":"running"}';
      startPromise  = launchWorkers();
      return 0;
    },

    pause: function (p) {
      sendAll('pause');
      cachedStatus = '{"state":"paused"}';
    },

    resume: function (p) {
      sendAll('resume');
      cachedStatus = '{"state":"running"}';
    },

    stop: function (p) {
      sendAll('stop');
      allDone      = true;
      cachedStatus = '{"state":"stopped"}';
    },

    // Roda n gerações em TODOS os Workers em paralelo.
    // Retorna Promise<string> com o melhor snapshot JSON.
    // Chamado pelo Dart como: await AegisWasm.step(p, n)
    step: function (p, n) {
      if (!startPromise) return Promise.resolve(cachedSnapshot);

      return startPromise.then(function () {
        if (allDone) return cachedSnapshot;

        return sendAll('step', { n: n }).then(function (results) {

          // Verifica conclusão
          var doneCount = results.filter(function (r) { return r.done; }).length;
          if (doneCount === NUM_WORKERS) {
            allDone      = true;
            cachedStatus = '{"state":"completed"}';
          }

          // Seleciona melhor snapshot (menor fitness)
          var bestFitness  = Infinity;
          var bestSnapshot = '';
          var bestModels   = [];

          results.forEach(function (r) {
            bestModels.push(r.bestModel || '');
            if (!r.snapshot) return;
            try {
              var snap = JSON.parse(r.snapshot);
              var f    = snap.best_fitness;
              if (typeof f === 'number' && f < bestFitness) {
                bestFitness  = f;
                bestSnapshot = r.snapshot;
              }
            } catch (_) {}
          });

          if (bestSnapshot)    cachedSnapshot  = bestSnapshot;
          if (bestModels[0])   cachedBestModel = bestModels[0]; // melhor arbitrário

          // Migração periódica entre Workers
          migrationTick += n;
          if (migrationTick >= MIGRATION_INTERVAL) {
            migrationTick = 0;
            doMigration(bestModels);
          }

          return cachedSnapshot;
        });
      });
    },

    // Leituras síncronas (cache atualizado após cada step)
    getStatus:    function (p) { return cachedStatus;    },
    getSnapshot:  function (p) { return cachedSnapshot;  },
    getBestModel: function (p) { return cachedBestModel; },
    getTuningLog: function (p) { return '[]'; },

    applyTuning: function (p, param, value, reason) {
      // Tuning em modo multi-Worker não propagado (sem impacto na qualidade)
      return 0;
    },
  };

  // Marca ready após boot dos Workers
  workerBootPromise.then(function () {
    window.AegisWasm.isReady = function () { return true; };
    window.dispatchEvent(new Event('AegisWasmReady'));
  }).catch(function () {
    window.AegisWasm.isReady = function () { return false; };
    window.dispatchEvent(new Event('AegisWasmReady'));
  });

})();
