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

## 8. Resultado do T7 (validação; 2026-11-28)

Execução completa: CT 490, WH 130 e SB 130 execuções, sem arquivos vazios
(`experiments/results_cac/t7_run.log`). Tabelas:
`experiments/cac/T7_{cascaded_tanks,wiener_hammerstein,silverbox}.md`.

**Faixa de ruído do placebo** (θ + 0,5, fim da busca):

| | p5 | p95 | mediana \|d\| | n |
|---|---|---|---|---|
| WH | 0,000 | 0,096 | 0,010 | 5 |
| SB | −0,124 | 0,229 | 0,012 | 5 |
| CT | −0,651 | 0,358 | 0,203 | 20 |

O CT é muito ruidoso: há valores finais de d de até +4, de modelos que
divergem na convenção reportada. As conclusões no CT são fracas.

**Efeitos claros** (fim da busca; entre parênteses, melhores / piores na
validação final reportada):

| braço | WH | SB | CT |
|---|---|---|---|
| teto 59 desde o início | −0,034, 5/5 (5/0) | −0,093 (3/2) | +0,060 (6/4) |
| teto 79 desde o início | −0,138, 5/5 (4/1), final −0,215 | −0,423 (4/1), final −0,246 | +0,008 (6/4), final −0,280 |
| população −25 (50 → 25) | −0,188, 5/5 (5/0) | −0,069 (4/1) | ≈ 0 (4/5 e 5/3) |
| população +50 | +0,245, 0/5 (0/5) | +0,443 (1/4) | −0,183 @100 (6/4) |
| rand/1 | +0,268, 0/5 (0/5) | +0,420 (1/4) | fim −0,145, final pior (3/6; @400 1/8) |
| `pmax` −1 | ≈ 0 (2/3) | +0,482, 0/5 (0/5) | ≈ 0 |
| modo de erro um passo | −0,032 (2/3) | +0,196 (2/3) | −0,273 @100, 9/10, p = 0,021 (6/4); @400 final pior (1/8) |

**Sem efeito em nenhum sistema** (d = 0 em todas as sementes):
`elitismCount` +2 e hipermutação desligada. Nesta configuração são inertes.

**Os demais**, dentro do ruído ou mistos: `maxRegressors` ±10/+20 durante a
busca, `maxTermsPerReg`, `maxDelay`, `denominatorProbability`, `jadeP`,
mutação de variável, papéis das ilhas, semeadura, poda e avanço de fase.

**Capacidade durante a busca contra desde o início.** Subir o teto durante
a busca quase não aumenta o modelo (WH: ΔK de 0 a 1), mas o teto alto desde
o início sim (+14 e +34).
- **Causa** (conferida no código, não é defeito): na inicialização, cada
  indivíduo sorteia de 1 até o teto regressores, então a população nasce
  grande.
- **Durante a busca**, o modelo só cresce por mutações que acrescentam um
  regressor por vez e precisam ser aceitas.
- **Consequência:** a folga de capacidade aproveitável vem da configuração
  inicial, não do regulador. Uma alternativa futura, não medida, é combinar
  o aumento do teto com reinício parcial.

**Leitura:**
1. **Capacidade.** O teto 39 do A1 limita o WH e o SB. Um teto maior desde
   o início melhora os dois na validação final. No CT o efeito é misto.
   Mudar o pacote é decisão do usuário (A2): fica como recomendação, sem
   abrir o teste.
2. **Controlador.** O regulador com ganho medido nos sistemas sem
   sobreajuste (portão fechado) é a população: −25 melhora o WH (5/0) e o
   SB (4/1); +50 piora os dois.
   - Bloqueados: rand/1 e `pmax` −1.
   - No CT nada é robusto na métrica final; a convenção de validação está
     sendo testada no T6b.

## 9. CAC v5 e desenho do T8 (registrado antes de rodar; 2026-11-28)

### 9.1 CAC v5 (agente `cac5`; `version: 5`, `measuredOnly`, `allRegulators`)

Mesma regra do v4.1 (só braços com ganho medido), agora com o mapa do T7
(`cacImpactMapV5`, que antecede o mapa v4):

| braço | regra | evidência (T7) |
|---|---|---|
| `populationSize` − (50 → 25) | `closedGate`, prior 0,3, horizonte 200 | WH 5/0 e SB 4/1 na métrica final; CT neutro |
| `populationSize` + | bloqueado | WH 0/5, SB 1/4 |
| `mutationStrategy` = rand/1 | bloqueado | WH 0/5, SB 1/4; CT final pior |
| `pmax` − | bloqueado | SB 0/5 |
| `elitismCount`, `hypermutation` | mascarados | d = 0 em todas as sementes |
| β↑, α↑ e demais | como no v4.1 | T1 a T5 |

**Regra nova `closedGate`:** o braço só é oferecido depois de uma janela
completa de gapOS (10 snapshots) abaixo do limiar 0,15, ou seja, com o
portão confirmado fechado.

**Só a dose medida:**
- o braço da população só aparece a partir da geração 50, que é o momento
  medido;
- nunca leva a população abaixo de 25, então é um disparo único.

**Testes:** Flutter, 4 testes novos:
- portão fechado: só a população;
- antes da geração 50 ou da janela completa: nada;
- sem segunda redução;
- portão aberto: só β↑ e α↑.

O código foi feito numa cópia de trabalho separada (`.wt/v5`), porque o T6b
roda o Dart a partir do código-fonte do diretório principal. Ele entra no
diretório principal, num commit, depois que o T6b terminar e antes do T8.

### 9.2 Desenho do T8

Script: `CTX=<0|1> experiments/cac/run_t8.sh <benchmark>`. Análise
congelada: `tool/experiments/cac_t8_analysis.dart`.

**Configuração comum:** build `cpp/build_sig`, pacote A1 com
`postProcessGuard`, só validação.

**Regra pré-registrada para `validationContext`:** fica ligado em todos os
braços (`CTX=1`) se e somente se o critério 1 do T6b (doc 15 §15.2) for
atendido.

| | CT | WH e SB |
|---|---|---|
| Sementes (novas) | 101–110 | 71–80 |
| Orçamento | 3×10⁵ | 6×10⁴ (o do T7, onde o efeito foi medido) |
| Braços | `none`, `cac5` | `none`, `cac5`, `STATIC_pop25` (referência: a dose do v5 desde o início) |

**Medida principal:** validação final reportada.

**Critério para o CAC v5** (`cac5` vs `none`, d = log da razão, pareado por
semente):
1. WH e SB, cada um: mediana de d < 0, com pelo menos 7 de 10 sementes
   melhores;
2. CT: não-dano, ou seja, mediana de d ≤ +0,02.

**Desfecho secundário:** `STATIC_pop25` vs `none`. Mostra se o ganho vem da
decisão online ou só da dose.

**Limitação declarada:** o mapa foi medido com orçamento de 6×10⁴ no WH e
no SB. O T8 testa nesse mesmo orçamento; generalizar para outros orçamentos
exige outro teste.

## 10. Resultados do T8 (2026-11-28)

**Execuções:** CTX=0, porque o critério 1 do T6b não foi atendido. Todas
completas e sem falhas: CT 20, WH 30, SB 30. Cada execução usou o
orçamento inteiro (por exemplo, CT 300 046 avaliações). O CT roda em
minutos porque a série é curta. Análise congelada:
`experiments/cac/T8_RESULTS.md`.

| sistema | comparação | mediana d final | melhores / piores (final) | mediana d fim | ações aceitas (mediana) |
|---|---|---|---|---|---|
| CT | cac5 vs none | −0,033 | 6 / 4 | −0,118 | 4 |
| WH | cac5 vs none | −0,072 | 8 / 2 | −0,027 | 1 |
| WH | STATIC_pop25 vs none | −0,214 | 9 / 1 | −0,183 | 0 |
| SB | cac5 vs none | −0,141 | 9 / 1 | −0,251 | 1 |
| SB | STATIC_pop25 vs none | −0,125 | 6 / 4 | −0,226 | 0 |

**Critério pré-registrado: ATENDIDO.**
- WH: mediana −0,072, com 8 de 10 sementes melhores.
- SB: mediana −0,141, com 9 de 10 sementes melhores.
- CT: mediana −0,033, dentro do limite de não-dano (≤ +0,02).

Pelo teste do sinal na métrica final, WH 8/2 dá p ≈ 0,11 e SB 9/1 dá
p ≈ 0,02.

**Leitura.**
- [artigo] É o primeiro critério de ganho do CAC atendido em sementes novas
  e registrado antes de rodar. O ganho vem de um único ajuste medido no T7,
  reduzir a população de 50 para 25, disparado só quando o controlador
  confirma que não há sobreajuste.
- O desfecho secundário mostra que a dose aplicada desde o início
  (`STATIC_pop25`) tem efeito parecido:
  - no WH, maior (−0,214);
  - no SB, um pouco menor e menos consistente (−0,125, 6 de 10).
- Portanto, a decisão online não é claramente melhor que a dose fixa. O
  valor do controlador está em decidir quando aplicá-la, com base no
  portão: no CT, onde há sobreajuste, ele não reduz a população.

**Limitações.**
- [limitação] O mapa e o teste usaram o mesmo orçamento de 6×10⁴ no WH e
  no SB, e n = 10.
- [limitação] O conjunto de teste continua fechado. Tudo aqui é validação.

## 11. Desenho do T9: generalização de orçamento (registrado antes de rodar; 2026-11-28)

Script: `CTX=0 experiments/cac/run_t9.sh <wiener_hammerstein|silverbox>`.
Análise congelada: o mesmo script do T8, apontado para outra pasta
(`dart run tool/experiments/cac_t8_analysis.dart experiments/results_cac/t9`).

**Pergunta:** o ganho do T8 se mantém com orçamento 2,5 vezes maior
(1,5×10⁵, o do T6b)?

| | WH e SB |
|---|---|
| Sementes (novas) | 81–90 |
| Orçamento | 1,5×10⁵ |
| Braços | `none`, `cac5`, `STATIC_pop25` |
| Configuração | a mesma do T8, com CTX=0 |

O CT fica de fora, porque o T8 já o testou com 3×10⁵.

**Critério (cac5 vs none, validação final):** no WH e no SB, cada um,
mediana de d < 0, com pelo menos 7 de 10 sementes melhores.

**Desfecho secundário:** `STATIC_pop25` vs `none`.

**Se falhar:** o ganho do v5 fica declarado como limitado ao orçamento
medido.
