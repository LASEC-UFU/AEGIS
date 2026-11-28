# Diário de pesquisa do AEGIS (base para o artigo)

**Finalidade:** registro cronológico de tudo o que foi feito, decidido,
medido, falhou ou desviou do plano, para servir de base à escrita do artigo
(`docs/paper/IFAC_JSC_PREPARACAO.md`). Pedido do usuário em 2026-11-26:
"vá registrando todas estas ações para servir depois de base para a escrita
do artigo".

**Como ler:**
- cada entrada traz a data, o que foi feito, o resultado com números e a
  fonte (commit e documento);
- **[artigo]** marca o que provavelmente entra no texto;
- **[limitação]** marca ressalvas que o texto precisa declarar.

**Regras de integridade, válidas em todas as entradas:**
- nenhum dado de teste é usado para escolher estrutura, parâmetro ou
  critério;
- WH e SB têm o teste fechado até o congelamento do A1;
- resultados desfavoráveis, falhas e desvios são registrados.

Registro técnico detalhado (em inglês): `experiments/EXPERIMENT_LOG.md`.

---

## 2026-11-21 — Continuação numa segunda máquina e fim do protocolo 1.1.0

- **Máquina:** Ryzen 5 PRO 5650G, 6 núcleos e 12 threads, 7,4 GB, Windows
  11. Binários congelados transferidos com SHA-256 conferido.
- **Reprodução entre máquinas:** CT `aegis_full`, semente 1: modelo,
  avaliações e validação idênticos bit a bit (RMSE livre de validação
  0,8320657852 V nas duas). **[artigo]** reprodutibilidade bit a bit entre
  máquinas.
- **Protocolo 1.1.0 completo:** WH e SB `legacy_head` terminados nesta
  máquina (10/10 cada). CT 14 condições, WH 10, SB 8; todas 10/10.
  - Falhas registradas: dois travamentos da máquina original (hardware), com
    reexecução.
  - Fontes: `37d6333`, `973b3b3`, `3f5d926`.

## 2026-11-21 a 23 — Fase 0, E3: triagem só por configuração

- **Desenho (pré-registrado):** 8 células = `maxRegressors` {8, 39} ×
  penalidades {padrão, zero} × `errorMode` {one_step, simulation}, sementes
  21–30, 240 execuções, só validação.
- **Critério:** zero+39 / padrão+8 ≤ 0,90 em ≥ 2 de 3 benchmarks.
- **Resultado:** atingido nos dois modos.

| Modo | CT | WH | SB |
|---|---|---|---|
| `one_step` | 1,22 ✗ | 0,56 ✓ | 0,12 ✓ |
| `simulation` | 0,52 ✓ | 0,28 ✓ | 0,13 ✓ |

- **Leituras [artigo]:**
  - com as penalidades padrão, o teto de regressores não é a restrição
    ativa (K de 4 a 7);
  - sem penalidades, o próprio AEGIS chega a 22–33 coeficientes e supera as
    estruturas fixas ajustadas por QR do E1 no WH (10,7 contra 26,5 mV) e no
    SB (0,34 contra 0,60 mV);
  - otimizar pela simulação livre foi melhor em 11 de 12 pares de células;
  - sem pressão, a busca usa extensivamente os expoentes reais (32–50 % dos
    fatores não inteiros) e a forma racional.
- **[limitação]** "penalidades zeradas" é um pacote, sem atribuição
  causal; uma divisão por benchmark; o CT tem 205 amostras de validação.
- **Custo:** as células grandes levaram cerca de 7 h por execução no WH.
- Fontes: `experiments/phase0/PHASE0_REPORT.md` §7; `e36aa9c`.

## 2026-11-23 — Propostas de arquitetura por estados (TDF-II) e auditorias

- **Diretriz do usuário:**
  - o objetivo é ganho de **velocidade e de arquitetura** mantendo os
    **expoentes reais** (a identidade do AEGIS);
  - embarcar código não é o objetivo.
- **Documentos:**
  - 08 (realização em estilo TDF-II, ponto fixo);
  - 09 (outro agente: estados transpostos);
  - 10 (auditoria do 09; proposta de ajuste por estatísticas deslocáveis);
  - 11 (outro agente: realização transposta adaptativa);
  - 12 (auditoria do 11).
- **Revisão externa da §10 do documento 10:**
  - acertou dois pontos: colunas do denominador (−y·φ) não são deslocáveis,
    porque N·D e D·D dependem de dois atrasos;
  - e o cache precisa ser medido antes de se prometer O(N·K).
- **Decisões:**
  - ordem P0 (medir) → P1 (exato) → P2′ (ajuste rápido) → P6 (refino por
    simulação);
  - a "Passada A" do 11 (gradiente em fluxo) foi descartada, porque perde
    para a solução exata em colunas mal condicionadas.
- Fontes: `3f84d2c`, `32e0369`, `adc1ee9`, `b783087`.

## 2026-11-24 — P0: onde o tempo é gasto (medido)

- Build instrumentado, idêntico bit a bit ao congelado (custo de 2 %).
- **Modelos grandes:**

| Parte da avaliação | Fração do tempo |
|---|---|
| Ajuste por QR | 26–35 % |
| ERR completo, que não entra no fitness | 25–27 % |
| ERR por grupo | 21–23 % |
| Montagem de Ψ | 15–19 % |
| Simulação livre | ≤ 2 % |
| Fora da avaliação | 0,5–3 % |

- **Cache de estatísticas deslocáveis (P2′b):** acerto simulado de 50–60 %,
  com 7,8–72 milhões de chaves. Inviável; **descartado com dados**.
- **[artigo]** a realização em estados para a simulação não acelera,
  porque o custo está no ajuste e no ERR.
- Fontes: `docs/architecture/13_P0_PROFILING.md`; `ba24dc3`.

## 2026-11-25 — P1: otimizações exatas

- **Mudanças:**
  - ERR completo só no avaliador canônico;
  - cache de séries de potência, com Ψ montada por linhas;
  - QR de Householder percorrendo a matriz por linhas.
- **Resultado:** idêntico bit a bit ao binário congelado em 7 de 7
  comparações (CT, WH, SB e modos `signed`/`legacy`); **1,8–2,6× mais
  rápido**.
- Fontes: `experiments/perf/PERF_REPORT.md`; `0af456d`.

## 2026-11-25 — P2′a: ajuste pelo Gram centrado (pré-registrado)

- **Mudança:** Gram centrado + Cholesky com descarte de colunas na ordem do
  QR, ERR por grupo no espaço K×K e *fallback* para Householder. Usado só
  nas ilhas; o campeão é sempre certificado pelo QR.
- **Auditoria por candidato:**
  - caminho rápido em 100 % dos candidatos (2 *fallbacks* em 60 015);
  - descarte de colunas idêntico ao do QR;
  - p99 de |ΔSSE|/SSE ≤ 4,7e−9.
- **Qualidade com sementes pareadas contra o E3 (critério de equivalência
  atingido):**

| | Razão do RMSE de validação | Campeões idênticos | Ganho de tempo |
|---|---|---|---|
| CT | 1,000 | 10 de 10 | 6,5× |
| WH | 1,010 | 5 de 10 | 14,5× |
| SB | 0,965 | 4 de 10 | 17,3× |

- **[artigo]** uma execução grande no WH cai de cerca de 7 h para cerca
  de 30 min, sem mudar a qualidade.
- **[limitação]** o paralelismo diferiu entre o E3 e o P2′a; os tempos
  são ordem de grandeza.
- **Desvio:** WH e SB foram reiniciados com paralelismo 3 minutos depois de
  começar, sem resultados.
- Fontes: `experiments/perf/P2A_PREREG.md` (`dba3e22`), `PERF_REPORT.md`.

## 2026-11-25 — P6: refino do campeão por erro de simulação (pré-registrado)

- **Método:** LM sobre o erro de simulação livre no treino, com
  sensibilidades exatas para modelos **racionais**, veto de admissibilidade
  e escolha da iteração na primeira metade da validação (V_A). A medida é a
  segunda metade (V_B).
- **Critério atingido em 2 de 3** (célula `mr39_zero_simulation`):

| | Mediana de V_B (refinado / original) | Antes → depois |
|---|---|---|
| WH | 0,873 | 11,0 → 9,5 mV |
| SB | 0,841 | 0,36 → 0,29 mV |
| CT | 1,000 | sem ganho |

- No WH e no SB, o refino melhorou 15 de 16 células e não piorou nenhuma.
- **Achado de estabilidade [artigo]:** 3 de 10 campeões da melhor célula do
  E3 no CT divergem em simulação livre **no treino**, embora sejam estáveis
  na validação. Motivou o veto checando também o treino.
- **Desvio:** um defeito da ferramenta (fator de entrada com expoente 0,5 em
  x = 0 marcado como não diferenciável) foi corrigido antes de ver
  resultados de refino; a execução foi refeita do zero.
- Fontes: `experiments/p6/P6_PREREG.md` (`01d62e6`), `P6_REPORT.md`
  (`26ed134`).

## 2026-11-26 — Núcleo: P1 e P2′a aplicados; veto (M9) e refino final

- **P1 e P2′a no código-fonte** (`0af456d`). Opções novas, todas desligadas
  por padrão, com a saída padrão idêntica ao 1.1.0:
  - `fitMethod`;
  - `admissibilityVeto` + `vetoTopK`: admissível = sem divergência no treino
    e na validação inteiros e |D| ≥ 1e−12; na promoção do campeão, os 5
    melhores de cada ilha concorrem, e um admissível sempre vence um
    inadmissível;
  - `finalRefine` = `simulation` (o P6 no núcleo).
- **Testes:** `core_tests` 96/0. Fumaça no CT: os campeões das sementes 23 e
  26, que divergiam no treino no E3, foram trocados por admissíveis.
- Fontes: `f2d6bf7`.
- **[limitação]** os binários de `cpp/build` correspondem ao código de
  `adc1ee9`; o build novo fica em `cpp/build_a1`.

## 2026-11-26 — Agentes atualizados e cataclismo

- **Agentes:** os três (UCB1, fuzzy, LLM) passam a ver a configuração da
  busca e a admissibilidade do campeão.
  - Fuzzy `expert-v2`: regra nova "sem campeão admissível → η" e a regra de
    θ desligada no modo `simulation`, onde θ não tem efeito.
  - Não há agente de rede neural no código.
  - Fonte: `ca765b6`.
- **Cataclismo:** `triggerRestart` passa a aceitar fração até 1,0. A elite
  e o campeão são sempre preservados (CHC, Eshelman 1991).
  - **Terminologia [artigo]:**
    - convergência prematura = colapso por perda de diversidade (deriva);
    - estagnação = população diversa que não progride (Lampinen e Zelinka,
      2000).

## 2026-11-26 — A1: pré-registro e congelamento

- **Decisão do usuário:** usar o melhor pacote do E3 e só abrir os testes do
  WH e do SB depois de congelar o desenho.
- **Braço A1:** pacote E3 (penalidades zero, teto 39, `simulation`) +
  `fitMethod` = `normal` + veto + refino final. Comparação com o
  `aegis_full` do 1.1.0, mesmos dados, sementes 1–10 e orçamentos.
- **Gate primário:** no WH e no SB, mediana da razão de teste ≤ 0,90, com
  Wilcoxon pareado exato, unilateral, e Holm < 0,05.
- **Congelado em `f51b8a7`**, antes de qualquer execução. O script de
  análise foi conferido com dados sintéticos. A primeira tentativa falhou
  sem rodar nada (diretório inexistente) e foi relançada às 07:41.
- Fontes: `experiments/a1/A1_PREREG.md`.

## 2026-11-26 — CAC: controlador adaptativo de convergência (desenvolvimento)

- **Pedido do usuário:**
  - um controlador que, a cada bloco de iterações, ajuste os parâmetros para
    extrair o máximo da convergência;
  - que **estime quando agir de novo**;
  - e que atue em **todos** os parâmetros do sistema.
- **Desenho (doc 14):**
  - braços lidos do esquema de ações do núcleo (16 parâmetros, ± passo e
    "não agir");
  - modelo de convergência por Theil–Sen sobre o log RMSE de validação do
    campeão;
  - horizonte h até a próxima decisão, com eventos que antecipam;
  - recompensa = ganho além do previsto;
  - Thompson sampling com prior das regras fuzzy.
- **v1 (desfavorável):** pior que sem agente nas 3 sementes do CT (validação
  0,72 / 0,85 / 0,64 contra 0,59 / 0,66 / 0,49 V); campeões encolheram para
  K = 5.
- **v2 (desfavorável)**, mecanismo identificado:
  - a regra fuzzy R6 subiu γ de 0 para 0,06 num único passo;
  - a seleção eliminou os modelos grandes de toda a população, de forma
    **irreversível** (voltar γ a 0 não recupera nada);
  - a tabela treinada entre execuções não ajudou, porque a recompensa é
    míope.
- **v3:**
  - pesos andam em décimos do passo máximo;
  - custo de afastamento do pacote;
  - prior fuzzy só para os operadores do DE.
  - **Primeiro resultado favorável:** o campeão no fim da busca é melhor
    que sem agente nas 3 sementes (RMSE normalizado 0,082 / 0,098 / 0,060
    contra 0,109 / 0,105 / 0,082), com K = 24–30.
  - Mais 7 sementes (24–30) em execução.
- **Achado sobre o A1:** num caso do CT, o refino final escolheu por V_A e
  V_B explodiu (RMSE de validação reportado 2,82 V). É o risco do P6 com a
  validação curta. **[limitação]** para o CT no A1; correção candidata:
  exigir que nenhuma das duas metades piore.
- Fontes: `5587fea`, `f480a71`, `f70923b`.

## 2026-11-26 — Plano empírico de treino do CAC

- **Pedido do usuário:** testes para o CAC aprender empiricamente o que cada
  um dos 16 parâmetros faz e quando agir.
- **Desenho (doc 15):** **ramificação determinística**. A mesma semente é
  idêntica até a geração g; num ramo se aplica uma ação, o outro segue sem
  mudança. Usam-se placebos (parâmetros inertes no pacote A1) para medir o
  ruído caótico.
- **Estágios:**
  - T1: mapa de impacto (≈ 1 440 ramos no CT);
  - T2: dose e momento;
  - T3: transferência para WH e SB;
  - T4: modelo de impacto e CAC v4;
  - T5: validação.
- **T0 executado:** a ação marcada para depois do fim reproduz o controle bit
  a bit; o ramo em g = 150 diverge exatamente na geração 151. **[artigo]**
  medição causal do efeito de cada hiperparâmetro.
- Fontes: `docs/architecture/15_PLANO_TREINO_CAC.md`; `2408df0`.

---

## 2026-11-26 — CAC v3: sementes 24–30 (CT, validação)

- **Fim da busca** (RMSE normalizado de validação do campeão, o objetivo da
  busca): CAC v3 melhor que sem agente em 5 de 7. Somando 21–23: **8
  melhores, 1 empate e 1 pior em 10 sementes.**
- **Valor final reportado** (depois da poda e do refino P6): misto. Nas
  sementes 24–30, 2 melhores, 4 piores e 1 empate.
- **Depois da poda e antes do refino:** 5 melhores, 3 piores e 2 empates em
  10.
- **Leitura:** o pós-processamento no CT (poda e refino P6) tem variância
  grande e pode inverter o ganho da busca. Exemplo: semente 27 do CAC, 0,0625
  no fim da busca e 0,221 depois da poda. Com 205 amostras de validação, o CT
  não decide se o CAC ajuda.
- **[limitação]** o efeito do CAC precisa ser medido no WH e no SB (T3/T5) e
  com o pós-processamento controlado. A poda e o refino no CT passam a ser
  uma fonte de variância a investigar à parte.
- Fonte: `experiments/results_perf/cac_v3b/` (fora do git).

## 2026-11-26 — Causa da variância do pós-processamento e proteção `postProcessGuard`

- **Causa encontrada [artigo]:** a poda aceita remoções quando o fitness
  não piora, mas o fitness mede a validação simulando dentro do bloco de
  validação, com os primeiros ≈ 40 pontos medidos. O valor reportado simula
  desde 40 amostras antes e pontua a validação inteira, transitório incluído.
  No CT (lento, 205 amostras) as duas medidas divergem, e a poda pode
  piorar o valor reportado. O refino P6 escolhe por uma metade só.
- **Proteção** (`postProcessGuard`, desligada por padrão; o A1 congelado não
  muda): poda, refino de um passo e refino P6 só são aceitos se a validação
  na convenção reportada não piorar.
- **Ablação** (CT, validação, sementes 21–30; a busca é idêntica com e sem
  proteção, conferido):
  - sem agente, mediana final 0,464 → **0,424 V**: 6 melhores, 4 iguais,
    nenhuma pior;
  - CAC v3, 0,432 → **0,405 V**: 6 melhores, 2 piores, 2 iguais; o caso
    catastrófico da semente 23 (2,82 V) cai para 0,50 V;
  - as 2 pioras vêm de a proteção ser gulosa passo a passo: bloquear a poda
    muda o modelo que o refino recebe.
- **CAC v3 contra sem agente, ambos com proteção:** 5 melhores, 4 piores e 1
  empate; mediana 0,405 contra 0,424 V. **Inconclusivo no CT.**
- **[limitação] Achado de desenho:** a busca otimiza uma validação com
  convenção de início diferente da reportada. Alinhar as duas é uma mudança
  candidata para depois do A1.
- **Desvio:** a recompilação de `cpp/build_a1` durante o A1 falhou no link
  (executável em uso). O executável do A1 foi conferido pelo hash e está
  intacto. O desenvolvimento passou a usar `cpp/build_dev`.
- Fontes: `586a3b7`; `experiments/perf/guard_ablation.sh`.

## 2026-11-26 — A1: resultado (teste aberto uma vez) e abertura do protocolo 1.1.0

- 30/30 execuções completas; manifesto com hashes no git (`5d1c5b8`) antes
  da análise; script e pré-registro inalterados desde `f51b8a7`.
- **Gate primário atingido [artigo]:**

| | A1 | 1.1.0 | Razão | p Holm |
|---|---|---|---|---|
| WH (teste) | 9,32 mV | 46,1 mV | 0,20 | 0,002 |
| SB multisine (teste) | 0,349 mV | 3,78 mV | 0,09 | 0,002 |
| SB arrow (extrapolação) | 0,507 mV | 7,56 mV | 0,07 | — |
| CT (teste, secundário) | 0,712 V | 0,661 V | 1,08 | — |

- No WH e no SB, o A1 vence nas **10 sementes**, sem divergências.
- **CT [limitação]:** a validação melhora (0,83 → 0,43 V), mas o teste piora
  8 %, com 3 divergências. É sobreajuste à validação curta, coerente com o
  E1 e com a investigação do pós-processamento.
- **Contexto na literatura (descritivo):**
  - no WH, o A1 fica abaixo dos NARX (pNARX 30,5, GP-NARX 12,8 mV) e da
    programação genética com gramática (23,5 mV), mas atrás das redes
    recorrentes e dos modelos em espaço de estados;
  - no SB, fica no nível dos melhores NARX e do SUBNET.
- **Protocolo 1.1.0 aberto** (`analyze.dart` em WH e SB): no WH, o melhor do
  1.1.0 foi o `aegis_sim` (37,6 mV) e a linha de base FROLS 12,5 mV; no SB,
  FROLS 2,10, `legacy_head` 2,89 e `aegis_full` 3,78 mV. Agentes no WH:
  UCB1 37,9 e fuzzy 53,8 mV (sem ganho).
- Fontes: `experiments/a1/A1_REPORT.md`, `A1_RESULTS.md`;
  `experiments/results/{wiener_hammerstein,silverbox}/analysis/SUMMARY.md`.

## 2026-11-26 — CAC T1: mapa causal de impacto dos 16 parâmetros (CT)

- 1 450 execuções com ramificação determinística (10 sementes × 4 momentos ×
  36 braços + controles), só validação.
- **[artigo]** Medição causal do efeito de cada hiperparâmetro sobre o
  campeão (fim da busca):
  - **γ ↑ é prejudicial sempre**, proporcional à dose (até +60 % log no RMSE;
    K −25);
  - **β ↑ é o efeito benéfico mais consistente no CT** (−7 a −20 %, 7–9 de 10
    sementes, também depois do pós-processamento);
  - δ ↑ e α ↑ ajudam no fim da busca, mas δ piora o valor reportado;
  - os operadores do DE, o reinício/cataclismo, η e `stagnationLimit` ficam
    dentro do ruído;
  - ζ é **inerte** (pisos do currículo acima dos valores testados): o T1
    achou um parâmetro sem efeito sem que ninguém precisasse dizer.
- **Ruído caótico** (placebos): −21 % a +57 % no RMSE final.
- **[limitação]** o CT sobreajusta a validação, e por isso a parcimônia ajuda
  aqui; no WH e no SB foi o contrário (A1). O mapa depende do sistema; o T3
  (WH/SB) é necessário. Sem correção para múltiplas comparações.
- **Desvio:** 10 execuções falharam por travamento da VM do Dart (memória) e
  foram refeitas.
- Fonte: `docs/architecture/15_PLANO_TREINO_CAC.md` §8;
  `experiments/cac/T1_RESULTS.md` (`2e87dd4`).

## 2026-11-26 — CAC T2+T3 iniciado

- Pedido do usuário: "pode continuar".
- Desenho registrado antes de rodar (doc 15 §9, `5c8754f`): dose e momento
  de β, α e δ, mais γ em doses mínimas e um placebo, no CT (10 sementes,
  orçamento completo), WH e SB (5 sementes, 3×10⁴ avaliações). Só validação.
- A análise do T1 foi generalizada para descobrir as sementes, e reproduz o
  resultado do T1 idêntico.
- **Correção deste diário:** um `sed` com `\&` na entrada do A1 apagou o
  cabeçalho de pendências, e com isso a entrada do T1 não foi inserida. Ambos
  foram restaurados à mão nesta data.

---

## 2026-11-27 — CAC T2+T3: resultado (dose e momento dos pesos, CT, WH e SB)

- 820 de 820 execuções completas, sem travamentos com 5 processos. Só
  validação.
- [artigo] **O efeito dos pesos de penalidade depende do sistema:**
  - no WH e no SB (20 000 amostras), subir δ ou γ, mesmo na menor dose
    (+0,02 e +0,002), piora o campeão em 5/5 sementes e em todos os
    momentos, com log da razão de +0,4 a +1,7;
  - β também piora, com efeito menor;
  - no CT (819 amostras), os mesmos braços ficam dentro do ruído ou ajudam;
  - na métrica final do CT, α e β tardio ajudam, e δ e γ pioram.
- [artigo] Coerente com o E3: penalidades zero foram o melhor pacote no WH e
  no SB.
- [artigo] Transiente no CT: β e δ pioram nas primeiras 25–50 gerações e só
  depois melhoram. O horizonte para julgar uma ação de peso deve ser de
  ≈ 200 gerações.
- Consequência para o CAC v4: subir β, δ ou γ exige um sinal medido de
  sobreajuste; sem ele, o CAC mantém os pesos. α fica permitido com passo
  pequeno.
- [limitação]
  - 5 sementes e orçamento de 3×10⁴ no WH e no SB;
  - sem correção para comparações múltiplas;
  - a faixa de ruído do CT é larga (−0,41 a +0,25).
- Ajuste de ferramenta: o título da análise passou a usar o nome do
  benchmark. A análise segue reproduzindo o T1 idêntico.
- Fonte: doc 15 §10; `experiments/cac/T2_*.md`.

---

## 2026-11-27 — CAC T4: modelo de impacto, CAC v4 e desenho do T5

- Pedido do usuário: "pode seguir para o T4 e montar o CAC v4".
- [artigo] **Sinal de sobreajuste.** gapOS = log(validação / treino, um
  passo) separa os sistemas em que subir penalidade ajuda (CT, mediana
  0,40) dos sistemas em que prejudica (WH 0,02, SB −0,05).
  - Na validação cruzada deixando o WH ou o SB de fora, o limiar escolhido
    nos outros dois não autoriza nenhuma subida no sistema deixado de fora.
  - O gap em simulação livre falha: autorizaria 77 de 140 ramos do WH, com
    perda.
  - Limiar conservador: 0,15. Fonte: `experiments/cac/T4_FEATURES.md`.
- [artigo] **CAC v4.** O mapa medido substitui o prior fuzzy:
  - β ↑ só com o portão aberto;
  - α ↑ permitido;
  - δ ↑ e γ ↑ bloqueados;
  - ζ, θ e o horizonte livre mascarados;
  - operadores do DE e reinícios com prior levemente negativo (ruído
    medido);
  - horizonte mínimo de 200 gerações após ação de peso.
  - Todos os parâmetros continuam no espaço de ações. O v3 segue disponível.
  - Testes: 43 de 43.
- [limitação] Só três sistemas: o portão separa grupos, não estima um
  limiar fino. Deixando o CT de fora, a regra "quando subir" não pode ser
  aprendida.
- T5 registrado antes de rodar (doc 15 §11.3): v4 contra o A1 sem agente e
  contra o v3, no CT (sementes 21–30) e no WH e no SB (31–35, orçamento
  completo); só validação; critério de não-dano no WH e no SB.

---

## 2026-11-27 — CAC T5: resultado (v4 contra o A1 sem agente e contra o v3)

- 60 de 60 execuções completas; só validação. Análise congelada antes:
  `experiments/cac/T5_RESULTS.md`.
- [artigo] **Critério registrado: não atingido.**
  - CT, fim da busca: v4 −0,151 (8/10 melhores), mas pior que o v3
    (−0,216).
  - WH: dano, +0,205 com 4 de 5 sementes piores.
  - SB: +0,007, com 3 de 5 piores (o limite era 2).
- [artigo] **O portão funcionou como desenhado.** No WH e no SB ele nunca
  abriu (gap entre −0,04 e +0,04) e nenhum peso foi mexido. O dano no WH
  veio de 2 a 8 ações em operadores do DE, medidos como "ruído" só no CT. Um
  efeito médio nulo não quer dizer inofensivo: perturbar a trajetória
  caótica no WH, onde os campeões sem agente são muito parecidos entre
  sementes, quase só pode piorar. (Análise exploratória, não prevista no
  registro.)
- [artigo] **CT:** o campeão da busca melhora em 8 de 10 sementes, mas a
  validação final reportada piora em 8 de 10. É a variância do
  pós-processamento; o A1 roda sem `postProcessGuard`.
- [limitação] 5 sementes no WH e no SB; as conclusões sobre a causa do dano
  são exploratórias.
- Próximos passos possíveis (decisão do usuário), em sementes novas:
  - v4.1, que só age onde há ganho medido;
  - CT com `postProcessGuard`.
- Fonte: doc 15 §12.

---

## 2026-11-27 — CAC v4.1 e desenho do T6 (com `postProcessGuard`)

- Pedido do usuário: "pode seguir com o v4.1 e o postProcessGuard no T6".
- **v4.1** (`measuredOnly`): só oferece braços com ganho medido (β ↑ e α ↑
  com o portão aberto, e o retorno à âncora). Os demais braços precisam de
  evidência positiva na tabela do próprio controlador.
  - Consequência: com o portão fechado, ele não age.
  - Testes: 45 de 45.
- **T6 registrado antes de rodar** (doc 15 §13):
  - sementes novas: CT 71–80, WH e SB 36–40;
  - `cac41_guard` vs `none_guard`, e, no CT, também `none`;
  - no CT, a medida principal passa a ser a validação final reportada;
  - no WH e no SB, o critério é de não-dano.
- Escolha registrada: o v4.1 foi desenhado depois de ver o T5. Por isso ele
  é testado só em sementes que ainda não tinham sido usadas.

---

## 2026-11-27 — Hipótese do usuário: faltam reguladores ou o sinal está errado

- Comentário do usuário: "ou estamos fornecendo os parâmetros errados para
  fazer a análise ou falta reguladores para atuar mas pra mim é nítido que
  uma inteligência ajudando na convergência é ponto positivo e precisamos
  encontrar o que está faltando ou errado".
- Diagnóstico só com dados existentes (T5, braço sem agente, validação):
  - [artigo] **WH limitado pela capacidade.** O campeão atinge ou encosta no
    teto de 39 regressores nas 5 sementes (máximo na história: 39, 39, 39,
    39, 38; K final: 32–39), e o gap ≈ 0 indica que não há sobreajuste. No
    SB, 4 de 5 sementes chegam a 39.
  - Os 16 parâmetros que o controlador pode mudar são todos de dinâmica da
    busca ou pesos de penalidade. Os de **capacidade e classe de modelo**
    (`maxRegressors`, `maxDelay`, `pmax`, `maxTermsPerReg`,
    `denominatorProbability`, `populationSize`) são fixos na configuração.
  - Outros pontos fracos do sinal:
    - cada execução começa com a tabela vazia, e com ≈ 20 decisões por
      execução o controlador não tem como aprender dentro dela;
    - a recompensa vem de uma única trajetória caótica;
    - a validação da busca usa outra convenção de início que a reportada
      (tema do A2).
- Próximo passo proposto: medir a folga de capacidade com teto estático
  maior no WH e no SB (só validação, sementes novas). Se houver ganho,
  tornar a capacidade um regulador do controlador, acionado pelo portão
  (gap ≈ 0 e K no teto → crescer; gap alto → podar).

---

## 2026-11-27 — Reguladores completos: o controlador alcança toda a configuração

- Pedidos do usuário:
  - "isto é um erro o regulador tem que poder ter acesso a tudo o tipo de
    configuração que a ferramenta dispõe … maxRegressors, maxDelay, pmax,
    maxTermsPerReg, denominatorProbability, tamanho da população";
  - "e todas as outras que tiver e se precisar criar mais também, quanto
    mais melhor".
- Desenho: `docs/architecture/16_REGULADORES_COMPLETOS.md`.
- **O controlador passa de 16 para 45 reguladores.** São 29 novos:
  - **capacidade:** `maxRegressors`, `maxTermsPerReg`, `maxDelay`, `pmax`,
    `pmin`, `exponentStep` (só grade igual ou mais fina que 0,5),
    `denominatorProbability`;
  - **busca:** população, elite, mutação de variável, JADE c e p,
    intervalo de imigrantes, hipermutação, estratégia, método de ajuste,
    veto e top-k;
  - **objetivo e currículo:** modo de erro, contribuição mínima da entrada,
    limite de estagnação de fase, papéis das ilhas;
  - **pós-processamento:** podador, refinador, P6, guard;
  - **eventos:** avançar fase, semear a partir do campeão, podar o campeão.
- [artigo] **Ficam fora, com motivo:**
  - divisão dos dados, coluna de saída, normalização (vazamento ou
    comparação inválida);
  - semente, threads;
  - orçamento;
  - `exponentStep` acima de 0,5 e `powerMode` (removeriam os expoentes
    reais).
- [artigo] **O teto de 40 regressores era uma trava de sanidade do núcleo,
  sem estrutura de dados dependente.** O teto de 39 do E3 estava encostado
  nela, então modelos maiores nunca foram testados. A trava agora é 200.
- O atraso máximo configurado passa a ser o teto de lançamento, porque fixa
  a linha comum de pontuação. A nova chave `maxDelayStart` dá o valor
  inicial do regulador.
- **Evento descartado:** `refineChampion` (refino P6 durante a busca) não
  funciona neste núcleo. Ao injetar o modelo refinado, o avaliador reajusta
  os coeficientes por mínimos quadrados e desfaz o refino.
- [limitação] **Defeito encontrado no lado Dart.** O registro de parâmetros
  do serviço usa valores padrão próprios, que não refletem a configuração
  real da execução (por exemplo, γ = 0,01 no registro contra 0 no pacote
  A1).
  - O CAC lê o valor atual primeiro desse registro.
  - Nos T1–T6, isso só afetou braços de descida de γ (rejeitados pelo núcleo
    como "sem mudança") e braços mascarados.
  - Para os reguladores novos, o valor passará a vir do snapshot do núcleo.
- Testes do núcleo no build novo (`cpp/build_cap`): core 96/96, API 92/92
  (26 checagens novas dos reguladores), phase0 11/11.
- **Bit-identidade sem ações contra o `build_dev`:** idêntico no CT
  (3×10⁵ avaliações) e no WH (2×10⁴), pacote A1 com guard, semente 7
  (ignorados só os campos de tempo).
- Cuidado de protocolo:
  - o T6 continua no `build_dev`, intacto;
  - as mudanças em Dart esperam o T6 terminar, porque cada execução roda
    `dart run` a partir do código-fonte.

---

### 2026-11-27 — Resultado do T6 (CAC v4.1 + postProcessGuard)

- **Execução.** T6 concluído sem erros: CT 30, WH 10 e SB 10 execuções,
  sementes novas, só validação. Análise congelada:
  `experiments/cac/T6_RESULTS.md`; doc 15 §14.
- [artigo] **Critério pré-registrado NÃO atendido.**
  - CT, `cac41_guard` vs `none_guard`:
    - fim da busca −0,184 (8/10 melhores);
    - validação final reportada +0,604 (7/10 piores).
  - WH e SB: o portão de sobreajuste nunca abriu e houve 0 ações; as
    execuções ficaram idênticas ao controle (não-dano atendido).
- [artigo] **O `postProcessGuard` sozinho** melhora a validação final do CT
  em 4/10 e nunca piora.
- [limitação] **Diagnóstico exploratório, feito depois da análise
  congelada.**
  - O v4.1 agiu com β↑ e α↑ e produziu campeões menores (K 5–22 contra
    24–34).
  - Esses campeões vencem na convenção de validação da busca (simulação a
    partir do atraso do próprio modelo), mas perdem na convenção reportada
    (simulação a partir de trainEnd − maxDelay).
  - O guard descarta que a causa seja o pós-processamento.
  - O controlador otimiza um sinal que, no CT, discorda da métrica
    reportada: confirma a hipótese do usuário de "sinal errado".
  - Correção candidata, ainda não testada: dar ao controlador, e à escolha
    do campeão, a validação na convenção reportada.

### 2026-11-27 — Controlador em Dart com acesso aos 45 reguladores; correção do doc 16

- **Opção nova `allRegulators` no CAC** (agentes `cac-all`, `cac4-all`,
  `cac41-all`). Com a opção ligada:
  - o controlador oferece todos os reguladores do esquema, menos os de
    pós-processamento, que não têm efeito online;
  - lê o valor atual do snapshot do núcleo, o que corrige o defeito do
    registro com padrões velhos;
  - trata os 3 eventos novos como braços de um disparo.
- **Padrão desligado:** v3, v4 e v4.1 ficam idênticos ao T1–T6.
- **Agente LLM:** a lista de parâmetros e o prompt incluem os reguladores
  novos.
- **Testes:** Flutter 48/48.
- [limitação] **Correção de documentação.** O doc 16 §3.5 listava um evento
  `refineChampion` que nunca foi implementado no núcleo. A linha foi
  removida; são 3 eventos novos e a contagem de 29 reguladores novos está
  certa.
- **Mapa de impacto.** Os reguladores novos continuam sem mapa de impacto.
  O CAC v4.1 não os usa até o T7 medir o efeito.

### 2026-11-27 — Autorização do usuário para continuar sem supervisão

- **Pedido do usuário:** "quando terminar já vou estar dormindo então já
  deixo registrado que você pode continuar já para a próxima etapa e ter
  como meta só parar quando tudo já estiver analisado e implementado
  conforme nossas conversas".
- **Plano:**
  - analisar o T7;
  - montar as regras do CAC v5 a partir do mapa medido;
  - corrigir o sinal de validação (convenção reportada, achado do T6);
  - pré-registrar e rodar a validação (T8);
  - registrar tudo.
- **Restrições que continuam valendo:**
  - sem chamadas pagas;
  - sem uso do teste;
  - builds congelados intactos;
  - commits só em `audit/aegis-1.1.0-wip`.
- **Decisões reservadas ao usuário** (artigo, A2, licenças, LLM pago):
  continuam pendentes.

### 2026-11-27 — Correção do sinal de validação (`validationContext`) e desenho do T6b

- **Achado do T6.** A busca simula o bloco de validação sozinho; o
  relatório simula a partir da cauda do treino e pontua a validação
  inteira.
- **Correção:** nova chave `validationContext` no núcleo (build novo
  `cpp/build_sig`, ignorado pelo git; o `build_cap` do T7 ficou intacto).
  Com ela ligada, a busca e o controlador medem a validação na convenção
  reportada.
- **Verificação:**
  - desligada: bit-idêntica ao `build_cap` no CT (só o relógio difere);
  - ligada e sem pós-processamento: fim da busca = validação reportada
    (0,1332333753 nos dois);
  - testes core, API (com um teste novo) e phase0 passam.
- **T6b**, registrado antes de rodar (doc 15 §15):
  - CT com sementes 91–100, em 1 processo ao lado do T7;
  - WH e SB (sementes 41–45) depois do T7;
  - braços `none_guard`, `none_guard_ctx` e `cac41_guard_ctx`;
  - medida principal: validação final reportada.

- [limitação] **Desvio no T6b, antes de qualquer execução.** Com o T7
  rodando, a memória livre era de 0,7 GB de 7,4 GB, e um sexto processo
  Dart arriscaria derrubar o T7. O T6b passa a rodar depois do T7, com 5
  processos, encadeado automaticamente. Desenho e critérios sem mudança.

### 2026-11-28 — Resultado do T7 (mapa de impacto dos reguladores novos)

- **Execução.** T7 concluído sem falhas: CT 490, WH 130 e SB 130
  execuções, só validação. Doc 16 §8; `experiments/cac/T7_*.md`.
- [artigo] **Capacidade.** O teto de 39 regressores do A1 limita o WH e o
  SB. Teto 79 desde o início, na validação final:
  - WH: −0,215, 4/1 melhores;
  - SB: −0,246, 4/1 melhores;
  - CT: misto.
- [artigo] **População, nos sistemas sem sobreajuste.**
  - −25 melhora: WH 5/0 e SB 4/1 na validação final;
  - +50 piora: WH 0/5 e SB 1/4.
  - rand/1 piora o WH (0/5) e `pmax` −1 piora o SB (0/5).
- [limitação] **Subir o teto durante a busca quase não aumenta o modelo.**
  A inicialização sorteia até o teto, e o crescimento durante a busca é
  lento. Conferido no código, não é defeito.
- [limitação] **CT.** A faixa do placebo é larga (mediana |d| 0,20) e há
  divergências na métrica reportada: nada robusto.
- [limitação] **Inertes.** Elitismo e hipermutação ficaram inertes.
- **Pendente com o usuário (A2).** Mudar o teto do pacote fica como
  recomendação. O teste não foi aberto.

### 2026-11-28 — CAC v5 e desenho do T8 (registrado antes de rodar)

- **CAC v5** (agente `cac5`): v4.1 mais o mapa medido do T7.
  - Com o portão confirmado fechado (sistemas sem sobreajuste), a partir da
    geração 50, oferece uma única redução de população, de 50 para 25: WH
    5/0 e SB 4/1 no T7.
  - Bloqueia população +, rand/1 e `pmax` −.
  - Mascara elitismo e hipermutação.
  - Testes: Flutter, 4 testes novos.
  - Código feito em `.wt/v5`, porque o T6b usa o `lib/` principal. Entra no
    diretório principal antes do T8.
- **T8** (doc 16 §9):
  - sementes novas: CT 101–110, WH e SB 71–80;
  - braços `none` e `cac5`, mais `STATIC_pop25` no WH e no SB;
  - `validationContext` ligado se e somente se o T6b atender o critério 1;
  - critério: WH e SB com mediana < 0 e pelo menos 7/10 melhores; CT sem
    dano.

### 2026-11-28 — T6b concluído: correção de sinal não atende critérios [artigo]

- O T6b completou todas as execuções (CT 30; WH 15; SB 15), sem falhas. Rodei a análise congelada; a saída está em `experiments/cac/T6B_RESULTS.md`.
- **Critério 1 (`validationContext` no pacote): não atendido.**
  - CT: d final mediano +0,039 (4 melhores / 6 piores).
  - SB: 3 de 5 piores; o máximo permitido era 2.
  - WH: −0,005 (3 / 2).
- **Critério 2 (CAC v4.1 com contexto): não atendido.**
  - CT: −0,004 (5 / 5), abaixo do mínimo de 6 sementes melhores.
  - WH e SB: zero ações.
- [artigo] Corrigir a convenção eliminou o dano do CAC no CT (T6: +0,604; T6b: −0,004). O dano do T6 vinha, portanto, do sinal de validação errado. Mas não há ganho detectável.
- [limitação] O CT tem n = 10 e faixa placebo larga.
- **Decisão pela regra registrada antes:** o T8 roda com CTX=0. `validationContext` fica como opção desligada por padrão.

### 2026-11-28 — CAC v5 no diretório principal; T8 iniciado [artigo]

- Apliquei no diretório principal o código do v5 que estava na cópia `.wt/v5`. Commit `3a648df`.
  - flutter test: 52/52 passam. dart analyze: sem problemas.
  - Removi a cópia `.wt/v5`.
- Iniciei o T8 com CTX=0, conforme a regra pré-registrada, porque o critério 1 do T6b não foi atendido.
  - Ordem: CT, WH, SB; 5 processos; `build_sig`.
  - Log: `experiments/results_cac/t8_run.log`.

## Pendências e decisões do usuário (atualizado em 2026-11-27)

- ~~Resultado do A1 e abertura dos testes do WH e do SB~~ feitos em 2026-11-26.
- Estratégia do artigo à luz do A1 (gate atingido no WH e no SB; CT pior).
- CAC: T5 e T6 concluídos (critério não atingido em ambos; T6: sinal de validação da busca discorda da métrica reportada no CT). Dart com acesso aos 45 reguladores feito. T7 (mapa de impacto dos reguladores novos) em execução desde 2026-11-27 14:04, build_cap, 5 processos.
- A2 candidato: alinhar a validação da busca com a reportada e proteger o
  pós-processamento (problema do CT).
- Licenças dos dados WH/SB, agente LLM pago.
