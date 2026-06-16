# AEGIS — Pipeline Python de Análise e Comparação

Pipeline de análise estatística, comparação com métodos de referência e geração de figuras de publicação para o sistema AEGIS.

---

## Sumário

1. [Visão Geral do Pipeline](#1-visão-geral-do-pipeline)
2. [Instalação](#2-instalação)
3. [Fluxo Completo de Uso](#3-fluxo-completo-de-uso)
4. [narx_utils.py — Utilitários NARX compartilhados](#4-narx_utilspy--utilitários-narx-compartilhados)
5. [baseline_methods.py — Métodos de comparação](#5-baseline_methodspy--métodos-de-comparação)
6. [run_comparison.py — Orquestrador de experimentos](#6-run_comparisonpy--orquestrador-de-experimentos)
7. [analyze_batch.py — Análise estatística dos resultados AEGIS](#7-analyze_batchpy--análise-estatística-dos-resultados-aegis)
8. [generate_figures.py — Figuras de publicação](#8-generate_figurespy--figuras-de-publicação)
9. [Formato dos Arquivos JSON](#9-formato-dos-arquivos-json)
10. [Dicas e Resolução de Problemas](#10-dicas-e-resolução-de-problemas)

---

## 1. Visão Geral do Pipeline

```
┌─────────────────────────────────────────────────────────────────┐
│                    AEGIS Python Pipeline                        │
│                                                                 │
│  aegis_batch.exe ──► run_00.json                               │
│  (N execuções)        run_01.json  ──► analyze_batch.py        │
│                       ...             (estatísticas)            │
│                       summary.json                              │
│                            │                                    │
│                            ▼                                    │
│                   generate_figures.py ──► fig1…fig6.pdf/png    │
│                            ▲                                    │
│                            │                                    │
│  run_comparison.py ──► DE-Classic/                             │
│  (baselines)              JADE/        ──► comparison_table    │
│                           GA/                                   │
│                           PSO/                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Separação de responsabilidades:**

| Etapa | Ferramenta | O que faz |
|-------|-----------|-----------|
| Identificação | `aegis_batch.exe` (C++) | Roda N experimentos AEGIS, salva JSONs |
| Análise AEGIS | `analyze_batch.py` | Estatísticas descritivas dos resultados AEGIS |
| Comparação | `run_comparison.py` | Roda DE clássico, JADE, GA, PSO no mesmo dataset |
| Figuras | `generate_figures.py` | Gera 6 figuras de publicação (PDF + PNG) |

Os scripts Python são independentes entre si — cada um pode ser rodado isoladamente conforme a necessidade.

---

## 2. Instalação

### Pré-requisitos

- Python ≥ 3.10
- pip

### Instalar dependências

```bash
cd python/
pip install -r requirements.txt
```

**Pacotes instalados:**

| Pacote | Versão mínima | Uso |
|--------|---------------|-----|
| `numpy` | 1.24 | Álgebra linear, matrizes de regressores, OLS |
| `pandas` | 2.0 | Exportação de tabelas CSV (opcional) |
| `matplotlib` | 3.7 | Geração de todas as figuras |
| `seaborn` | 0.12 | Tema visual para figuras (opcional — degradation graceful) |
| `scipy` | 1.10 | Funções estatísticas auxiliares |
| `colorama` | 0.4 | Saída colorida no terminal (opcional) |
| `tqdm` | 4.65 | Barra de progresso em `run_comparison.py` (opcional) |

> **Nota:** `seaborn`, `colorama` e `tqdm` são opcionais. Os scripts funcionam sem eles, apenas com output visual menos elaborado.

---

## 3. Fluxo Completo de Uso

### Passo 1 — Rodar o AEGIS em modo batch (C++)

Antes de usar os scripts Python, rode o `aegis_batch.exe` para gerar os JSONs de resultado:

```powershell
# Build (se ainda não foi feito)
cmake -S cpp -B cpp/build_win -DCMAKE_BUILD_TYPE=Release
cmake --build cpp/build_win --config Release

# Rodar 10 experimentos independentes no dataset WH
.\cpp\build_win\Release\aegis_batch.exe `
    --data data/WH_estimation_uy.csv `
    --runs 10 `
    --seed-start 0 `
    --output results/aegis_wh/ `
    --islands 3 `
    --pop-size 50 `
    --max-gen 5000 `
    --verbose
```

Isso cria:
```
results/aegis_wh/
├── run_00.json   ← seed=0
├── run_01.json   ← seed=1
├── ...
├── run_09.json   ← seed=9
└── summary.json  ← resumo de todas as execuções
```

### Passo 2 — Analisar os resultados AEGIS

```bash
python analyze_batch.py --results results/aegis_wh/
```

Saída no terminal:
```
══════════════════════════════════════════════════════════════════
  AEGIS Batch Analysis — AEGIS
  Diretório : results/aegis_wh/
  Execuções : 10
══════════════════════════════════════════════════════════════════

  Métrica               Média ± Desvio          Min         Max         Mediana
  ──────────────────    ────────────────────    ────────    ────────    ────────
  R² (treino)           0.9998 ± 0.0001         0.9996      0.9999      0.9998
  R² (teste)            0.9997 ± 0.0002         0.9994      0.9999      0.9997
  ...
```

### Passo 3 — Rodar métodos de comparação

```bash
python run_comparison.py \
    --data data/WH_estimation_uy.csv \
    --runs 10 \
    --methods de jade ga pso \
    --aegis-results results/aegis_wh/summary.json \
    --output comparison_results/wh/
```

### Passo 4 — Gerar figuras de publicação

```bash
python generate_figures.py \
    --aegis results/aegis_wh/ \
    --baselines comparison_results/wh/ \
    --out figures/wh/ \
    --phases 400 900 1800
```

---

## 4. narx_utils.py — Utilitários NARX compartilhados

**Arquivo:** `narx_utils.py`
**Papel:** Biblioteca interna compartilhada por todos os outros scripts. Não é executado diretamente.

### O que contém

#### `NarxConfig` — Configuração do problema NARX

Dataclass com todos os parâmetros do problema:

```python
from narx_utils import NarxConfig

cfg = NarxConfig(
    n_y        = 9,     # número de atrasos da saída y(k-1)..y(k-n_y)
    n_u        = 9,     # número de atrasos da entrada u(k-1)..u(k-n_u)
    max_degree = 2,     # grau máximo do polinômio (1=linear, 2=quadrático)
    output_col = -1,    # índice da coluna de saída (-1 = última coluna)
    train_ratio = 0.70, # fração para treino
    val_ratio   = 0.15, # fração para validação
    test_ratio  = 0.15, # fração para teste
    alpha_bic   = 0.01, # peso do BIC na fitness
    gamma_cplx  = 0.01, # peso da penalidade de complexidade
)
```

#### `load_csv(path)` — Carregamento de dados

- Auto-detecta separador: tab (`\t`), ponto-e-vírgula (`;`) ou vírgula (`,`)
- Pula linhas de cabeçalho (linhas sem valores numéricos)
- Retorna `np.ndarray` de shape `(n_amostras, n_colunas)`

```python
from narx_utils import load_csv
data = load_csv("WH_estimation_uy.csv")
# data.shape → (8192, 2)  para o dataset WH
```

#### `normalize_minmax(data, train_end)` — Normalização MinMax

- Ajusta os parâmetros (min, max) **somente** nas primeiras `train_end` linhas (partição de treino)
- Aplica a normalização em **todas** as linhas — sem data leakage do teste para o treino
- Retorna `(data_normalizado, mins, maxs)`

```python
from narx_utils import normalize_minmax, split_indices

t_end, v_end = split_indices(len(data), cfg)
data_norm, mins, maxs = normalize_minmax(data, t_end)
```

#### `enumerate_candidates(n_cols, cfg)` — Enumeração de regressores candidatos

Gera todos os regressores polinomiais possíveis até `cfg.max_degree`:

- **Grau 1:** `y(k-1)`, `y(k-2)`, ..., `u(k-1)`, `u(k-2)`, ...
- **Grau 2:** `y(k-1)·y(k-1)`, `y(k-1)·y(k-2)`, `y(k-1)·u(k-1)`, ...

Retorna `(candidates, labels)`:
- `candidates`: lista de termos, cada termo é uma lista de `(col_idx, lag)`
- `labels`: strings descritivas para cada candidato (ex: `"y(k-1)·u(k-3)"`)

```python
candidates, labels = enumerate_candidates(data.shape[1], cfg)
print(f"Total de candidatos: {len(candidates)}")
# Para n_y=9, n_u=9, degree=2, 2 variáveis → ~189 candidatos
```

#### `NarxEvaluator` — Avaliador de fitness rápido

Pré-constrói a matriz de regressores completa uma única vez; avaliações individuais são simples seleções de colunas + OLS. Muito mais rápido do que reconstruir a matriz a cada cromossomo.

```python
from narx_utils import NarxEvaluator
import numpy as np

evaluator = NarxEvaluator(data_norm, candidates, cfg)

# Avaliar uma seleção (máscara binária)
mask = np.zeros(len(candidates))
mask[[0, 3, 7]] = 1.0   # seleciona candidatos 0, 3 e 7

fitness, metrics = evaluator.evaluate(mask)
print(f"fitness={fitness:.4f}  R²_val={metrics['r2_val']:.4f}")
```

**Estrutura do dicionário de métricas retornado:**
```python
{
    "r2_train":   0.9998,
    "r2_val":     0.9997,
    "r2_test":    0.9996,
    "rmse_train": 0.0012,
    "rmse_val":   0.0013,
    "rmse_test":  0.0014,
    "n_terms":    3,
    "bic":        -45231.2,
    "aic":        -45280.1,
}
```

**Função de fitness (mesma lógica do AEGIS, simplificada para baselines):**

$$f = \text{RMSE}_{\text{val}} + \alpha \cdot \frac{\text{BIC}}{n_{\text{treino}}} + \gamma \cdot k$$

onde $k$ é o número de termos selecionados.

> **Por que simplificada?** Os métodos baseline não têm acesso ao núcleo C++ do AEGIS. Eles usam uma versão Python da fitness com os componentes principais (RMSE + BIC + complexidade), sem a penalidade free-run ($\theta$) nem a penalidade de ausência de entrada ($\zeta$) — que são vantagens específicas do AEGIS.

---

## 5. baseline_methods.py — Métodos de comparação

**Arquivo:** `baseline_methods.py`
**Papel:** Implementa DE Clássico, JADE, GA binário e PSO binário para identificação NARX. Todos usam `NarxEvaluator` para fitness. Não é executado diretamente — importado por `run_comparison.py`.

### Codificação do cromossomo (compartilhada por todos os métodos)

Todos os métodos operam com um **vetor contínuo em [0,1]ⁿ**, binarizado por limiar 0,5:

```
cromossomo = [0.3, 0.8, 0.1, 0.7, ...]   ← vetor contínuo
máscara    = [0,   1,   0,   1,   ...]   ← x > 0.5 → inclui regressor
```

Cada posição corresponde a um regressor candidato do pool gerado por `enumerate_candidates()`.

---

### `run_de_classic()` — DE Clássico (DE/rand/1/bin)

Evolução Diferencial clássica com parâmetros **fixos** $F$ e $CR$ — sem adaptação.

**Referência:** Storn & Price (1997)

**Assinatura:**
```python
from baseline_methods import run_de_classic

best_mask, best_fit, metrics, history = run_de_classic(
    evaluator,         # NarxEvaluator
    n_cands,           # número de candidatos (dimensão do cromossomo)
    pop_size  = 100,   # tamanho da população
    max_gen   = 5000,  # número máximo de gerações
    F         = 0.5,   # fator de mutação (fixo)
    CR        = 0.9,   # taxa de crossover (fixo)
    seed      = 0,     # semente aleatória
    verbose   = False, # imprimir progresso
)
```

**Operadores:**
- **Mutação:** `v = a + F·(b − c)` onde `a, b, c` são indivíduos distintos aleatórios
- **Crossover:** binomial — cada dimensão herda do mutante com prob. `CR`; pelo menos uma dimensão sempre muda
- **Seleção:** greedy — trial substitui o pai somente se `f(trial) ≤ f(pai)`

**Saída:**
- `best_mask` — máscara binária do melhor cromossomo
- `best_fit` — melhor valor de fitness
- `metrics` — dicionário com R², RMSE, etc. do melhor cromossomo
- `history` — lista de `[gen, fitness]` para curva de convergência

---

### `run_jade()` — JADE (DE autoadaptativo)

DE com autoadaptação de $F$ e $CR$ via aprendizado por histórico de sucesso.

**Referência:** Zhang & Sanderson (2009) — *IEEE Trans. Evolutionary Computation*

**Assinatura:**
```python
from baseline_methods import run_jade

best_mask, best_fit, metrics, history = run_jade(
    evaluator,
    n_cands,
    pop_size = 100,
    max_gen  = 5000,
    mu_F     = 0.5,   # média inicial de F
    mu_CR    = 0.9,   # média inicial de CR
    c        = 0.1,   # taxa de aprendizado (Lehmer mean)
    p        = 0.05,  # fração top-p para current-to-pbest
    seed     = 0,
)
```

**Mecanismos de adaptação:**
- $F_i \sim \text{Cauchy}(\mu_F, 0.1)$, recalibrado se $F_i \leq 0$
- $CR_i \sim \mathcal{N}(\mu_{CR}, 0.1)$, clampado em $[0, 1]$
- Após cada geração: $\mu_F \leftarrow (1-c)\,\mu_F + c\,\text{mean}_L(S_F)$ (média de Lehmer)
- $\mu_{CR} \leftarrow (1-c)\,\mu_{CR} + c\,\text{mean}(S_{CR})$ (média aritmética)
- **Arquivo externo:** cromossomos substituídos são mantidos em memória para diversidade adicional

**Estratégia de mutação:** `current-to-pbest/1` — combina o melhor global (top-p%) com dois aleatórios do arquivo estendido.

---

### `run_ga()` — Algoritmo Genético binário

GA clássico com seleção por torneio, crossover uniforme e mutação bit-flip.

**Assinatura:**
```python
from baseline_methods import run_ga

best_mask, best_fit, metrics, history = run_ga(
    evaluator,
    n_cands,
    pop_size        = 100,
    max_gen         = 5000,
    crossover_prob  = 0.9,   # probabilidade de crossover
    mutation_prob   = 0.02,  # probabilidade de flip por bit
    tournament_k    = 3,     # tamanho do torneio de seleção
    elitism         = 2,     # número de elites preservados
    seed            = 0,
)
```

**Operadores:**
- **Seleção:** torneio de tamanho `tournament_k` — vence o de menor fitness
- **Crossover uniforme:** cada bit herda de um dos pais com prob. 0,5
- **Mutação bit-flip:** cada bit tem prob. `mutation_prob` de ser invertido
- **Elitismo:** os `elitism` melhores indivíduos são copiados diretamente para a próxima geração sem alteração

---

### `run_pso()` — PSO binário (com sigmoid)

Particle Swarm Optimization adaptado para espaço binário via função de transferência sigmoid.

**Referência:** Kennedy & Eberhart (1997) — *Proc. IEEE Congress on Evolutionary Computation*

**Assinatura:**
```python
from baseline_methods import run_pso

best_mask, best_fit, metrics, history = run_pso(
    evaluator,
    n_cands,
    swarm_size = 100,
    max_gen    = 5000,
    w_start    = 0.9,   # inércia inicial (decaimento linear)
    w_end      = 0.4,   # inércia final
    c1         = 2.0,   # coeficiente cognitivo (melhor pessoal)
    c2         = 2.0,   # coeficiente social (melhor global)
    v_max      = 4.0,   # clamp da velocidade
    seed       = 0,
)
```

**Mecanismo binário:**
1. Velocidade atualizada no espaço contínuo: $v_i \leftarrow w\,v_i + c_1 r_1 (p_{\text{best}} - x_i) + c_2 r_2 (g_{\text{best}} - x_i)$
2. Probabilidade de ativação: $\sigma(v_i) = 1/(1 + e^{-v_i})$
3. Binarização: $x_i = 1$ se $\text{rand}() < \sigma(v_i)$, senão $x_i = 0$
4. Velocidade clampada em $[-v_{\max}, v_{\max}]$ para evitar saturação do sigmoid

**Decaimento de inércia:** linear de `w_start` para `w_end` ao longo das gerações.

---

## 6. run_comparison.py — Orquestrador de experimentos

**Arquivo:** `run_comparison.py`
**Papel:** Roda todos os métodos de comparação em sequência, com o mesmo protocolo experimental, e gera a tabela comparativa final.

### Uso

```bash
python run_comparison.py --data <csv> [opções]
```

### Argumentos completos

| Argumento | Padrão | Descrição |
|-----------|--------|-----------|
| `--data` | *(obrigatório)* | Arquivo CSV/TSV de entrada |
| `--output` | `comparison_results/` | Diretório raiz de saída |
| `--methods` | `de jade ga pso` | Métodos a executar (qualquer combinação) |
| `--runs` | `10` | Número de execuções por método |
| `--seed-start` | `0` | Primeira semente aleatória |
| `--max-gen` | `5000` | Número máximo de gerações/iterações |
| `--pop-size` | `100` | Tamanho da população/enxame |
| `--n-y` | `9` | Atrasos da saída (deve ser ≥ max_delay do AEGIS) |
| `--n-u` | `9` | Atrasos da entrada |
| `--degree` | `2` | Grau máximo do polinômio |
| `--output-col` | `-1` | Índice da coluna de saída (-1 = última) |
| `--aegis-results` | `None` | Caminho para `summary.json` do AEGIS (inclui na tabela) |
| `--verbose` | `False` | Imprime progresso a cada 500 gerações |

### Exemplos

```bash
# Rodar apenas DE clássico e JADE (mais rápido para teste inicial)
python run_comparison.py \
    --data data/WH_estimation_uy.csv \
    --methods de jade \
    --runs 5 \
    --max-gen 2000

# Comparação completa incluindo resultados já obtidos do AEGIS
python run_comparison.py \
    --data data/WH_estimation_uy.csv \
    --runs 10 \
    --aegis-results results/aegis_wh/summary.json \
    --output comparison_results/wh/

# Verbose para acompanhar convergência
python run_comparison.py \
    --data data/WH_estimation_uy.csv \
    --methods pso \
    --runs 3 \
    --verbose
```

### Estrutura de saída

```
comparison_results/wh/
├── de/
│   ├── run_00.json
│   ├── run_01.json
│   ├── ...
│   └── summary.json
├── jade/
│   ├── run_00.json
│   └── summary.json
├── ga/
│   └── ...
├── pso/
│   └── ...
└── comparison_table.json   ← tabela comparativa com todos os métodos
```

### Tabela impressa no terminal

```
──────────────────────────────────────────────────────────────────────
  Método        R² test (mean±std)      RMSE test (mean±std)    Ger. média
──────────────────────────────────────────────────────────────────────
  AEGIS         0.9999 ± 0.0001         0.0012 ± 0.0001         2063
  JADE          0.9987 ± 0.0012         0.0034 ± 0.0015         4821
  DE-Classic    0.9943 ± 0.0031         0.0071 ± 0.0023         5000
  GA            0.9891 ± 0.0058         0.0098 ± 0.0041         5000
  PSO           0.9876 ± 0.0072         0.0112 ± 0.0059         5000
──────────────────────────────────────────────────────────────────────
```

> **Interpretação da comparação:** Os métodos baseline usam uma fitness simplificada (sem penalidade free-run nem penalidade de ausência de entrada). O resultado esperado é que o AEGIS seja superior — esta comparação serve para evidenciar a contribuição de cada componente do método proposto.

---

## 7. analyze_batch.py — Análise estatística dos resultados AEGIS

**Arquivo:** `analyze_batch.py`
**Papel:** Analisa os JSONs gerados por `aegis_batch.exe`, calcula estatísticas descritivas e identifica a melhor execução.

### Uso

```bash
python analyze_batch.py --results <dir> [opções]
```

### Argumentos

| Argumento | Padrão | Descrição |
|-----------|--------|-----------|
| `--results` | *(obrigatório)* | Diretório com `run_NN.json` (saída do `aegis_batch`) |
| `--export` | `None` | Caminho para salvar tabela CSV com uma linha por execução |
| `--metric` | `r2_test` | Métrica primária para ranking (não altera o relatório, reservado para futuro) |

### Exemplos

```bash
# Análise básica
python analyze_batch.py --results results/aegis_wh/

# Com exportação CSV para Excel/pandas
python analyze_batch.py --results results/aegis_wh/ --export stats.csv

# Funciona também com summary.json diretamente
python analyze_batch.py --results results/aegis_wh/summary.json
```

### O que o script calcula

Para cada métrica numérica disponível nos JSONs:

| Estatística | Descrição |
|-------------|-----------|
| **Média** | `np.mean(valores)` |
| **Desvio padrão** | `np.std(ddof=1)` (amostral, N-1) |
| **Mínimo / Máximo** | Pior e melhor execução |
| **Mediana** | Percentil 50 |
| **Q25 / Q75** | Quartis (para boxplot manual) |

**Métricas analisadas:**

- `r2_train`, `r2_val`, `r2_test` — coeficiente de determinação em cada partição
- `rmse_train`, `rmse_val`, `rmse_test` — RMSE em cada partição
- `n_terms` — número de termos do modelo identificado
- `final_gen` — geração em que convergiu
- `elapsed_s` — tempo de execução em segundos

**Análise de convergência:**
O script analisa os históricos de fitness para estimar a geração em que cada execução atingiu 90% do ganho total (convergência prática), reportando média e desvio dessa geração.

**Taxa de sucesso:**
Informa quantas execuções obtiveram R²_teste > 0.99.

### Exemplo de saída completa

```
════════════════════════════════════════════════════════════════
  AEGIS Batch Analysis — AEGIS
  Diretório : results/aegis_wh/
  Execuções : 10
════════════════════════════════════════════════════════════════

  Métrica               Média ± Desvio          Min         Max         Mediana
  ──────────────────    ────────────────────    ────────    ────────    ────────
  R² (treino)           0.9999 ± 0.0001         0.9996      0.9999      0.9999
  R² (val)              N/A                     N/A         N/A         N/A
  R² (teste)            0.9997 ± 0.0002         0.9994      0.9999      0.9997
  RMSE (treino)         0.0011 ± 0.0003         0.0007      0.0018      0.0010
  RMSE (val)            ...
  RMSE (teste)          0.0013 ± 0.0004         0.0008      0.0021      0.0012
  N termos              6.4 ± 1.2               5.0         9.0         6.0
  Ger. conv.            2341 ± 498              1823        3217        2289
  Tempo (s)             187.3 ± 24.1            152.1       231.8       184.7

  Convergência (geração onde fitness ≈ final):
    Média  : 1987
    Desvio : 412
    Min    : 1523
    Max    : 2743

  Melhor execução: run #2  seed=2
    R²_test  = 0.999976
    R²_train = 0.999983
    N termos = 7
    Max delay= 9
    Gen conv.= 2063
    Tempo    = 171.3s

  R²_test > 0.99 : 10/10 execuções (100%)

════════════════════════════════════════════════════════════════
```

---

## 8. generate_figures.py — Figuras de publicação

**Arquivo:** `generate_figures.py`
**Papel:** Gera 6 figuras de qualidade para publicação em formato PDF (vetor) e PNG (raster), a partir dos JSONs do AEGIS e dos métodos de comparação.

### Uso

```bash
python generate_figures.py --aegis <dir> [--baselines <dir>] [--out <dir>] [opções]
```

### Argumentos

| Argumento | Padrão | Descrição |
|-----------|--------|-----------|
| `--aegis` | *(obrigatório)* | Diretório com JSONs do AEGIS |
| `--baselines` | `None` | Diretório com subpastas de métodos baseline (`de/`, `jade/`, etc.) |
| `--out` | `figures/` | Diretório de saída das figuras |
| `--phases` | `None` | Gerações das transições de fase (ex: `--phases 400 900 1800`) |
| `--data` | `None` | CSV original (para Fig 4, se predições não estão no JSON) |

### Figuras geradas

#### Fig 1 — `fig1_convergence.{pdf,png}` — Curva de convergência AEGIS

- **Eixo X:** geração
- **Eixo Y:** fitness composta (menor = melhor)
- **Série destacada:** melhor execução (ciano)
- **Séries de fundo:** todas as outras execuções (cinza translúcido)
- **Linhas verticais:** transições de fase (se `--phases` fornecido)
- **Uso:** demonstra estabilidade entre execuções e velocidade de convergência

```bash
# Exemplo com marcadores de fase
python generate_figures.py --aegis results/aegis_wh/ \
    --phases 400 900 1800 --out figures/
```

#### Fig 2 — `fig2_r2_boxplot.{pdf,png}` — Boxplot R² todos os métodos

- **Tipo:** boxplot lado a lado por método
- **Eixo Y:** R² no conjunto de teste
- **Marcador diamante:** média de cada método
- **Interpretação:** spread das caixas = variância entre execuções; posição = qualidade média
- **Precisa de:** AEGIS + ao menos um método de comparação

#### Fig 3 — `fig3_comparison_bar.{pdf,png}` — Barras horizontais comparativas

- **Tipo:** barras horizontais com barras de erro (mean ± std)
- **Eixo X:** R² teste
- **Cada barra:** um método
- **Anotação:** valor numérico ao lado de cada barra
- **Uso:** comparação direta publicável em tabela/figura de paper

#### Fig 4 — `fig4_predicted_vs_actual.{pdf,png}` — Predição vs real

- **Painel superior:** sobreposição de $y(k)$ real e $\hat{y}(k)$ previsto no conjunto de teste
- **Painel inferior:** resíduo $e(k) = y(k) - \hat{y}(k)$
- **Dados:** lidos de `best_model.y_test_actual` e `best_model.y_test_predicted` no JSON

> **Nota:** Para que Fig 4 mostre as séries temporais, o AEGIS precisa incluir `y_test_actual` e `y_test_predicted` no JSON exportado. Se esses campos não estiverem presentes, a figura mostra uma mensagem orientando como exportá-los.

#### Fig 5 — `fig5_err_contribution.{pdf,png}` — ERR dos regressores

- **Tipo:** barras horizontais em ordem decrescente de ERR
- **Eixo X:** ERR (%) — porcentagem de variância explicada por cada regressor
- **Anotação:** valor ERR + ERR acumulado
- **Dados:** lidos de `best_model.err_contributions` no JSON exportado pelo AEGIS

#### Fig 6 — `fig6_convergence_comparison.{pdf,png}` — Convergência comparativa

- **Eixo X:** geração/iteração
- **Eixo Y:** melhor fitness na geração
- **Uma curva por método** (melhor execução de cada)
- **Uso:** demonstra que o AEGIS converge mais rápido e/ou para um valor melhor
- **Gerado apenas se** `--baselines` for fornecido

### Exemplo completo

```bash
python generate_figures.py \
    --aegis results/aegis_wh/ \
    --baselines comparison_results/wh/ \
    --out figures/wh/ \
    --phases 400 900 1800
```

Saída:
```
figures/wh/
├── fig1_convergence.pdf
├── fig1_convergence.png
├── fig2_r2_boxplot.pdf
├── fig2_r2_boxplot.png
├── fig3_comparison_bar.pdf
├── fig3_comparison_bar.png
├── fig4_predicted_vs_actual.pdf
├── fig4_predicted_vs_actual.png
├── fig5_err_contribution.pdf
├── fig5_err_contribution.png
├── fig6_convergence_comparison.pdf
└── fig6_convergence_comparison.png
```

---

## 9. Formato dos Arquivos JSON

### `run_NN.json` — Resultado por execução

Produzido por `aegis_batch.exe` (AEGIS) ou por `run_comparison.py` (baselines). Formato unificado para que `analyze_batch.py` e `generate_figures.py` funcionem com ambos.

```json
{
  "run_id":          0,
  "seed":            0,
  "method":          "AEGIS",
  "timestamp":       "2026-06-16T14:23:11",
  "data_file":       "WH_estimation_uy.csv",
  "elapsed_s":       171.3,
  "final_gen":       2063,
  "final_state":     "completed",

  "r2_train":        0.999983,
  "r2_val":          null,
  "r2_test":         0.999976,
  "rmse_train":      0.000823,
  "rmse_val":        null,
  "rmse_test":       0.000891,
  "n_terms":         7,
  "max_delay":       9,
  "bic":             -51234.2,
  "aic":             -51289.7,

  "config": { "num_islands": 3, "population_size": 50, "max_generations": 5000, ... },

  "best_model": {
    "equation":          "y(k) = ...",
    "r2_train":          0.999983,
    "r2_test":           0.999976,
    "err_contributions": [
      { "label": "y(k-1)",    "err": 0.7823 },
      { "label": "y(k-2)",    "err": 0.1341 },
      ...
    ],
    "y_test_actual":    [0.012, 0.034, ...],
    "y_test_predicted": [0.011, 0.035, ...],
    ...
  },

  "tuning_log": [
    { "gen": 120, "param": "mutationFactor", "old": 0.5, "new": 0.7, "reason": "..." },
    ...
  ],

  "fitness_history": [
    [0,    0.4821],
    [1,    0.4713],
    [2,    0.4652],
    ...
    [2063, -0.4172]
  ]
}
```

### `summary.json` — Resumo de todas as execuções

```json
{
  "aegis_version": "1.0.0",
  "method":        "AEGIS",
  "timestamp":     "2026-06-16T15:10:00",
  "data_file":     "WH_estimation_uy.csv",
  "num_runs":      10,
  "ok_runs":       10,
  "seed_start":    0,
  "max_gen":       5000,
  "num_islands":   3,
  "pop_size":      50,
  "runs": [
    { "run_id": 0, "seed": 0, "elapsed_s": 171.3, "final_gen": 2063,
      "r2_train": 0.9999, "r2_val": null, "r2_test": 0.9999, ... },
    ...
  ]
}
```

### `comparison_table.json` — Tabela de comparação

```json
{
  "timestamp": "2026-06-16T16:00:00",
  "data_file": "WH_estimation_uy.csv",
  "num_runs":  10,
  "config":    { "n_y": 9, "n_u": 9, "max_degree": 2, "pop_size": 100, "max_gen": 5000 },
  "results": {
    "AEGIS": {
      "r2_test":   { "mean": 0.9999, "std": 0.0001, "min": 0.9994, "max": 0.9999, "n": 10 },
      "rmse_test": { "mean": 0.0013, "std": 0.0004, ... },
      "final_gen": { "mean": 2063.0, "std": 498.0,  ... },
      "elapsed_s": { "mean": 187.3,  "std": 24.1,   ... }
    },
    "DE-Classic": { ... },
    "JADE":       { ... },
    "GA":         { ... },
    "PSO":        { ... }
  }
}
```

---

## 10. Dicas e Resolução de Problemas

### Execuções muito lentas nos baselines

Os métodos baseline em Python puro são mais lentos que o núcleo C++ do AEGIS. Para testes rápidos:

```bash
# Reduzir gerações e população para validar o pipeline
python run_comparison.py --data data.csv \
    --runs 3 --max-gen 500 --pop-size 30
```

### `seaborn` não instalado

Os scripts funcionam sem `seaborn`, com estilo padrão do matplotlib. Para instalar:

```bash
pip install seaborn
```

### Campos nulos no JSON (r2_val = null)

Alguns campos podem ser `null` se o AEGIS não os reportar diretamente no `summary.json`. O `analyze_batch.py` ignora valores nulos ao calcular estatísticas (reporta `N/A`). Para ter todos os campos, use os `run_NN.json` individuais (que contêm `best_model` com mais detalhes).

### Fig 4 sem dados de série temporal

Para que `fig4_predicted_vs_actual` mostre a sobreposição real vs previsto, o AEGIS precisa incluir `y_test_actual` e `y_test_predicted` no JSON exportado. Na tela **Results** do AEGIS, clique em **Exportar JSON** após a identificação — o arquivo exportado contém esses campos completos.

### Reprodutibilidade

Todos os métodos aceitam `--seed-start` / `seed=`. Para reproduzir exatamente os mesmos resultados:
- **AEGIS:** use `--seed-start 0` no `aegis_batch.exe`
- **Baselines:** use `--seed-start 0` no `run_comparison.py`

> O AEGIS usa sementes internas no C++ (propagadas via campo `random_seed` no JSON de configuração). A reprodutibilidade exata depende do compilador e plataforma.

### Importar `narx_utils` de outro diretório

Se executar os scripts de fora da pasta `python/`:

```bash
cd python/
python analyze_batch.py --results ../results/aegis_wh/
```

Ou adicionar ao PYTHONPATH:

```bash
set PYTHONPATH=C:\SourceCode\AEGIS\python   # Windows
python analyze_batch.py --results results/aegis_wh/
```

---

## Referências dos métodos implementados

1. **Storn, R. & Price, K.** (1997). Differential Evolution — A Simple and Efficient Heuristic for Global Optimization. *J. Global Optimization*, 11(4), 341–359.

2. **Zhang, J. & Sanderson, A. C.** (2009). JADE: Adaptive Differential Evolution with Optional External Archive. *IEEE Trans. Evolutionary Computation*, 13(5), 945–958.

3. **Goldberg, D. E.** (1989). *Genetic Algorithms in Search, Optimization and Machine Learning*. Addison-Wesley.

4. **Kennedy, J. & Eberhart, R. C.** (1997). A discrete binary version of the particle swarm algorithm. *Proc. IEEE SMC*, 4104–4108.

5. **Billings, S. A.** (2013). *Nonlinear System Identification: NARMAX Methods*. Wiley.

---

<div align="center">

*AEGIS Python Pipeline — parte do projeto AEGIS v2.1*

*Para dúvidas sobre o método, consulte `assets/avaliacao_cientifica.md`*

</div>
