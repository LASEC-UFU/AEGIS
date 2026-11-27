# 16. Reguladores completos: o controlador alcança toda a configuração

Data: 2026-11-27. Branch `audit/aegis-1.1.0-wip`.

## 1. Motivação

**Pedido do usuário** (2026-11-27): "o regulador tem que poder ter acesso a
tudo o tipo de configuração que a ferramenta dispõe tipo maxRegressors,
maxDelay, pmax, maxTermsPerReg, denominatorProbability, tamanho da população
tudo isso pode ser ajustado no regulador … e todas as outras que tiver e se
precisar criar mais também, quanto mais melhor".

**Diagnóstico que levou a isso:**
- **Os 16 reguladores atuais não alcançam a capacidade.** Os 16
  parâmetros da ação (doc 15 §1) são todos de dinâmica da busca ou pesos de
  penalidade.
- **WH e SB estão limitados pela capacidade.**
  - No WH, o campeão atinge o teto de 39 regressores nas 5 sementes do T5,
    sem sobreajuste (gap ≈ 0). No SB, 4 de 5 sementes chegam a 39.
  - Nesses sistemas, o controlador só podia perturbar a trajetória, e isso
    piorou o resultado (T5, doc 15 §12).
- **O teto nunca passou de 40.** O núcleo travava `maxRegressors` em 40
  (trava de sanidade, sem estrutura de dados dependente). O teto de 39 do
  E3 estava encostado nessa trava; a trava agora é 200.

## 2. Princípio

Todo parâmetro que muda **a busca ou a classe de modelos** vira regulador.
Ficam de fora apenas os que tornariam a comparação inválida:

| Fora do controlador | Motivo |
|---|---|
| `trainRatio`, `validationRatio`, `trainEndRow`, `valEndRow`, `testStartRow`, `testTransient` | mudar a divisão dos dados vazaria validação ou teste para a busca |
| `outputCol`, `normalizerType` | mudam os dados e a escala do erro; as medidas deixam de ser comparáveis |
| `randomSeed`, `numThreads` | não são escolhas de identificação |
| `maxEvaluations`, `maxGenerations` | orçamento: a comparação entre braços exige o mesmo |
| `exponentStep` acima de 0,5, `powerMode` | removeriam os expoentes reais, que são a identidade da arquitetura. Passos menores (grade mais fina) são permitidos |

`stagnationLimit` continua bloqueado por `allowBudgetActions`, como antes.

## 3. Novos reguladores

### 3.1 Capacidade e classe de modelos (`kind: "structure"`)

| Parâmetro | Faixa | Efeito ao apertar |
|---|---|---|
| `maxRegressors` | 1–200 | indivíduos acima do limite são reparados (mantém os K primeiros após canonicalizar) e reavaliados |
| `maxTermsPerReg` | 1–6 | regressores com mais fatores são reparados |
| `maxDelay` | 1 até o teto de lançamento | atrasos acima são saturados |
| `pmax` | pmin–10 | expoentes reprojetados na grade |
| `pmin` | 0,1–pmax | idem |
| `exponentStep` | 0,1–0,5 | só grade igual ou mais fina; reprojeta os expoentes |
| `denominatorProbability` | 0–1 | em 0, os denominadores são removidos |

**Teto de atraso.** A linha comum de pontuação (`score_start`), o
aquecimento das ilhas e o contexto do pós-processamento dependem do atraso
máximo. Por isso o regulador de atraso é limitado por um teto fixo no
lançamento:
- `maxDelay` (configuração) passa a ser esse teto;
- a nova chave `maxDelayStart` (padrão = `maxDelay`) é o valor inicial do
  regulador.
- Com `maxDelayStart` = `maxDelay`, o comportamento é idêntico ao
  anterior.

### 3.2 Busca (`kind: "search"`)

| Parâmetro | Faixa |
|---|---|
| `populationSize` | 4–1000 (cresce com indivíduos aleatórios avaliados; encolhe removendo os piores, nunca a elite) |
| `elitismCount` | 0 até a população − 1 |
| `variableMutationRate` | 0–1 |
| `jadeC` | 0–1 |
| `jadeP` | 0,01–1 |
| `reinitInterval` | 1–500 |
| `hypermutation` | 0/1 |
| `mutationStrategy` | 0 = JADE, 1 = rand/1 |
| `fitMethod` | 0 = QR, 1 = normal (P2′a) |
| `admissibilityVeto` | 0/1 |
| `vetoTopK` | 1–50 |

### 3.3 Objetivo e currículo (`kind: "objective"`)

| Parâmetro | Faixa |
|---|---|
| `errorMode` | 0 = um passo, 1 = simulação; reavalia a população inteira |
| `inputContributionMin` | 0–1 |
| `phaseStagnationLimit` | 2–5000 |
| `islandRoles` | 0/1 |

### 3.4 Pós-processamento (`kind: "post"`; lido só na finalização)

`enablePruner`, `enableRefiner`, `finalRefine` (0/1, refino por simulação
P6) e `postProcessGuard` (0/1).

### 3.5 Eventos novos (`kind: "event"`)

| Evento | Valor | Ação |
|---|---|---|
| `advancePhase` | 1 | força o currículo a passar para a fase seguinte |
| `seedFromChampion` | 0,05–0,5 | troca essa fração dos piores de cada ilha por mutantes do campeão (intensificação) |
| `pruneChampion` | 1 | poda o campeão com o podador do pós-processamento e o injeta como migrante |
| `refineChampion` | 1–50 | refina o campeão por simulação (P6, até esse número de iterações) e o injeta como migrante |

## 4. Garantias

- **Sem ações, o resultado é bit-idêntico** ao build anterior, conferido
  com execuções iguais nos dois builds.
- As faixas e o passo máximo de cada regulador estão no esquema de ações.
  Os agentes (CAC, roteirizado, LLM) leem esse esquema, então todos passam a
  ver os novos reguladores.
- **O mapa de impacto dos novos reguladores ainda não foi medido.** Por
  isso:
  - o CAC v4.1 não os oferece enquanto não houver evidência;
  - o CAC v4 os oferece com prior levemente negativo.
  - Próximo estágio de treino (T7): medir o impacto desses reguladores no
    CT, no WH e no SB, com ramificação determinística como no T1.
