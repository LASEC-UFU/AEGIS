# Fase 0: pré-registro (E1, E2 e E3)

Data: 2026-11-20. O usuário aprovou a Fase 0 ("pode começar a produção").
Origem: [07_PARECER_REVISAO.md](../../docs/architecture/07_PARECER_REVISAO.md),
§10.4, com as correções da §9.

**Este arquivo foi escrito antes de qualquer execução da Fase 0.** O SHA-256
dele entra no manifesto antes da primeira execução de E1 ou E2. Qualquer
mudança depois disso vira uma nova versão, com motivo registrado. Resultados
negativos são reportados.

## 0. Regras

- **Dados:**
  - só os arquivos de estimação `experiments/data/processed/<b>/est.csv`;
  - nenhum CSV de teste é aberto pela ferramenta: ela não tem opção de
    teste;
  - os testes de WH e SB continuam fechados.
- **Divisão explícita, igual à do estudo 1.1.0:**
  - CT: `trainEndRow` = 819, `valEndRow` = 1024;
  - WH e SB: `trainEndRow` = 16000, `valEndRow` = 20000;
  - `testStartRow` = número de linhas.
- **Normalização:** min–max em [−1, 1], ajustada no treino. É a mesma do
  pipeline, porque a avaliação passa por `aegis_evaluate_model`.
- **Métricas:** produzidas pelo avaliador do núcleo (`evaluate_segment`).
  - O treino é simulado desde o maior atraso do modelo e pontuado a partir
    da linha `maxDelay` = 40.
  - A validação é simulada desde `trainEnd − 40` e pontuada de `trainEnd`
    até `valEnd`.
  - Métrica principal: **RMSE de simulação livre na validação, em unidades
    originais** (`rmseFreeRunOrig`).
- **Configuração base:** `experiments/configs/conditions/aegis_full.json`
  (`maxDelay` = 40, base de potências `hybrid`).
- **Build e núcleo:** build separado em `cpp/build_phase0`, alvo
  `aegis_phase0`. O núcleo 1.1.0 (`cpp/build`) não é tocado.
- **Carga na máquina:**
  - enquanto o protocolo 1.1.0 roda, só 1 processo da Fase 0, em prioridade
    BelowNormal;
  - o E3 só começa depois que o protocolo terminar, com no máximo 6
    processos.
- **Modelos do AEGIS 1.1.0 lidos dos JSON de WH e SB:**
  - leitura programática só de `report.model`;
  - nenhum campo de teste é impresso nem lido pela ferramenta;
  - as duplicatas são removidas pela serialização canônica (estrutura e
    expoentes), não pelo texto da equação.

## 1. E1: capacidade com estruturas fixas e ajuste QR

Por benchmark b ∈ {CT, WH, SB}. Os atrasos começam em 1 (convenção do
AEGIS), salvo no controle 1.4.

| ID | Estrutura | K (coeficientes com intercepto) |
|---|---|---|
| CHAMP | Campeões distintos do `aegis_full` 1.1.0, sementes 1–10 | 4 a 9 |
| ARX_L | ARX com os atrasos AR do DCE 2026, Tab. 2: CT (n_y, n_u) = (2, 11); WH (6, 12); SB (7, 14) | n_y + n_u + 1 |
| PN_DCE | Monômios univariados dos mesmos atrasos, grau igual ao da Tab. 3 do DCE: CT 3, WH 5, SB 7 | (n_y + n_u)·grau + 1 |
| PN_K | FROLS, com ERR no treino e ordem determinística, sobre o dicionário univariado D = {y(k−i)^p, i = 1..10} ∪ {u(k−j)^p, j = 1..20}, p ∈ {1, 2, 3}; seleciona K − 1 termos | K ∈ {4, 9, 20, 40} |
| E1b_m | Espinha ARX_L forçada mais m termos não lineares (p ∈ {2, 3}, mesmos atrasos do ARX_L), escolhidos por ERR sobre o resíduo da espinha no treino | ARX_L + m, m ∈ {1, 3, 5} |

**1.4 Controle de suporte temporal (secundário).**
- Variantes ARX_L0 e PN_DCE0 usam u(k) contemporâneo: atrasos de u de 0 a
  n_u − 1, como no DCE.
- Implementação: coluna extra `u_lead(k)` = u(k+1), usada com atraso 1. A
  última linha de `est.csv` é descartada nas duas variantes do par, então
  `valEnd` passa a ser `rows − 1`.
- A comparação é pareada com ARX_L e PN_DCE recalculados nas mesmas
  `rows − 1` linhas.

**Registro de cada estrutura:**
- ID canônico e K;
- número de coeficientes exatamente zero, ou seja, o posto efetivo do QR;
- RMSE livre e de um passo no treino e na validação, em unidades originais;
- flags de divergência e tempo.

**Gate E1, decidido agora:**
- **Referência:** V_CHAMP(b), a mediana do RMSE livre de validação dos
  campeões distintos.
- **Apoio à hipótese de capacidade:** o PN_K com K = 40 atinge ≤ 0,90 ×
  V_CHAMP(b) em pelo menos 2 dos 3 benchmarks.
- PN_DCE, ARX_L, E1b e o controle 1.4 são descritivos e **não** entram no
  gate.
- O resultado negativo significa "sem apoio para priorizar capacidade", não
  "capacidade é irrelevante".

## 2. E2: ajuste por erro de simulação (LM) em estrutura fixa

**Estruturas:**
- todas as do E1 em que o denominador é 1 e q ≤ 150, com q = coeficientes
  mais intercepto;
- os modelos racionais e os acima do limite são registrados como "não
  executado", com o motivo.

**Perda:**
- soma dos quadrados do erro de simulação livre no **treino** (coordenadas
  normalizadas), com a mesma convenção do avaliador;
- simulação desde o maior atraso do modelo, com saídas medidas antes disso,
  pontuada da linha 40 até `trainEnd − 1`;
- a validação nunca entra no ajuste.

**Parâmetros otimizados:** todos os coeficientes e o intercepto. Atrasos e
expoentes não mudam.

**Inicialização:** os coeficientes do QR devolvidos pelo avaliador
(`refit = 1`).

**Jacobiano por sensibilidades recursivas:**
- `s(k) = ∂f/∂ϑ + Σᵢ ∂f/∂ŷ(k−i) · s(k−i)`;
- sensibilidade zero nas linhas com saída medida.
- **Derivada da base híbrida:**
  - p = 1: derivada 1;
  - p inteiro n: n·x^(n−1);
  - p não inteiro: p·|x|^(p−1).
- **Política para p < 1 com |x| < 1e−12:**
  - se ocorrer na trajetória candidata, o passo é rejeitado;
  - se ocorrer na inicialização, o status é `nondifferentiable_init` e o
    LM não roda.

**Conferência de consistência, obrigatória e fatal:**
- a simulação da ferramenta com os coeficientes do QR tem de reproduzir o
  `rmseFreeRun` de treino do avaliador, com diferença relativa ≤ 1e−9;
- se não reproduzir, a estrutura é marcada `consistency_fail` e excluída do
  gate, com contagem reportada.

**Levenberg–Marquardt:**
- sistema `(JᵀJ + λ·diag(JᵀJ)) δ = Jᵀr`, resolvido por Cholesky;
  se não for positivo definido, λ é multiplicado por 10;
- λ₀ = 1e−3; ×10 a cada passo rejeitado; ÷3 a cada passo aceito;
- **limites:** no máximo 100 iterações e no máximo 10 rejeições seguidas;
- **parada por convergência:** redução relativa da perda < 1e−10 num passo
  aceito, ou ‖δ‖ ≤ 1e−10·(‖ϑ‖ + 1e−10);
- **passo rejeitado:** quando a trajetória sai do limite de divergência do
  núcleo (10 × max|y_treino| normalizado), fica não finita ou não reduz a
  perda;
- **inicialização divergente no treino:** status `init_diverged`, LM não
  roda e a estrutura entra na contagem de falhas.

**Avaliação:** os coeficientes finais passam pelo avaliador com `refit = 0`.

**Gate E2, decidido agora:**
- **Medida:** por benchmark, a mediana, sobre as estruturas executadas, de
  `(V_LM − V_QR) / V_QR`.
- **Apoio ao ajustador:**
  - essa mediana é ≤ −10 % em pelo menos 2 dos 3 benchmarks;
  - em cada um desses benchmarks, as divergências na validação com LM não
    passam das com QR.
- Wilcoxon pareado exato por estrutura é reportado só como descrição. As
  estruturas não são amostras independentes.

## 3. E3: triagem só por configuração (binário 1.1.0)

Roda só depois que o protocolo 1.1.0 terminar.

| Fator | Níveis |
|---|---|
| `maxRegressors` | 8 ou 39 |
| Penalidades | padrão do `aegis_full`, ou zeradas: `complexityPenalty` = `exponentPenalty` = `denominatorPenalty` = `alpha` = 0 e `gammaAnnealStart` = `gammaAnnealEnd` = 0 |
| `errorMode` | `one_step` ou `simulation` com `freeRunHorizon` = 0 |

- **Tamanho:** 8 células × sementes 21–30, nos três benchmarks.
- **Orçamento:** o mesmo do estudo (3×10⁵ avaliações no CT, 1,5×10⁵ em WH e
  SB). Divisão explícita (§0), sem arquivo de teste.
- **Pesos efetivos:** são publicados. Os pisos de ζ do currículo e o piso
  de θ da ilha free-run continuam ativos; isso é limitação conhecida, e o E3
  é um **pacote de triagem**.
- **Gate de triagem:**
  - comparação: penalidades zeradas com teto 39 contra o padrão com teto 8,
    no mesmo `errorMode`;
  - critério: mediana do RMSE livre de validação ≤ 0,90 vezes a do padrão
    em pelo menos 2 dos 3 benchmarks;
  - consequência: decompor a pressão de parcimônia antes de qualquer
    conclusão causal.

## 4. Testes da ferramenta, antes de usar dados reais

1. **Simulação:** o simulador próprio reproduz `RationalModel::simulate`
   (diferença ≤ 1e−12) em modelos com expoentes 1, 2, 3 e 0,5.
2. **Sensibilidades:** concordam com diferenças finitas centrais
   (passos 1e−4, 1e−5, 1e−6; o melhor tem erro relativo < 1e−6) num modelo
   não linear pequeno e bem condicionado.
3. **Sistema sintético:** `y[k] = 0,5·y[k−1] + 0,2·u[k−1] + 0,1·u[k−2]²`,
   sem ruído, entrada uniforme em [−1, 1], semente de desenvolvimento 41.
   - O QR dá erro de simulação de treino < 1e−9.
   - O LM a partir de coeficientes perturbados em 20 % volta a uma perda
     < 1e−12.
4. **Equivalência de bases:** monômios {x, x², x³} mais constante e Legendre
   {P1, P2, P3} mais constante dão as mesmas predições de um passo (≤ 1e−9).

## 5. Saídas

- `experiments/results_phase0/<b>/e1e2.jsonl`, uma linha por estrutura;
- `experiments/results_phase0/<b>/e3/<célula>/`;
- `experiments/results_phase0/MANIFEST.json` com:
  - SHA-256 deste arquivo, do executável e das configurações;
  - hashes dos `est.csv`;
  - data e hora.

Relatório: `experiments/phase0/PHASE0_REPORT.md`, com todas as estruturas,
falhas e "não executados".
