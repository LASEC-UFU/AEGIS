# AEGIS — Correções e melhorias implementadas

Referência: itens de [01_AUDITORIA.md](01_AUDITORIA.md). Todas as alterações
estão na árvore de trabalho (sem commit). Verificação: `cpp/build/core_tests`
(91 verificações), `cpp/build/api_tests` (66), `flutter test` (28 testes),
`dart analyze lib test tool` (sem problemas).

## P0

| Item | Correção | Arquivos | Teste |
|---|---|---|---|
| P0-1 lote inoperante | `aegis_batch` reescrito: códigos de retorno corretos, chaves camelCase, modo síncrono com semente explícita, execuções paralelas (`--jobs`), arquivo de teste separado (`--data-test`), `--set chave=valor`, registro completo por execução (relatório final + histórico) | `cpp/src/aegis_batch.cpp` | api_tests (determinismo), verificação cruzada batch × runner Dart (modelo idêntico) |
| P0-2 estabilidade invertida | Novos diagnósticos: singularidade do denominador ao longo dos dados, divergência da simulação livre, raio espectral da parte AR linear (Durand–Kerner, orientação correta). Penalidade = singularidade + divergência | `stability_analyzer.*`, `metrics.hpp`, `individual_evaluator.cpp` | core_tests `[stability]` |
| P0-3 clamp da normalização | Transformação afim sem corte, no C++ e no motor Dart; coluna constante centrada. O teste Dart existente afirmava o corte e foi corrigido | `normalizer.*`, `data_normalizer.dart`, `test/data_normalizer_test.dart` | core_tests `[normalizer]`, data_normalizer_test |
| P0-4 divergência mascarada | `RationalModel::simulate` detecta não-finito ou \|ŷ\| > 10·max\|y_treino\|, satura e marca a divergência | `rational_model.*` | core_tests `[stability]` |
| P0-5 ACF = ERR | ACF real dos resíduos (validação), banda 1,96/√N, veredito de brancura, CCF resíduo–entrada; ERR em campo próprio; mapeamento Dart corrigido | `individual_evaluator.cpp` (`diagnose`), `de_optimizer.cpp`, `snapshot_parser.dart` | snapshot_parser_test |
| P0-6 base de potência | `powerMode` explícito (`hybrid` padrão, `signed`, `legacy`), `exponentStep` (0,5); modo exportado com o modelo; motor Dart alinhado (`power_basis.dart`) | `safe_power.hpp`, `regressor_library.*`, `power_basis.dart`, `regressor_builder.dart` | core_tests `[power basis]`, `[polynomial recovery]`, engine_consistency_test |
| P0-7 teste exposto durante a execução | Métricas de teste só no relatório final; `rmseTest = null` no status/snapshot | `identification_pipeline.cpp` | api_tests `[sync run]`, snapshot_parser_test |
| P0-8 só one-step normalizado | Métricas por partição: one-step e simulação livre, normalizadas e em unidades originais, FIT %, divergência, janela de inicialização | `model_io.*` (`evaluate_segment`) | api_tests, verificação Dart |

## P1

| Item | Correção | Arquivos |
|---|---|---|
| P1-1 crossover só cresce | Comprimento do mutante pela regra do DE; crossover posicional independente (encolhe/cresce); mutação estrutural; forma canônica | `de_optimizer.cpp`, `regressor_library.cpp` |
| P1-2 seleção em fração da validação | Avaliador canônico com validação completa; "hall of fame" do campeão sob os pesos correntes | `de_optimizer.cpp` |
| P1-3 CR reseta μF | Ajuste de um parâmetro preserva o outro | `de_optimizer.cpp` (teste em core_tests) |
| P1-4 fases sobrescrevem o agente | Ações sobre pesos alteram a base usada pelas fases; γ do agente sobrepõe o anelamento; valor efetivo registrado | `identification_pipeline.cpp` |
| P1-5 snapshot falso | Estatísticas reais por ilha e globais; parâmetros correntes e pesos efetivos | `de_optimizer.*`, `identification_pipeline.cpp`, `snapshot_parser.dart` |
| P1-6 diagnósticos não executados | Estabilidade, resíduos, sobre/subajuste a cada geração no campeão; poda e refino no campeão final, aceitos só se o fitness canônico não piorar | `individual_evaluator.cpp`, `automatic_pruner.*`, `identification_pipeline.cpp` |
| P1-7 WebSocket | Envio com timeout (cliente lento é desconectado), threads com join, mesma interface de ações, log único | `agent_controller.*` (teste com cliente que desconecta e cliente travado) |
| P1-8 interface de ações | `aegis_apply_action` tipada: faixa, passo máximo, cooldown, trava de orçamento, kill switch, códigos de rejeição, valor anterior/novo/efetivo, desfecho após H gerações, JSON escapado | `identification_pipeline.*`, `aegis_api.*`, `json_lite.hpp` |
| P1-9 UCB1 | Cooldown também para sinais severos; braços (parâmetro, direção); recompensa com baseline de deriva no RMSE de validação; observações com mudança de fase descartadas; rejeições não contam | `local_adaptive_agent.dart` |
| P1-10 LLM | Núcleo comum (nativo/web), saída com JSON Schema, timeout, orçamentos de chamadas e custo, recusa e fallback, validação local, memória das respostas do motor, registro de decisões | `llm_agent_core.dart`, `llm_agent_native.dart`, `llm_agent_web.dart` |
| P1-11 desempenho | Ψ uma vez por partição, potências inteiras por multiplicação | `regressor_library.cpp`, `individual_evaluator.cpp` (≈ 15× por avaliação) |
| P1-12 QR | Colunas dependentes não consomem linha de R | `regressor_library.cpp` (core_tests `[qr]`) |
| P1-13 horizonte de simulação | `freeRunHorizon = 0` = validação inteira; `errorMode = simulation` | `individual_evaluator.cpp`, `identification_pipeline.cpp` |
| P1-14 motor Dart | Base de potência e intercepto alinhados ao C++ (teste de consistência); continua sem modelos racionais e sem currículo (documentado) | `least_squares.dart`, `bic_fitness.dart`, `model_validator.dart` |

## Achados durante os experimentos (iterações registradas em `experiments/EXPERIMENT_LOG.md`)

| Achado | Tratamento |
|---|---|
| Penalidade de contribuição de entrada com ERR invariante à ordem empurrava a busca para longe de y(k−1) | Indicador redefinido (parte AR primeiro) |
| Candidatos com atrasos diferentes eram pontuados em janelas diferentes | Linha de pontuação comum (`maxDelay`) |
| Objetivo one-step domina o termo de simulação | Opção `errorMode = simulation`, avaliada como condição |

## Novos componentes

- Política fuzzy Takagi–Sugeno (`fuzzy_policy_agent.dart`), base em JSON, recusa por evidência insuficiente.
- Aprendizado offline da base fuzzy a partir de trajetórias (`tool/experiments/learn_fuzzy_policy.dart`).
- Executor headless em lockstep com agentes (`tool/experiments/run_agent_experiment.dart`).
- Baseline FROLS (`cpp/tools/frols_baseline.cpp`) e reavaliação de modelos (`cpp/tools/evaluate_models.cpp`).
- Executor do código original (`experiments/tools/legacy_head_runner.cpp`) com binários preservados.
- Preparação de benchmarks com SHA-256 e leitor MAT v5 (`tool/benchmarks/`).
- Análise estatística e figuras SVG (`tool/experiments/analyze.dart`).

## Pendências conhecidas

- O motor Dart (fallback web) não estima modelos racionais nem implementa o currículo.
- `aegis_wasm_loader.js` não expõe as funções novas (ações tipadas, relatório final); a versão web usa a entrada legada `aegis_apply_tuning`, que passa pela mesma validação. Requer rebuild WASM na CI (Emscripten indisponível nesta máquina).
- O app Flutter Windows não foi compilado aqui (sem MSVC); a CI compila apenas a DLL com MSVC — os testes C++ novos foram verificados só com MinGW.
- A tela do agente já exibe decisões, origem e desfecho das ações; o esquema de ações permanece documentado em `docs/AGENT_INTERFACE.md`.
