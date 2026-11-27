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

## 5. Ajuste de semântica: `pmax` e `maxDelay` (2026-11-27, antes de qualquer uso)

**Problema.** Na fase 0, o currículo reduz temporariamente o espaço de
busca: atraso a 50 % e `pmax` inicial. O regulador lia esse valor reduzido.
- Exemplo: um "+10" na fase 0 viraria 30, e a passagem para a fase 1
  fixaria o atraso em 30 em vez de 50.

**Correção.** O valor do regulador passa a ser o **alvo** do espaço de
busca:
- **na fase 0**, a ação muda só o alvo, que o currículo aplica ao entrar na
  fase 1. A exceção é um alvo mais apertado que a restrição atual, que vale
  na hora;
- **da fase 1 em diante**, a ação vale imediatamente.

**Verificação:**
- testes: core 96/96, API 92/92, phase0 11/11;
- bit-identidade sem ações contra o `build_dev` no CT conferida de novo:
  idêntico;
- teste rápido com o agente roteirizado (CT, semente 81, fora do T7):
  - 5 de 5 ações aceitas: teto 59 → 69, atraso 40 → 50, população
    50 → 100, semeadura pelo campeão e avanço de fase;
  - o campeão chegou a 41 regressores.

## 6. T7: mapa de impacto dos novos reguladores (registrado antes de rodar)

Script: `experiments/cac/run_t7.sh <benchmark>`. Análise:
`tool/experiments/cac_t1_analysis.dart` (a mesma do T1 a T3).

**Configuração comum:**
- ramificação determinística, como no T1: o braço é idêntico ao controle
  até a geração g, onde o agente roteirizado aplica a ação;
- só validação, build `cpp/build_cap`;
- pacote A1 com `postProcessGuard`;
- teto de atraso 60 com início em 40, em todos os braços, inclusive o
  controle.

| | CT | WH | SB |
|---|---|---|---|
| Sementes | 81–90 | 66–70 | 66–70 |
| Orçamento | 3×10⁵ | 6×10⁴ (≈ 400 gerações) | 6×10⁴ |
| Momentos g | 100 e 400 | 50 | 50 |

**Braços (23 ramificados):**

| Grupo | Braços |
|---|---|
| Capacidade | `maxRegressors` +10, +20 (duas ações com 25 gerações de intervalo) e −10; `maxTermsPerReg` +1; `maxDelay` +10 e +20; `pmax` ±1; `denominatorProbability` ±0,2 |
| Busca | população +50 e −25; elite +2; mutação de variável +0,2; JADE p +0,1; rand/1; hipermutação desligada; papéis das ilhas desligados |
| Objetivo e eventos | modo de erro um passo; semeadura pelo campeão (0,2); poda do campeão; avanço de fase |
| Placebo | θ + 0,5 (inerte em simulação) |

**Braços estáticos de capacidade** (sem agente, desde o início): teto 59 e
teto 79. Eles respondem diretamente se há folga de capacidade.

**Medidas:**
- principal: campeão de validação no fim da busca;
- também: validação final reportada e ΔK.

**Pergunta:**
- quais reguladores novos têm efeito fora da faixa de ruído do placebo, em
  qual sistema e em qual direção;
- em particular, se mais capacidade melhora o WH e o SB (gap ≈ 0) e piora o
  CT (gap alto).

**Custo:** CT 490 execuções, WH e SB 130 cada, com 5 processos, cerca de
12–14 h. Roda depois do T6.

**Correção (2026-11-27):** a primeira versão da tabela de eventos (§3.5)
listava um quarto evento, `refineChampion`, que nunca foi implementado no
núcleo. A linha foi removida. Os eventos novos são três (`advancePhase`,
`seedFromChampion`, `pruneChampion`), o que fecha a conta de 29 reguladores
novos (7 + 11 + 4 + 4 + 3).

## 7. Controlador em Dart: acesso ao conjunto completo (2026-11-27, depois do T6)

**`allRegulators`** é uma nova opção do CAC, com agentes `cac-all`,
`cac4-all` e `cac41-all` no runner. Padrão: desligada.

| | desligada (padrão) | ligada |
|---|---|---|
| Reguladores oferecidos | os 16 originais (DE, pesos, `triggerRestart`) | todos do esquema, exceto `post` |
| Valor atual | registro do Dart primeiro, depois o snapshot (como no T1 a T6) | snapshot do núcleo primeiro |
| Eventos novos | — | um braço cada (`seedFromChampion` com 0,2) |

- **Desligada:** v3, v4 e v4.1 ficam idênticos ao T1–T6 em qualquer build.
- **Valor atual com a opção ligada.** Corrige o defeito do registro: ele
  mantém padrões velhos, por exemplo γ 0,01 enquanto o A1 roda com 0, e teto
  de regressores 8.
- **Reguladores `post` nunca entram no bandit.** Só agem na finalização,
  então uma ação online não pode ser julgada pelo efeito.
- **Agente LLM:** a lista de parâmetros permitidos passa a incluir os
  reguladores novos (menos `post`), com as faixas do esquema do núcleo. O
  prompt descreve os reguladores de capacidade, de busca e os eventos.
- **Agente roteirizado** (usado no T7): já lia os valores do snapshot; não
  mudou.
- **Testes:** Flutter 48/48, com 3 testes novos (padrão desligado
  inalterado, conjunto completo com valores do núcleo, v4.1 continua
  oferecendo só braços medidos).
