# Fluxo de Identificação do Modelo em AEGIS

Este documento descreve a arquitetura completa e o fluxo de identificação da ferramenta AEGIS —
do pré-processamento até a seleção do melhor modelo NARX racional, incluindo a integração com o
motor C++, a ponte FFI e o agente LLM baseado na Claude API.

---

## Arquitetura geral

```
┌─────────────────────────────────────────────────────────┐
│                      Flutter UI                         │
│  DataScreen · EvolutionScreen · AgentDashboardScreen    │
│  ResultsScreen · HowToScreen · AboutScreen              │
└────────────────────┬────────────────────────────────────┘
                     │ Riverpod (engineProvider)
┌────────────────────▼────────────────────────────────────┐
│                   EngineNotifier (Dart)                  │
│  • Inicializa pipeline  • Polling 200 ms                 │
│  • applyTuning()        • _onGeneration()               │
└──────┬─────────────────────────────┬────────────────────┘
       │ dart:ffi (AegisFfiService)  │ GenerationSnapshot
┌──────▼──────────┐        ┌─────────▼────────────────────┐
│  aegis_core.dll │        │     LlmAgent (Dart)           │
│  C++ core       │        │  • processSnapshot()          │
│  • DE optimizer │        │  • cooldown 50 gerações       │
│  • Normalizer   │        │  • POST /v1/messages (Claude) │
│  • RationalModel│        │  • onSuggestion → applyTuning │
│  • LocalRefiner │        └──────────────────────────────┘
│  • WebSocket srv│◄── externos (monitoramento opcional)
└─────────────────┘
```

### Backends disponíveis

| Plataforma | Motor de identificação | Agente LLM | Deploy |
|------------|----------------------|------------|--------|
| Windows (com `aegis_core.dll`) | C++ via FFI (JADE multi-ilha, full) | Claude API ativo | `flutter run -d windows` |
| Windows (sem DLL) | Dart puro (`DEEngine`) | Claude API ativo | `flutter run -d windows` |
| Web / GitHub Pages | Dart puro (`DEEngine`) | **Inativo** (sem `dart:io`) | automático via CI |

A seleção é automática: `AegisLibrary.tryLoad()` é chamado em `main()` e, se falhar,
`EngineNotifier` usa o motor Dart existente. No web, os stubs condicionais garantem
que `dart:ffi`, `dart:io` e `package:ffi` **nunca são compilados**.

### Deploy no GitHub Pages

O repositório usa GitHub Actions para build e deploy automático em cada push para `main`:

```
.github/workflows/deploy.yml
  flutter build web --release --base-href "/<repo>/"
  → https://LASEC-UFU.github.io/AEGIS/
```

**Funcionalidades disponíveis no web:**

| Recurso | Web | Windows (nativo) |
|---------|-----|------------------|
| Carregar CSV | ✅ | ✅ |
| Motor DE (Dart) | ✅ | ✅ |
| Motor DE (C++ JADE) | ❌ | ✅ (com DLL) |
| Agente LLM (Claude API) | ❌ | ✅ |
| How to Use / About | ✅ | ✅ |
| Gráficos e resultados | ✅ | ✅ |

> O agente LLM é inativo no web porque requer `dart:io` (para ler `ANTHROPIC_API_KEY`
> do ambiente) e o servidor WebSocket C++ não existe nessa plataforma. Todas as telas
> e o motor Dart funcionam normalmente.

---

## 1. Pré-processamento dos dados

### 1.1 Normalização

**C++ (quando DLL disponível):** `Normalizer` em `cpp/src/normalizer.cpp`

Três estratégias configuráveis via JSON (`normalizerType`):

| Tipo | Parâmetro JSON | Descrição |
|------|----------------|-----------|
| `minmax` (padrão) | `"minmax"` | Escala para `[norm_lo, norm_hi]` (padrão `[1e-6, 1.0]`) |
| `robust` | `"robust"` | Mediana + IQR — resistente a outliers |
| `zscore` | `"zscore"` | Média zero, desvio padrão unitário |

**Dart (fallback):** `lib/engine/identification/data_normalizer.dart` — MinMax com
`lowerBound = 0.01`, `upperBound = 1.0`.

### 1.2 Divisão dos dados

A separação é **sequencial** (preserva a ordem temporal — essencial para séries temporais):

| Conjunto | Razão padrão | Parâmetro JSON |
|----------|-------------|----------------|
| Treino | 70% | `trainRatio` |
| Validação | 15% | `validationRatio` |
| Teste | 15% (restante) | — |

**C++:** feito internamente em `IdentificationPipeline::split_data()` após normalização.  
**Dart:** `lib/engine/identification/data_splitter.dart` e passado explicitamente via FFI.

---

## 2. Representação do modelo — NARX Racional

O modelo identificado é um **NARX racional** (Nonlinear AutoRegressive with eXogenous inputs):

$$\hat{y}(k) = \frac{\sum_{j \in N} \theta_j \cdot \phi_j(k)}{1 + \sum_{j \in D} \theta_j \cdot \phi_j(k)}$$

Onde cada regressor $\phi_j(k)$ é um produto de termos com expoentes reais:

$$\phi_j(k) = \prod_{t} \text{sign}(x_{v_t}(k - d_t)) \cdot (|x_{v_t}(k - d_t)| + \varepsilon)^{p_t}$$

- $v_t$: índice da variável (entrada ou saída passada)
- $d_t$: atraso $\geq 1$
- $p_t \in [p_{\min}, p_{\max}]$: expoente real (ex.: 0.5 a 5.0 em passos de 0.5)
- $\varepsilon = 10^{-9}$: guarda contra divisão por zero em `safe_power` / `signed_power`

**Cromossomo:** lista de `Regressor` (cada um com lista de `Term`), coeficientes $\theta$ e
flag `is_denominator` por regressor.

---

## 3. Construção da matriz $\Psi$ e estimação de coeficientes

Definido o cromossomo, monta-se a matriz de regressores $\Psi$ (`cpp/src/regressor_library.cpp`):

1. Para cada amostra usável $k = d_{\max}, \ldots, N-1$:
   - Avalia-se cada $\phi_j(k)$ → linha da matriz $\Psi$
2. Para modelos racionais: **pseudo-linearização** dos regressores denominador:
   $\psi_j(k) \leftarrow -y(k) \cdot \psi_j(k)$
3. **Solução QR** (Householder): $\min \|\Psi\,\theta - y\|_2$ → `qr_solve()`
4. Coeficientes validados (NaN/Inf → cromossomo inválido)

---

## 4. Avaliação de fitness (IndividualEvaluator)

`cpp/src/individual_evaluator.cpp`

### 4.1 Métricas calculadas

| Métrica | Descrição |
|---------|-----------|
| SSE | Soma dos quadrados dos erros (treino) |
| RMSE treino / validação | Raiz do erro quadrático médio |
| AIC / BIC | Critérios de informação |
| FPE / MDL | Final Prediction Error, Minimum Description Length |
| ERR | Error Reduction Ratio por regressor (Gram-Schmidt modificado) |

### 4.2 Penalidades

| Penalidade | Parâmetro | Propósito |
|------------|-----------|-----------|
| Denominador | `denominatorPenalty` | Penaliza modelos mais complexos (racionais) |
| Complexidade | `complexityPenalty` | Penaliza número de termos |
| Expoente | `exponentPenalty` | Penaliza expoentes muito distantes de 1.0 |
| Estabilidade | `stabilityPenalty` | Penaliza raízes do denominador fora do círculo unitário |

### 4.3 Fitness composto

$$f = \text{RMSE}_{\text{val}} + \alpha \cdot \max(0, \text{BIC}) + \beta \cdot P_D + \gamma \cdot P_C + \delta \cdot P_E + \eta \cdot P_S$$

Fitness menor = modelo melhor.

---

## 5. Otimização por Differential Evolution (multi-ilha JADE)

`cpp/src/de_optimizer.cpp` / `lib/engine/de/de_engine.dart`

### 5.1 Estrutura de ilhas

Cada ilha é um conjunto **independente** de cromossomos com seu próprio RNG e parâmetros JADE.
A comunicação entre ilhas acontece via migração periódica.

```
Ilha 0 ──┐
Ilha 1 ──┼── Migração circular a cada migrationInterval gerações
Ilha 2 ──┘
```

### 5.2 JADE (Adaptive DE)

Cada geração, por indivíduo:

1. **Mutação** `DE/current-to-pbest/1`:
   $v_i = x_i + F_i \cdot (x_{pbest} - x_i) + F_i \cdot (x_{r1} - x_{r2})$
   - $F_i \sim \text{Cauchy}(\mu_F, 0.1)$, clipado a $(0, 2]$
   - $\mu_F$ adaptado via média de Lehmer dos $F$ bem-sucedidos
2. **Crossover binomial**: mistura `trial` com `target` gene a gene com taxa $CR_i$
   - $CR_i \sim \mathcal{N}(\mu_{CR}, 0.1)$, clipado a $[0, 1]$
   - $\mu_{CR}$ adaptado via média aritmética dos $CR$ bem-sucedidos
3. **Seleção gulosa**: `trial` substitui `target` se fitness menor
4. **Elitismo**: os `elitismCount` melhores nunca são substituídos

A mutação opera **estruturalmente** sobre o cromossomo: expoentes e atrasos são perturbados
continuamente, variáveis por mutação discreta rara (probabilidade 10%).

### 5.3 Parâmetros DE configuráveis

| Parâmetro | JSON | Padrão | Intervalo |
|-----------|------|--------|-----------|
| Tamanho da população | `populationSize` | 50 | 20–500 |
| Fator de mutação (inicial) | `mutationFactor` | 0.5 | 0.0–2.0 |
| Taxa de crossover (inicial) | `crossoverRate` | 0.9 | 0.0–1.0 |
| Elitismo | `elitismCount` | 2 | 0–20 |
| Intervalo de migração | `migrationInterval` | 20 | 5–200 |
| Taxa de migração | `migrationRate` | 0.1 | 0.0–0.5 |
| Máx. regressores | `maxRegressors` | 8 | 2–20 |
| Máx. termos/regressor | `maxTermsPerReg` | 3 | 1–5 |
| Expoente mínimo | `pmin` | 0.5 | 0.1–1.0 |
| Expoente máximo | `pmax` | 5.0 | 1.0–10.0 |
| Atraso máximo | `maxDelay` | 20 | 1–200 |
| Máx. gerações | `maxGenerations` | 5000 | 100–100000 |
| Limite de estagnação | `stagnationLimit` | 500 | 50–5000 |
| Threads | `numThreads` | auto | 1–64 |

### 5.4 Critérios de parada

O motor para ao primeiro dos seguintes:
- `maxGenerations` atingido
- `stagnationLimit` gerações sem melhora global

---

## 6. Refinamento local (LocalRefiner)

`cpp/src/local_refiner.cpp`

Após cada geração (opcional), o melhor cromossomo passa por refinamento local dos
**coeficientes** (estrutura fixa):

- **Polynomial:** solução QR já é ótima global — refinamento no-op
- **Racional:** iteração **TRF** (Trust Region Reflective) com Jacobiano numérico finito
  - Alternativa: **LM** (Levenberg-Marquardt) via delta inicial invertido
  - Convergência por `ftol` (SSE) ou `xtol` (passo)

---

## 7. Análise e diagnóstico

Módulos em `cpp/src/`:

| Módulo | Classe | O que verifica |
|--------|--------|----------------|
| `residual_analyzer.cpp` | `ResidualAnalyzer` | Autocorrelação e correlação cruzada dos resíduos (teste de brancura) |
| `stability_analyzer.cpp` | `StabilityAnalyzer` | Raízes do polinômio denominador (estabilidade BIBO) |
| `collinearity_analyzer.cpp` | `CollinearityAnalyzer` | VIF — multicolinearidade entre regressores |
| `excitation_analyzer.cpp` | `ExcitationAnalyzer` | Energia de persistência da excitação (PE) |
| `overfitting_detector.cpp` | `OverfittingDetector` | RMSE validação / RMSE treino > limiar |
| `underfitting_detector.cpp` | `UnderfittingDetector` | RMSE treino > limiar absoluto |
| `population_diversity_monitor.cpp` | `PopulationDiversityMonitor` | Hash estrutural + variância de fitness |

Os diagnósticos alimentam o relatório por geração (`GenerationReport`) que é:
- Transmitido via WebSocket C++ (porta 8765) para ferramentas externas
- Retornado via `aegis_get_snapshot()` para o polling Dart (200 ms)
- Enviado ao agente LLM (`LlmAgent::processSnapshot`)

---

## 8. Poda automática (AutomaticPruner)

`cpp/src/automatic_pruner.cpp`

Após a identificação, regressores irrelevantes são removidos por ordem de prioridade:

1. **ERR < limiar**: contribuição explicativa desprezível
2. **VIF > limiar**: colinear com outro regressor (mantém o de menor VIF)
3. **|coeficiente| < limiar**: coeficiente numericamente nulo

O modelo podado é re-estimado com QR e seus coeficientes atualizados.

---

## 9. Agente LLM (Claude API)

`lib/services/llm_agent_native.dart`

O agente LLM ajusta os parâmetros DE **em tempo de execução**, diretamente a partir do
Flutter, sem processo Python ou servidor intermediário.

### 9.1 Fluxo

```
_onGeneration(snapshot)          // chamado pelo polling 200 ms
    └─► LlmAgent.processSnapshot(snap)
            └─► (a cada 50 gerações, se API key presente)
                 POST https://api.anthropic.com/v1/messages
                     model: claude-opus-4-7
                     system: prompt de especialista DE
                     user: JSON do snapshot
                 ◄── {"proposed_changes":{"param":value},"reason":"..."}
                      ou null
            └─► onSuggestion(param, value, reason)
                    └─► EngineNotifier.applyTuning(param, value)
                            └─► AegisFfiService.applyTuning()  (C++)
                                ou DEEngine.applyTuning()       (Dart)
```

### 9.2 Parâmetros ajustáveis pelo agente

| Parâmetro | Intervalo | Heurística típica |
|-----------|-----------|-------------------|
| `mutationFactor` | 0.0–2.0 | Aumentar se diversidade baixa ou estagnação alta |
| `crossoverRate` | 0.0–1.0 | Reduzir se CR alto + diversidade boa |
| `migrationRate` | 0.0–0.3 | Aumentar em estagnação severa |
| `complexityPenalty` | 0.0–10.0 | Aumentar em overfitting; reduzir em underfitting |
| `maxRegressors` | 2–20 | Aumentar se modelo subajustado estruturalmente |

### 9.3 Resolução da API key

O `LlmAgent` busca a chave na seguinte ordem:

1. Argumento do construtor (para testes programáticos)
2. Variável de ambiente `ANTHROPIC_API_KEY`
3. Arquivo `anthropic_api_key.txt` na pasta do executável

**Configuração rápida (Windows):**
```
# Opção A — variável de ambiente (sessão atual)
$env:ANTHROPIC_API_KEY = "sk-ant-..."

# Opção B — arquivo ao lado do executável gerado
copy anthropic_api_key.txt build\windows\x64\runner\Release\
```

O arquivo `anthropic_api_key.txt` está no `.gitignore` — não é versionado.

### 9.4 Cooldown e segurança

- Mínimo de **50 gerações** entre chamadas à API (configurável em `_cooldown`)
- Flag `_calling` evita chamadas concorrentes
- Resposta `null` do Claude → nenhuma ação (motor saudável)
- Valor sugerido fora do intervalo → rejeitado pelo `handle_suggestion` em C++

---

## 10. API C (FFI) — `aegis_api.h`

Todas as funções usam ABI C plano (sem name-mangling) para compatibilidade com `dart:ffi`.

| Grupo | Funções principais |
|-------|--------------------|
| Ciclo de vida | `aegis_create_pipeline`, `aegis_destroy_pipeline` |
| Dados | `aegis_load_data(pipeline, data*, rows, cols)` |
| Configuração | `aegis_configure(pipeline, json_config*)` |
| Controle | `aegis_start`, `aegis_pause`, `aegis_resume`, `aegis_stop` |
| Status | `aegis_get_status`, `aegis_get_snapshot`, `aegis_get_best_model` |
| Tuning | `aegis_apply_tuning(pipeline, param*, value, reason*)` |
| Strings | `aegis_free_string(ptr*)` — libera qualquer char* retornado |
| WebSocket | `aegis_create_agent_server`, `aegis_agent_server_start`, `aegis_agent_broadcast` |
| Info | `aegis_version()` |

**Fluxo Dart (AegisFfiService):**
```dart
_pipeline = lib.createPipeline();
lib.loadData(_pipeline!, nativeData, rows, cols);
lib.configure(_pipeline!, configJson.toNativeUtf8());
lib.start(_pipeline!);
// polling 200 ms:
final snap = lib.getSnapshot(_pipeline!);  // retorna JSON, liberar com freeString
```

---

## 11. WebSocket C++ (porta 8765)

`cpp/src/agent_controller.cpp` — servidor RFC 6455 puro (sem dependências externas).

Usado para **monitoramento externo** (dashboards, scripts de análise):

- Recebe conexões em `localhost:8765`
- Transmite JSON por geração (mesmo payload de `aegis_get_snapshot`)
- Aceita sugestões de parâmetros no formato:
  ```json
  {"proposed_changes": {"mutationFactor": 0.7}, "reason": "estagnação detectada"}
  ```
- Cada sugestão é validada e logada em `tuning_log` acessível via `aegis_get_tuning_log()`

O agente LLM interno (Dart) **não usa** esse WebSocket — comunica-se diretamente via
`applyTuning()`.

---

## 12. Resultado final

Ao término (estagnação ou `maxGenerations`), o melhor cromossomo é recuperado via
`aegis_get_best_model()` com:

- Equação textual: `y_hat(k) = (N) / (1 + D)`
- Coeficientes estimados $\theta$
- Regressores com variáveis, atrasos e expoentes
- Métricas: RMSE treino/validação/teste, R², AIC, BIC, FPE, MDL, SSE
- Diagnósticos: estabilidade, resíduos, colinaridade, excitação
- Valores ERR por regressor

---

## Referências no código

### C++
- `cpp/include/aegis/aegis_api.h` — API pública C
- `cpp/src/identification_pipeline.cpp` — orquestrador principal
- `cpp/src/de_optimizer.cpp` — motor DE multi-ilha JADE
- `cpp/src/individual_evaluator.cpp` — fitness, ERR, estabilidade
- `cpp/src/rational_model.cpp` — predição one-step e free-run
- `cpp/src/regressor_library.cpp` — $\Psi$, QR solver
- `cpp/src/agent_controller.cpp` — servidor WebSocket RFC 6455

### Dart/Flutter
- `lib/ffi/aegis_ffi_service.dart` — ponte FFI Dart↔C++
- `lib/services/llm_agent_native.dart` — agente LLM (Claude API)
- `lib/ui/state/app_state.dart` — `EngineNotifier` (Riverpod)
- `lib/engine/de/de_engine.dart` — motor DE Dart (fallback)
- `lib/agent/generation_snapshot.dart` — estrutura de dados geração
- `lib/agent/tunable_parameter.dart` — registro de parâmetros ajustáveis
