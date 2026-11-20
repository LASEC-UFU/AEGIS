# AEGIS — Auditoria técnica e científica (Fase 1)

Escopo: código no commit `9e4b1d8` (árvore limpa). Todas as afirmações abaixo foram
verificadas no código-fonte e, quando indicado, em execução. A documentação (README,
`assets/*.md`) foi comparada com o comportamento real.

Prioridades:

- **P0** — invalida resultados numéricos ou científicos, ou impede a execução reprodutível.
- **P1** — distorce a busca, os diagnósticos ou a interação com agentes.
- **P2** — inconsistência de documentação, robustez ou qualidade sem impacto direto nos números.

Cada item traz: problema · evidência · impacto · correção · teste de verificação.

---

## P0 — Problemas que invalidam resultados

### P0-1. Runner em lote `aegis_batch` nunca executa uma identificação
- **Evidência.** `cpp/src/aegis_batch.cpp:273` testa `if (!aegis_load_data(...))`, mas a API retorna
  `0` em caso de sucesso (`aegis_api.h`), então o sucesso é tratado como erro. O mesmo vale para
  `aegis_configure` e `aegis_start`. Em execução: `0/2 runs OK`.
  As chaves enviadas são `random_seed`, `max_generations`, `num_islands`, `population_size`,
  `output_col` (linhas 285–297), mas o parser aceita apenas camelCase (`randomSeed`,
  `maxGenerations`…): **a semente nunca era aplicada**. A leitura de resultados usa
  `best_fitness`, `r2_train`, `num_terms` (linhas 332, 395, 431), que não existem no JSON
  (`bestFitness`, `r2Train`, `numRegressors`).
- **Impacto.** Nenhum resultado multi-semente pode ter sido produzido por esta ferramenta; os
  scripts `python/analyze_batch.py` dependem dela. Reprodutibilidade inexistente.
- **Correção.** Verificar `rc != 0`; usar as chaves corretas; desligar o WebSocket em lote;
  registrar configuração efetiva, semente, hash dos dados, versão e métricas completas.
- **Teste.** Execução em lote com 2 sementes iguais deve gerar modelos idênticos; sementes
  diferentes, modelos diferentes; JSON de saída validado.

### P0-2. Análise de "estabilidade" invertida e conceitualmente incorreta
- **Evidência.** `cpp/src/stability_analyzer.cpp`: o "polinômio do denominador" é montado como
  `1 + Σ θ_d z^{d}` somando coeficientes por atraso, ignorando variável, expoente e produtos.
  As raízes desse polinômio são os **recíprocos** das raízes características; para
  `D = 1 + θ·y(k−1)` o código calcula a raiz `−1/θ` (linha 30) e marca o modelo como
  instável quando |θ| < 1, com penalidade `(1/|θ| − 1)·10` (linha 127). Para grau ≥ 3 usa
  iteração de potência e preenche as demais raízes com zero (linha 76).
- **Impacto.** A penalidade `η·P_S` (η = 1, ou 1,6 na ilha "Stability") pune
  sistematicamente modelos racionais com denominador **bem-condicionado** (|θ| pequeno) e
  favorece denominadores próximos de singularidade. O indicador `is_stable` exibido não
  significa estabilidade BIBO. Qualquer conclusão sobre modelos racionais está comprometida.
- **Correção.** Substituir por diagnósticos com significado: (a) margem de singularidade do
  denominador `min_k |D(k)|` e troca de sinal ao longo dos dados; (b) limitação da simulação
  livre (divergência / saída não finita / fora de um envelope da faixa observada);
  (c) raio espectral da parte linear autoregressiva, calculado corretamente (polinômio
  característico na orientação correta, raízes por método completo). A penalidade usa (a)+(b);
  (c) é diagnóstico.
- **Teste.** `D = 1 + 0,5·y(k−1)` deve ser bem-condicionado (penalidade 0);
  denominador que cruza zero nos dados deve ser penalizado; AR `y(k)=1,5y(k−1)` deve ter raio
  espectral 1,5; `y(k)=0,5y(k−1)`, 0,5.

### P0-3. Normalização min-max corta (clamp) validação e teste
- **Evidência.** `cpp/include/aegis/normalizer.hpp:27` retorna `max(lo, min(hi, v))`;
  `lib/engine/identification/data_normalizer.dart:61` faz `.clamp(lowerBound, upperBound)`.
  O ajuste usa apenas o trecho de treino, mas a transformação é aplicada a todo o conjunto.
- **Impacto.** Qualquer amostra de validação/teste fora da faixa do treino é **alterada**
  (entradas e saídas). As métricas de teste deixam de corresponder aos dados reais; em
  benchmarks de extrapolação (p.ex. Silverbox) o efeito é severo.
- **Correção.** Transformação afim sem corte; inversão exata; exportar os parâmetros.
- **Teste.** Valor fora da faixa deve ser transformado linearmente e invertido exatamente.

### P0-4. Simulação livre mascara divergência
- **Evidência.** `cpp/src/rational_model.cpp:141`: `if (!std::isfinite(yp)) yp = 0.0;`.
- **Impacto.** Um modelo que diverge para ±∞ passa a "prever 0", produzindo RMSE de simulação
  moderado e enganoso; a penalidade de free-run e o diagnóstico de estabilidade ficam errados.
- **Correção.** Detectar divergência (não finito ou |ŷ| acima de um envelope da faixa
  observada), marcar `diverged`, saturar no envelope e reportar o instante de divergência.
- **Teste.** Modelo `y(k)=1,5·y(k−1)+u(k−1)` deve ser marcado divergente.

### P0-5. Campo `residual_autocorr` contém valores de ERR
- **Evidência.** `cpp/src/de_optimizer.cpp:649`: `r.residual_autocorr = best.err; // reuse slot`.
  No Dart (`aegis_ffi_service_native.dart:310`) esse campo vira `residualAutocorrelation`, que a
  tela de Resultados plota como autocorrelação dos resíduos com bandas de confiança.
- **Impacto.** O teste de brancura exibido ao usuário não é um teste de resíduos.
- **Correção.** Calcular a autocorrelação real dos resíduos (one-step, validação) e a correlação
  cruzada resíduo–entrada; transmitir ERR em campo próprio.
- **Teste.** Resíduo branco sintético → ACF dentro de ±1,96/√N; campo `err` separado.

### P0-6. Semântica das potências diverge do modelo documentado
- **Evidência.** `cpp/include/aegis/safe_power.hpp:27`: `signed_power = sign(x)·(|x|+ε)^p`,
  usado em todo regressor (`regressor_library.cpp`). Assim, `u(k−1)²` no código é `u·|u|`
  (função ímpar), e há um viés `ε = 10⁻⁶`. O README descreve `∏ x^α` (polinômio). Além disso,
  `quantize_exponent` é chamado com passo 0 (`de_optimizer.cpp:107,223`): expoentes são
  contínuos, ao contrário do README ("passos de 0,5"). O motor Dart usa `pow(x, p)` real
  (NaN → 0 para base negativa com expoente fracionário).
- **Impacto.** A classe de modelos efetivamente identificada não é NARX polinomial; não-
  linearidades pares (x²) não são representáveis; os modelos exportados não podem ser
  reproduzidos por terceiros a partir da equação publicada. C++ e Dart são incompatíveis.
- **Correção.** Tornar a base explícita e documentada (`powerMode`): `hybrid` (padrão novo:
  expoente inteiro → potência exata; não inteiro → `sign(x)|x|^p`), `signed` (legado, sem ε);
  `exponentStep` configurável (padrão 0,5 como documentado). Registrar o modo no modelo
  exportado. Alinhar o Dart.
- **Teste.** `x=−2, p=2 → 4` (hybrid); `x=−2, p=2 → −4` (signed); `p=1,5` ímpar em ambos;
  mesma matriz Ψ em C++ e Dart.

### P0-7. Métricas de teste calculadas e expostas durante a execução
- **Evidência.** `identification_pipeline.cpp:657`: a thread de atualização chama
  `compute_test_metrics()` a cada 2 s durante a execução; `best_model_json()` publica
  `rmseTest/r2Test`, que a UI mostra ao vivo.
- **Impacto.** Permite seleção/parada baseada no teste (por pessoa ou agente). Viola o
  protocolo de avaliação.
- **Correção.** Teste calculado apenas quando o estado é `completed`/`stopped`; nunca no
  snapshot do agente; marcar na exportação que o teste foi avaliado uma única vez.
- **Teste.** Durante a execução `rmseTest` deve ser `null`; após a conclusão, finito.

### P0-8. Métricas de teste apenas one-step, em escala normalizada
- **Evidência.** `compute_test_metrics` usa `predict_one_step` em dados normalizados. O
  resultado publicado (R² = 0,99998 no WH, `assets/avaliacao_cientifica.md`) é R² one-step.
- **Impacto.** Para sistemas amostrados rapidamente, R² one-step ≈ 1 é trivial (y(k)≈y(k−1)).
  Os benchmarks WH/Silverbox avaliam **erro de simulação livre** em escala original.
  A afirmação de desempenho não é sustentada pelo protocolo usado.
- **Correção.** Reportar one-step **e** free-run (treino/validação/teste) em escala
  normalizada e original, com o transiente inicial descartado conforme o benchmark.
- **Teste.** Verificação independente em Python das mesmas métricas (tolerância 1e-9).

---

## P1 — Problemas que distorcem a busca, os diagnósticos ou os agentes

### P1-1. Crossover nunca reduz o número de regressores
- **Evidência.** `de_optimizer.cpp:259–268`: para posições além do menor cromossomo, o regressor
  existente é sempre copiado (ramo `else if` linha 265); o mutante tem
  `max(|x_i|,|x_pbest|,|x_r1|)` regressores. Logo `|trial| ≥ |target|` sempre.
- **Impacto.** Viés de crescimento (bloat); parcimônia só por seleção entre tamanhos já
  existentes; os indivíduos tendem ao `maxRegressors`.
- **Correção.** Crossover posicional com decisão independente também nas posições excedentes;
  operadores estruturais explícitos (inserir/remover/trocar regressor) com probabilidade
  configurável; eliminação de regressores e termos duplicados.
- **Teste.** Distribuição de tamanhos dos trials deve conter tamanhos menores que o alvo.

### P1-2. Seleção do campeão e métricas usam só uma fração da validação
- **Evidência.** `identification_pipeline.cpp:569–583` divide a validação em `n_islands` partes
  ("regimes"); `canonical_best_locked` (`de_optimizer.cpp:549`) reavalia os campeões sob a ilha
  0, cuja janela é **apenas o primeiro terço** da validação. `rmseVal` exportado é dessa fração.
- **Impacto.** Seleção final ruidosa; `rmseVal` não é a métrica de validação declarada.
- **Correção.** Avaliador canônico com a validação completa e pesos de referência; regimes
  por ilha continuam disponíveis (e desligáveis) como mecanismo de busca.

### P1-3. Ajuste de CR redefine μF adaptado (e vice-versa)
- **Evidência.** `de_optimizer.cpp:768–779` → `Island::update_config` copia `mu_f`/`mu_cr` da
  configuração original para o estado JADE.
- **Impacto.** Uma ação do agente sobre CR desfaz a adaptação de F (efeito colateral oculto),
  confundindo a atribuição de crédito ao agente.
- **Correção.** Ajustar somente o parâmetro alvo, preservando o outro.

### P1-4. Fases do currículo sobrescrevem ajustes do agente
- **Evidência.** `phase_weights` parte de `cfg_.weights` (`identification_pipeline.cpp:325`); ajustes
  do agente alteram só os pesos das ilhas e são perdidos na próxima transição de fase.
- **Impacto.** O efeito de uma ação pode desaparecer sem registro; a recompensa observada
  mistura ação e transição de fase.
- **Correção.** Ações do agente atualizam a base de configuração usada pelas fases; transições
  de fase registradas no log e sinalizadas nas observações do agente.

### P1-5. Snapshot do motor C++ incompleto e parcialmente falso
- **Evidência.** `aegis_ffi_service_native.dart:284–312`: `meanFitness = bestFitness`,
  `median = best`, quartis = ∞, `islandSnapshots = []`. `population_diversity` é o desvio
  padrão do fitness misturando ilhas com pesos/regimes diferentes.
- **Impacto.** O agente recebe sinais incorretos (média = melhor, nenhuma informação por ilha).
- **Correção.** O núcleo publica estatísticas por ilha (melhor, média, mediana, desvio,
  estagnação, taxa de sucesso, μF, μCR, papel, estruturas únicas) e globais reais.

### P1-6. Diagnósticos implementados mas nunca executados
- **Evidência.** `LocalRefiner`, `AutomaticPruner`, `OverfittingDetector`, `UnderfittingDetector`,
  `ExcitationAnalyzer`, `CollinearityAnalyzer`, `PopulationDiversityMonitor`, `ThreadPool` não são
  chamados em nenhum ponto do pipeline. `enable_refiner/enable_pruner` não têm efeito. Os
  campos `is_stable`, `overfitting`, `underfitting`, `pe_ok` do snapshot são sempre os padrões.
  O README afirma que poda e refinamento rodam ao final.
- **Correção.** Executar sobre-/sub-ajuste e estabilidade a cada relatório; poda e refino como
  pós-processamento opcional, aceito apenas se o fitness canônico (validação) não piorar.

### P1-7. Comunicação WebSocket pode travar o motor e perde auditoria
- **Evidência.** `agent_controller.cpp:137` `send` bloqueante chamado do thread do DE a cada
  geração; threads de cliente `detach` (linha 357) acessam `this` após `stop()`; ações recebidas
  vão para um log interno que não é exportado; só a primeira chave de `proposed_changes` é lida.
- **Impacto.** Um cliente lento pode parar a evolução; possível uso após liberação; ações sem
  trilha de auditoria.
- **Correção.** Envio com timeout/não bloqueante e limitação de frequência; threads com join;
  todas as ações passam pela mesma interface tipada do pipeline e pelo mesmo log.

### P1-8. Interface de ações do agente sem contrato
- **Evidência.** `handle_suggestion` aceita 14 nomes; limites diferem do README e do prompt do
  LLM; `-1 = unknown param` documentado mas nunca retornado; `old_value` não registrado; sem
  limite de taxa; strings de log não escapadas (`tuning_log_json` quebra com aspas).
- **Correção.** Interface tipada única (`aegis_apply_action`) com esquema publicado,
  limites, passo máximo por ação, cooldown, códigos de rejeição, valor anterior, geração,
  origem (agente) e JSON escapado.

### P1-9. Agente local UCB1: cooldown ignorado e recompensa confundida
- **Evidência.** `local_adaptive_agent.dart:91` sinais severos ignoram o cooldown (teste
  reprovado na linha de base). A recompensa é `fitness_antes − fitness_depois` bruto, sem
  baseline, sem normalização e atravessando transições de fase (pesos diferentes). O README
  descreve ciclo de 10 gerações, c = 1,2 e recompensa com baseline; o código usa 25, c = 0,5,
  sem baseline. Braços por parâmetro, sem direção.
- **Correção.** Cooldown também para sinais severos; recompensa relativa com baseline de
  deriva recente; observações que cruzam mudança de fase marcadas inconclusivas; documentação
  alinhada.

### P1-10. Agente LLM sem timeout, sem registro de trajetória e com validação só no C++
- **Evidência.** `llm_agent_native.dart`: `http.post` sem timeout; nenhum registro de prompt,
  resposta, latência ou custo; aplica a primeira chave sem validar; snapshot enviado contém os
  campos falsos de P1-5; modelo fixo no código.
- **Correção.** Timeout, registro estruturado (estado, recomendação, justificativa, ação
  aplicada/rejeitada, latência, tokens), validação local + no núcleo, resposta explícita de
  "evidência insuficiente", interruptor sem afetar a execução.

### P1-11. Avaliação lenta (recalcula `pow` ~4× por indivíduo)
- **Evidência.** Ψ é recalculada para ajuste, ERR, predição de treino e de validação.
  ~0,6 s/geração no WH (8192 amostras).
- **Correção.** Calcular Ψ uma vez por avaliação; reutilizar para ajuste, ERR e predição;
  potências inteiras por multiplicação.

### P1-12. QR "rank-revealing" incorreto
- **Evidência.** `regressor_library.cpp:123–129`: ao pular uma coluna quase dependente, a
  linha correspondente não é reutilizada pelas reflexões seguintes; a solução deixa de ser a
  de mínimos quadrados.
- **Correção.** QR com ponteiro de linha independente do índice de coluna (colunas
  dependentes recebem θ = 0 e não consomem linha).
- **Teste.** Ψ com coluna duplicada → mesmo resíduo que Ψ sem a coluna.

### P1-13. Simulação livre no fitness usa só 50 amostras
- **Evidência.** `freeRunHorizon = 50` por padrão.
- **Impacto.** O critério favorece modelos bons a curto prazo, que podem divergir depois.
- **Correção.** Manter configurável, registrar e testar em ablação; relatório final usa
  simulação completa.

### P1-14. Motor Dart (fallback) é outro algoritmo
- **Evidência.** Sem intercepto, sem pseudo-linearização (racionais tratados como
  polinomiais), fitness = BIC de treino, sem currículo, `RelativeImprovement(1e-8)` em
  janela de 50 encerra cedo, semente por relógio, `MaxGenerations(5000)` fixo.
- **Correção.** Documentar como motor simplificado; alinhar a base numérica (potências,
  intercepto) e verificar consistência C++×Dart para a avaliação de um mesmo cromossomo.

---

## P2 — Documentação, robustez e qualidade

| # | Problema | Evidência |
|---|---|---|
| P2-1 | README: p-best `max(2, 0,05·NP)`; código usa 20 % | `de_optimizer.cpp:153` |
| P2-2 | README: topologias anel/estrela/aleatória no C++; C++ só anel | `de_optimizer.cpp:505` |
| P2-3 | README: migrantes limitados a [1,5]; C++ não limita | `de_optimizer.cpp:501` |
| P2-4 | `numThreads` não tem efeito (uma thread por ilha criada a cada geração) | `de_optimizer.cpp:676` |
| P2-5 | Defaults divergentes: `noInputPenalty` 0,5 (C++) × 1,5 (README); `phaseStagnationLimit` 150 × 100; `freeRunPenalty` lido com defaults 0 e 0,5 | `identification_pipeline.cpp:150–159` |
| P2-6 | README cita `agent_websocket_service.dart`, inexistente | README §16 |
| P2-7 | Exportação JSON sem configuração, semente, normalização, log de ações | `results_screen.dart:261` |
| P2-8 | Elites não geram trials | `de_optimizer.cpp:309` |
| P2-9 | Regressores com termos repetidos (`u(k−15)·…·u(k−15)`) | `results/aegis_WHmodel_*.json` |
| P2-10 | `TuningLogEntry` com campos não inicializados | `agent_controller.hpp:49` |
| P2-11 | Histórico Dart duplica snapshots a cada poll de 200 ms | `aegis_ffi_service_native.dart:129` |
| P2-12 | Registro de parâmetros Dart atualizado mesmo quando o núcleo rejeita | `aegis_ffi_service_native.dart:109` |
| P2-13 | OpenMP vinculado mas não usado | `CMakeLists.txt` |
| P2-14 | Proveniência de `Benchmarks/WH_estimation_uy.csv` desconhecida (8192 amostras ≠ benchmark oficial) | `Benchmarks/` |
| P2-15 | Baselines Python usam outra representação (máscara binária) — comparação não equivalente | `python/baseline_methods.py` |
| P2-16 | Recursos fuzzy/neurais **não existem** no código (só UCB1, histórico e log) | busca no repositório |

---

## Sequência de correção adotada (reversível)

1. Núcleo numérico: normalização, potências, QR, avaliação única de Ψ, simulação livre,
   estabilidade, resíduos, métricas de teste (P0-2…P0-8, P1-11, P1-12).
2. Busca: crossover/estruturas, avaliador canônico, JADE/tuning, ablações por configuração
   (P1-1…P1-4, P1-13).
3. Interface de agentes: ações tipadas, log/trajetória, modo síncrono (lockstep),
   snapshot completo, WebSocket seguro (P1-5, P1-7, P1-8).
4. Agentes: UCB1 (P1-9), LLM (P1-10), política fuzzy nova, registro de trajetórias.
5. Lote, experimentos e análise estatística (P0-1).
6. Documentação e testes.
