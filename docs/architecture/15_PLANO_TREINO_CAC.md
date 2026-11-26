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
