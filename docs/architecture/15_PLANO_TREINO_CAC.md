# 15 — Plano empírico de treino do CAC

Data: 2026-11-26. Pedido do usuário: "planeje vários testes para treinar o CAC
para ele entender melhor como usar os 16 parâmetros, o que cada um impacta e
quando é melhor agir em cada um, mas de forma empírica".

Contexto: [14_CONTROLADOR_ADAPTATIVO.md](14_CONTROLADOR_ADAPTATIVO.md) (v1–v3).
A v3 melhorou a validação do campeão em 3 sementes do CT, mas o
conhecimento que ela usa (prior fuzzy, tamanho dos passos, horizonte) ainda é
escrito à mão. Este plano substitui esse conhecimento por **medições
causais**.

## 0. Regras do programa

- **Só treino e validação.** Nenhum arquivo de teste é aberto. O CT usa a
  divisão do E3 (`testStartRow` = 1024).
- **Sementes de treino 41–80**, separadas das de desenvolvimento (21–40) e
  das do A1 (1–10). O que se aprende aqui nunca é avaliado nas mesmas
  sementes.
- **Pacote base:** o do A1 (`run_a1.sh`), com o CAC desligado. É sobre ele
  que o CAC vai agir.
- **Carga:** até 6 processos, BelowNormal, e só depois que o A1 terminar.
- Cada estágio tem um script, um arquivo de resultados fora do git e um
  resumo no git.

## 1. Os 16 parâmetros e o que se espera medir

| # | Parâmetro | Mecanismo | Hipótese a testar |
|---|---|---|---|
| 1 | `mutationFactor` (F) | tamanho do passo diferencial | ↑ ajuda em estagnação com baixa taxa de sucesso; ↓ ajuda no refino tardio |
| 2 | `crossoverRate` (CR) | fração herdada do mutante | ↓ dá passos menores; efeito na diversidade estrutural |
| 3 | `migrationRate` | fração migrada entre ilhas | ↑ ajuda ilhas diversas e paradas |
| 4 | `migrationInterval` | gerações entre migrações | interage com o 3 |
| 5 | `reinitializationRatio` | imigrantes aleatórios | ↑ ajuda diversidade colapsada |
| 6 | `structuralMutationRate` | inserir, remover e trocar regressores | efeito no K e na exploração de estruturas |
| 7 | `stagnationLimit` | critério de parada (orçamento) | só com `allowBudgetActions`; mede o efeito de parar antes |
| 8 | `complexityPenalty` (γ) | custo por fator | **dano irreversível já observado** (v2); medir a dose segura |
| 9 | `noInputPenalty` (ζ) | piso de contribuição da entrada | efeito em modelos só autorregressivos |
| 10 | `freeRunPenalty` (θ) | peso do erro livre (modo `one_step`) | **inerte** no A1 (`simulation`): serve de **placebo** |
| 11 | `freeRunHorizon` | horizonte do erro livre | inerte no A1; segundo placebo, mas reavalia as populações |
| 12 | `denominatorPenalty` (β) | custo do denominador | efeito na fração racional e na admissibilidade |
| 13 | `stabilityPenalty` (η) | custo de divergência | efeito na admissibilidade |
| 14 | `exponentPenalty` (δ) | custo de expoentes altos | efeito nos expoentes reais |
| 15 | `alpha` | peso do BIC | parcimônia por verossimilhança |
| 16 | `triggerRestart` | reinício parcial ou cataclismo | quando o cataclismo ajuda (convergência prematura) e quando destrói |

## 2. Desenho central: ramificação determinística

O AEGIS é determinístico por semente, e as ações são aplicadas entre
gerações. Para uma semente s e uma geração g:
- **ramo controle:** a execução sem nenhuma ação, a mesma para todas as
  intervenções da semente;
- **ramo intervenção:** a mesma execução, idêntica até g, com **uma** ação
  aplicada em g.

O efeito da ação é a diferença entre os ramos nas gerações g + 25, 50, 100 e
200 e no fim da execução. Isso dá o horizonte em que o efeito aparece e o
efeito de longo prazo (o dano irreversível do γ só aparece no longo
prazo).

**Ruído caótico:** qualquer perturbação muda a trajetória depois de g. Para
separar efeito de caos, usam-se **placebos**:
- `freeRunPenalty` e `freeRunHorizon` mudados no A1, onde não entram no
  fitness;
- um reinício de 5 %, a menor dose.

O efeito de um parâmetro só conta quando supera a distribuição dos
placebos.

**Implementação:** um agente roteirizado no `run_agent_experiment.dart`,
`--agent script:<param>=<valor>@<geração>`, que aplica a ação exatamente em
g e registra o snapshot naquele instante (as variáveis da situação). O ramo
controle é a execução com `--agent none`. **Conferência obrigatória antes
de tudo:** o roteiro com uma ação marcada para depois do fim da execução
deve reproduzir o controle bit a bit.

## 3. Estágios

### T0: conferências (≈ 15 min)
- Reprodução bit a bit do controle pelo agente roteirizado sem ação.
- Ramificação: o ramo intervenção é idêntico ao controle até g.

### T1: mapa de impacto (CT, a parte principal)
- **Sementes:** 41–50.
- **Momentos g:** 50 (fase 1, exploração), 150 (fase 2), 400 e 1000
  (fase 3, refino). Cobrem as situações típicas.
- **Ações:** para cada um dos 14 parâmetros contínuos, ±½ passo máximo
  (pesos: ±1/10, a escala da v3, e ±½ para medir o dano); `triggerRestart`
  com 0,3 e 1,0 (cataclismo); 4 placebos.
- **Tamanho:** ≈ 36 ações × 4 momentos × 10 sementes ≈ 1 440 ramos, mais 10
  controles.
- **Custo:** ≈ 1,5 min por ramo; com 6 processos, ≈ 6 h.
- **Saída:** por ramo, Δ log RMSE de validação do campeão em cada horizonte,
  ΔK, admissibilidade, diversidade, fase e as variáveis fuzzy em g.

### T2: dose e momento (CT)
- Para os 5–6 parâmetros com maior efeito no T1, doses de ¼, ½ e 1 passo
  máximo.
- O momento em mais pontos (25, 50, 100, 150, 250, 400, 700, 1000, 1500),
  para medir **quando** cada ação compensa.
- Sementes 51–60. ≈ 6 parâmetros × 2 direções × 3 doses × 9 momentos × 10
  ≈ 3 240 ramos. Para caber, roda-se até g + 300, salvo para os pesos, que
  vão até o fim. ≈ 8–10 h.

### T3: transferência para WH e SB (orçamento reduzido)
- As 10–12 ações mais informativas do T1/T2, em 3 momentos, com sementes
  61–65 e 3×10⁴ avaliações (≈ 200 gerações, ≈ 6 min por ramo com P2′a).
- ≈ 12 × 3 × 5 × 2 benchmarks ≈ 360 ramos, ≈ 6 h.
- Mede se o mapa do CT vale para sistemas com 16 000 amostras de treino.

### T4: modelo de impacto e CAC v4
- Ajustar, para cada braço, o efeito esperado e a incerteza **por
  situação** (as variáveis fuzzy no instante g) e por horizonte, com um
  modelo simples e interpretável: árvore rasa ou regras extraídas, com
  validação cruzada por semente.
- Substituir no CAC:
  - o **prior fuzzy escrito à mão** pelo efeito medido;
  - o **passo** pela dose segura do T2;
  - o **horizonte h** pelo atraso medido até o efeito aparecer, por
    parâmetro.
- Resultado: uma tabela publicada ("parâmetro → quando ajuda, quanto,
  depois de quantas gerações"), que também responde à pergunta científica.

### T5: validação do CAC v4 (desenvolvimento)
- CT, sementes 21–30, e WH/SB com orçamento completo, sementes 31–35, contra
  o A1 sem agente. Só validação.
- Se melhorar de modo consistente, o CAC ganha **pré-registro próprio**
  contra o A1, nas sementes 1–10, com teste.

## 4. Ordem e tempo

| Estágio | Quando | Tempo de máquina |
|---|---|---|
| T0 | assim que o A1 terminar | 15 min |
| T1 | em seguida | ≈ 6 h |
| T2 | depois do T1 | ≈ 8–10 h |
| T3 | depois do T2 | ≈ 6 h |
| T4 | análise | — |
| T5 | depois do T4 | ≈ 6 h |

## 5. Riscos

- **Caos domina:** se os placebos tiverem efeito do mesmo tamanho das ações,
  o mapa fica pouco informativo, e isso já é um resultado (os ajustes finos
  não importam). Mitigação: mais sementes por célula.
- **Situações raras:** algumas combinações de variáveis aparecem pouco. O
  modelo do T4 agrega por variável, não por combinação.
- **Interação entre ações:** o T1 mede ações isoladas. A interação fica para
  o T5, no uso real.
- **Generalização:** o CT tem validação curta. O T3 testa se o mapa vale
  para WH e SB.

## 6. T0 executado (2026-11-26)

CT, semente 41, pacote A1, validação:
- `--agent script:mutationFactor=0.65@99999` (ação depois do fim) contra
  `--agent none`: modelo e histórico inteiro **idênticos**;
- `--agent script:mutationFactor=0.65@150`: histórico idêntico ao controle
  até a geração 150 e diferente a partir da 151, quando a ação é aplicada.

A ramificação determinística funciona como desenhado.

## 7. Medida principal e preparação do T1 (2026-11-26)

- **Medida principal do T1–T3:** RMSE normalizado de simulação livre na
  validação do **campeão no fim da busca** (último ponto do histórico,
  `freeRunValFull`), antes de qualquer pós-processamento. Medidas também nos
  horizontes g + 25, 50, 100 e 200, pelo histórico.
- **Motivo:** no desenvolvimento do CAC v3 (CT, sementes 21–30), o
  pós-processamento (poda e refino P6) tem variância grande e pode inverter o
  efeito da busca (diário, 2026-11-26). A medida pós-processamento é
  reportada como secundária.
- **Agente roteirizado:**
  - aceita ações relativas ao valor vigente em g (`param+=passo@g`), com
    corte na faixa do esquema;
  - registra a situação (variáveis fuzzy, fase, K, validação) no instante da
    ação.
- **Script:** `experiments/cac/run_t1.sh`, que pode ser retomado.
  - 36 braços × 4 momentos × 10 sementes + 10 controles = 1 450 execuções;
  - `allowBudgetActions` = true em todas, inclusive no controle, para
    estudar `stagnationLimit`;
  - build de desenvolvimento `cpp/build_dev`.
- **Execução:** começa quando o A1 terminar.

## 8. Resultado do T1 (CT, validação; 2026-11-26)

1 450 execuções (36 braços × 4 momentos × 10 sementes + 10 controles).
Resultado completo: `experiments/cac/T1_RESULTS.md`.

**Integridade:**
- 10 execuções da semente 43 em g = 400 falharam por travamento da máquina
  virtual do Dart, ao compilar o executor (provável falta de memória com 6
  VMs em 7,4 GB). Não é falha do AEGIS.
- Uma delas deixou um `run_*.json` vazio, guardado como `.broken`.
- Todas foram refeitas e completadas.

**Ruído caótico (placebos, fim da busca):** log-razão entre p5 = −0,235 e
p95 = +0,451 (≈ −21 % a +57 % no RMSE), com mediana |d| = 0,068.
Perturbar a trajetória já muda bastante o campeão final no CT.

**Achados** (d = log RMSE do ramo / controle no fim da busca; negativo =
melhor):

| Parâmetro | Efeito medido | Leitura |
|---|---|---|
| `complexityPenalty` γ ↑ | **+0,09 a +0,60**; dose grande fora da faixa de ruído (pior) em 6–8 de 10; K −24 a −26 em todos os momentos | **Prejudicial sempre**, e o dano é proporcional à dose. Confirma causalmente o mecanismo que derrubou o CAC v2 |
| `denominatorPenalty` β ↑ | **−0,07 a −0,20**, 7–9 de 10 melhores; também melhor depois do pós-processamento (−0,05 a −0,16) | **O efeito benéfico mais consistente** no CT: menos denominadores generalizam melhor na validação curta |
| `exponentPenalty` δ ↑ | −0,03 a −0,23 no fim da busca (K −22), mas **pior depois do pós-processamento** (+0,2 a +0,6) | Discordância entre a validação da busca e a reportada (convenções diferentes, ver diário) |
| `alpha` (BIC) ↑ | −0,10 a −0,16 em g = 50–150; nulo depois | Ajuda cedo, com K −16 |
| `noInputPenalty` ζ | idêntico aos placebos | **Inerte:** os pisos de ζ do currículo (0,8–1,5) ficam acima dos valores testados (base 0,5 ± 0,5) |
| `stabilityPenalty` η | dentro da faixa de ruído | Sem efeito mensurável (o veto já garante admissibilidade) |
| Operadores do DE (F, CR, migração, imigrantes, mutação estrutural) | dentro da faixa de ruído; em g ≥ 150 o campeão quase não muda | **Efeito desprezível** no pacote A1 |
| `triggerRestart` (30 %, cataclismo) | dentro da faixa de ruído | Sem efeito mensurável no CT |
| `stagnationLimit` | nulo (as execuções param pelo orçamento) | Inerte com orçamento fixo |

**Ressalvas:**
- O CT sobreajusta a validação curta. Por isso as penalidades de
  parcimônia ajudam aqui, quando no WH e no SB foi justamente zerá-las que
  deu o ganho (E3, A1). **O mapa depende do sistema**, e o T3 (WH/SB) é
  indispensável.
- São 144 braços × momentos; sem correção para múltiplas comparações, os
  efeitos isolados pequenos podem ser acaso.

**Consequências para o CAC:**
- retirar ou mascarar os parâmetros inertes no contexto (ζ abaixo do piso,
  `stagnationLimit` com orçamento fixo);
- tratar γ ↑ como ação proibida no pacote sem penalidades;
- o efeito útil está nos **pesos** (β, α, δ), e com sinal que depende do
  sistema;
- os operadores do DE quase não importam.
- **T2 replanejado:** dose e momento para β, α e δ (e γ como controle de
  dano), no CT e já no WH, junto com o T3.

## 9. T2+T3: dose e momento dos pesos, no CT, WH e SB (registrado antes de rodar)

Script: `experiments/cac/run_t2.sh <benchmark>`. Só validação, pacote A1,
build `cpp/build_dev`, 5 processos (os travamentos de memória do Dart no T1
ocorreram com 6).

| | CT | WH | SB |
|---|---|---|---|
| Orçamento | 3×10⁵ | 3×10⁴ | 3×10⁴ |
| Sementes | 51–60 | 61–65 | 61–65 |
| Momentos g | 25, 100, 400, 1200 | 10, 25, 60, 150 | 10, 25, 60, 150 |

**Braços:**
- β: +0,025, +0,05 e +0,25;
- α: +0,05 e +0,25;
- δ: +0,02 e +0,1;
- γ: +0,002 e +0,005 (doses mínimas, controle de dano);
- placebo: θ + 0,5.

**Medida principal:** campeão no fim da busca (como no T1).

**Pergunta:**
- o sinal do efeito de β, α e δ é o mesmo no CT, no WH e no SB?
- a partir de que momento o efeito deixa de existir?
- existe dose de γ que não prejudica?

## 10. Resultado do T2+T3 (validação; 2026-11-27)

Saídas: `experiments/cac/T2_cascaded_tanks.md`, `T2_wiener_hammerstein.md`,
`T2_silverbox.md` (gerados por `tool/experiments/cac_t1_analysis.dart`).

**Integridade:**
- 820 de 820 execuções completas: CT 410, WH 205, SB 205.
- Nenhum travamento do Dart com 5 processos; nenhuma ação rejeitada.
- Término: CT 2026-11-26 21:55, WH 2026-11-27 00:20, SB 02:55.
- No WH e no SB, o orçamento de 3×10⁴ dá ≈ 196 gerações. Logo, o momento
  g = 150 está perto do fim da busca.

**Faixa de ruído (placebo θ, fim da busca, p5 a p95, log):**

| CT | WH | SB |
|---|---|---|
| −0,409 a +0,252 | −0,099 a +0,039 | −0,025 a +0,107 |

**Efeito no fim da busca (mediana do log da razão; negativo = melhor):**

| Braço | CT | WH | SB |
|---|---|---|---|
| β +0,025 / +0,05 / +0,25 | −0,29 a +0,03; dentro do ruído, exceto 9/10 melhores em 3 de 12 casos | **+0,07 a +0,35**, pior em todas as sementes e momentos | **+0,05 a +0,78**, pior na maioria; o pior momento é g = 150 |
| α +0,05 / +0,25 | −0,24 a 0; 9/10 melhores só em α +0,05 @25 | −0,08 a +0,02 (ruído) | −0,17 a +0,10; 4/5 melhores em α +0,25 @60 e @150 (p = 0,375) |
| δ +0,02 / +0,1 | −0,28 a −0,07; 9/10 melhores só em δ +0,02 @1200 | **+0,44 a +0,86**, 5/5 piores | **+1,19 a +1,67**, 5/5 piores |
| γ +0,002 / +0,005 | −0,22 a +0,03 (ruído) | **+0,36 a +0,85**, 5/5 piores | **+1,02 a +1,43**, 5/5 piores |

- **WH e SB:** δ e γ pioram em 5/5 sementes, em todos os momentos e já na
  menor dose, sempre fora da faixa de ruído. Com 5 pares, p = 0,063 é o menor
  valor possível do teste do sinal.
  - O efeito cresce com a dose.
  - K cai de 11 a 31 regressores.
  - A métrica final pós-processada tem o mesmo sinal.
  - β também piora, com efeito menor.
- **CT:** quase todas as medianas são negativas, mas a faixa de ruído é
  larga. Só 5 de 36 braços têm 9/10 sementes melhores (p = 0,021, sem
  correção para comparações múltiplas).
- **CT, métrica final pós-processada:**
  - α melhora em todos os momentos (−0,06 a −0,43);
  - β melhora quando aplicado em g = 400 ou 1200 (−0,16 a −0,42);
  - δ e γ pioram (+0,03 a +0,33), como no T1.
- **Transiente no CT:** β e δ pioram nas primeiras 25–50 gerações após a ação
  e só depois melhoram. Logo, o horizonte para julgar uma ação de peso
  precisa ser de ≈ 200 gerações.
- **γ no CT:** nas doses mínimas, γ não piora o fim da busca (dentro do
  ruído), ao contrário das doses maiores do T1. Ainda assim, piora a métrica
  final.

**Respostas às perguntas da §9:**
1. **O sinal não é o mesmo nos três sistemas.**
   - β, δ e γ (penalidades que reduzem K) ajudam ou são neutros no CT, que
     tem 819 amostras de treino e sobreajusta.
   - Os mesmos braços prejudicam claramente no WH e no SB, que têm 20 000
     amostras e precisam de capacidade. Isso é coerente com o E3, onde
     penalidades zero foram o melhor pacote no WH e no SB.
   - α é o único peso sem dano claro em nenhum dos três.
2. **Momento:**
   - no WH e no SB não há momento seguro para subir β, δ ou γ;
   - no CT, β tardio (g ≥ 400) é o único que melhora também a métrica final.
3. **Não existe dose de γ inofensiva no WH e no SB:** +0,002 já piora 5/5.

**Consequências para o CAC v4 (T4):**
- β, δ e γ não podem ser subidos por padrão. Subir esses pesos exige um
  sinal medido de sobreajuste, por exemplo:
  - a diferença entre o erro de treino e o de validação em simulação livre;
  - o número de amostras por parâmetro.
- Sem esse sinal, o CAC deve manter os pesos e agir nos outros parâmetros.
- α pode ficar como braço permitido, com passo pequeno.
- O horizonte mínimo após uma ação de peso deve ser de ≈ 200 gerações no CT.

**Limitações:**
- No WH e no SB: 5 sementes e orçamento reduzido (3×10⁴, contra 1,5×10⁵ do
  A1).
- Sem correção para comparações múltiplas.
- Só validação; nenhum dado de teste foi lido.

## 11. T4: modelo de impacto e CAC v4; desenho do T5 (registrado antes de rodar; 2026-11-27)

### 11.1 Sinal de sobreajuste

Saída: `experiments/cac/T4_FEATURES.md`, gerada por
`tool/experiments/cac_t4_features.dart`.
- **Dados:** 800 ramos de peso (β, δ, γ ↑) do T1 e do T2+T3. Os atributos
  são lidos no controle da mesma semente, na geração da ação.

**Atributo escolhido: gapOS = log(RMSE de validação / RMSE de treino), um
passo à frente, do campeão.**

| | CT | WH | SB |
|---|---|---|---|
| gapOS, p10 / p50 / p90 | 0,23 / 0,40 / 0,76 | −0,01 / 0,02 / 0,04 | −0,10 / −0,05 / −0,03 |
| Ramos de peso que ajudam | 321 de 520 | 2 de 140 | 17 de 140 |

**Validação cruzada deixando um sistema de fora:**
- **gapOS:** o limiar escolhido nos outros dois sistemas não autoriza
  nenhuma subida no WH (0/140) nem no SB (0/140).
- **Amostras por regressor:** separa igualmente bem, mas é uma propriedade
  fixa dos dados, não um sinal medido durante a busca.
- **Atributos descartados:**
  - o gap em simulação livre autorizaria 77 de 140 ramos no WH, com perda
    (o WH tem erro livre alto sem sobreajuste);
  - o número de regressores perde no WH e no SB.
- **Deixando o CT de fora:** a validação cruzada não se aplica, porque nos
  outros dois sistemas subir peso nunca ajuda. A regra aprendida ali é
  "nunca subir".

**Dentro do CT (tercis de gapOS):**
- β ajuda em todos os tercis (≈ 72 %);
- δ ajuda mais quanto maior o gap;
- γ é prejudicial, ou neutro só no tercil mais alto.

**Limiar do portão: gapOS ≥ 0,15**, na mediana das últimas 10 gerações.
- Fica entre os dois grupos: p90 do WH/SB = 0,04; p10 do CT = 0,23.
- É conservador. Com só três sistemas, o limiar é uma escolha entre
  grupos, não uma estimativa fina.

### 11.2 CAC v4 (`version: 4`, agente `cac4`)

Mapa de impacto medido (`cacImpactMapV4` em
`lib/services/convergence_controller.dart`). Ele substitui o prior fuzzy
escrito à mão; o v3 segue disponível para reprodução.

| Ação | Regra | Prior | Horizonte mínimo | Evidência |
|---|---|---|---|---|
| β ↑ (`denominatorPenalty`) | só com o portão aberto | +0,3 | 200 | T1, T2: CT melhor; WH/SB pior 5/5 |
| α ↑ | permitida | +0,2 com portão, 0 sem | 200 | CT melhor (busca e final); WH/SB ruído |
| δ ↑ | bloqueada | — | — | WH/SB muito pior; CT piora a métrica final |
| γ ↑ | bloqueada | — | — | dano em todos os sistemas e doses |
| ζ | mascarada | — | — | inerte (pisos do currículo) |
| θ, horizonte livre | mascarados em simulação | — | — | placebos |
| η, operadores do DE, reinício e cataclismo | permitidos | −0,05 | — | dentro do ruído |
| Descida de peso e retorno à âncora | permitidos | âncora +0,1 | 200 | sem medida própria |

- Os passos seguem os do v3: um décimo do passo máximo para os pesos, o que
  dá β e α + 0,05 (doses medidas no T2). Para os operadores do DE, o passo
  é metade do passo máximo.
- Todos os parâmetros do sistema continuam no espaço de ações. Os
  bloqueios e máscaras vêm do mapa medido, e a amostragem de Thompson pode
  reabilitar um braço permitido se a experiência mostrar ganho.
- Testes: `test/convergence_controller_test.dart`. Há 4 testes novos do v4,
  e a suíte completa passa (43 de 43).

### 11.3 Desenho do T5

Script: `experiments/cac/run_t5.sh <benchmark>`. Análise, congelada antes
das execuções: `tool/experiments/cac_t5_analysis.dart`.
- **Braços:** pacote A1 sem agente (`none`), CAC v3 (`cac`) e CAC v4
  (`cac4`). Ambos os CAC começam sem tabela treinada.
- **Sementes e orçamento:**

| | CT | WH | SB |
|---|---|---|---|
| Sementes | 21–30 | 31–35 | 31–35 |
| Orçamento | 3×10⁵ | 1,5×10⁵ (igual ao A1) | 1,5×10⁵ (igual ao A1) |

- Só validação, build `cpp/build_dev`, 5 processos.
- As sementes 21–23 do CT já foram usadas na avaliação do v3 em
  desenvolvimento (doc 14). Isso não afeta o v4, cujo mapa vem só do T1–T3
  (sementes 41–65).
- **Medidas:**
  - principal: campeão de validação no fim da busca;
  - secundária: validação final reportada.
  - Para cada sistema: mediana de d = log(agente / sem agente),
    melhores/piores e teste do sinal.
- **Critério para o v4 ganhar pré-registro próprio contra o A1:**
  1. mediana de d < 0 no CT na medida principal;
  2. no WH e no SB, nenhum dano: mediana de d ≤ +0,02 e no máximo 2 de 5
     sementes piores;
  3. não ser pior que o v3 na mediana em nenhum sistema.
  - Com 5 sementes, o WH e o SB não permitem significância; o critério
    nesses dois é de não-dano.
