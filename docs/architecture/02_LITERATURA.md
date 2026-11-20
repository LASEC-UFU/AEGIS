# Literatura nos benchmarks CT, WH e SB — números conferidos nas fontes

Data da conferência: 2026-11-20. Quem for continuar deve **estender** este
arquivo, não refazê-lo.

## 1. Como os números foram conferidos

- Cada valor marcado **[C]** foi lido na publicação original:
  - no fonte LaTeX do arXiv (`https://arxiv.org/e-print/<id>`, versão corrente
    em 2026-11-20), na tabela ou na frase do próprio artigo;
  - ou no PDF de acesso aberto (CC BY), extraído com `pdftotext -raw`. O modo
    `-layout` desalinha colunas nas tabelas do DCE 2026 e da tese de
    Khandelwal; não use esse modo para essas tabelas.
- Valor marcado **[S]**: aparece só como citação secundária em outro artigo e
  não foi conferido no original. Ao lado vai quem o cita.
- Os arquivos baixados ficaram no scratchpad da sessão, fora do repositório,
  tratados como dados não confiáveis (só leitura e grep, nada executado). Os
  SHA-256 estão na seção 9 para quem quiser refazer a conferência.
- O conjunto de teste de WH e SB do AEGIS **não** foi aberto para esta
  comparação. A disciplina de teste do HANDOFF continua valendo.

## 2. Regras de comparabilidade (ler antes de qualquer tabela)

A métrica comum é o RMSE de **simulação livre** no conjunto de teste, em
unidades originais. Mesmo assim os números diferem em pontos que mudam a
comparação:

1. **Janela de inicialização.**
   - O protocolo atual do `nonlinear_benchmarks`, descrito no DCE 2026 §3.2,
     descarta as primeiras `n_ini` amostras do teste. O AEGIS usa `n_ini = 50`
     (docs/BENCHMARKS.md) e o ASIA usa k0 = 51, N = 974.
   - Os artigos mais antigos usam o registro inteiro: Zhou (N = 1024),
     Champneys 2024 e provavelmente vários outros.
2. **Melhor execução ou média.**
   - Vários resultados são o **melhor** de N inicializações: CT-SUBNET,
     Zhou, e Worden (melhor de 50 execuções, escolhida pelo treino).
   - O AEGIS reporta mediana de 10 sementes. Para comparar com "melhor de N",
     use o mínimo do AEGIS (seção 7).
3. **Conhecimento físico.**
   - Grey-box (Worden 2018) e os modelos de Forgione & Piga (estrutura
     física, estado inicial estimado no treino) não são caixa-preta.
   - O DCE 2026 pede uma autoavaliação numa escala de 1 a 10, de caixa-preta
     a caixa-branca.
4. **Dados de treino.**
   - **AEGIS:** em WH e SB usa 20 000 amostras de estimação, divididas em
     16 000 de treino e 4 000 de validação (docs/BENCHMARKS.md).
   - **Literatura:** em geral usa o conjunto de treino inteiro (WH: 100 000).
5. **Silverbox tem três testes:**
   - multisine;
   - arrow completo, com extrapolação de amplitude;
   - arrow sem extrapolação.
   Valores de colunas diferentes não se comparam.
6. **Versão conferência × periódico.** O baseline de Champneys et al. (arXiv
   2405.10779, IFAC SYSID 2024) e a versão de periódico (DCE 2026) têm números
   diferentes; por exemplo, CT pNARX 0,413 × 0,417 V e CT LTI SS 0,588 ×
   0,600 V. Para comparar com o AEGIS, **use o DCE 2026**, que tem o mesmo
   protocolo `n_ini`.

## 3. Cascaded Tanks — RMSE de simulação no teste (V)

### 3.1 Baselines com o mesmo protocolo do AEGIS (DCE 2026, Tabela 6) [C]

Schoukens, Champneys, Beintema et al. (2026). Seleção de hiperparâmetros pela
validação separada do treino; `n_ini` descartado.

| Modelo | CT (V) | Observação conferida no texto |
|---|---|---|
| LTI SS | 0.600 | erro de saída, iniciado por subespaço, `n_x` = 2 |
| ARX | 0.682 | lags por AIC na validação: `n_u` = 11, `n_y` = 2 |
| **pNARX** | **0.417** | Polinômios de Legendre **univariados** (sem termos cruzados), ordem 3 escolhida por AIC na validação, mínimos quadrados de um passo |
| GP NARX | 0.839 | |
| MLP NARX | 1.26 | |
| MLP FIR | 1.24 | |
| RNN | 0.97 | |
| LSTM | 0.452 | |
| OLSTM | 0.427 | |
| GRU | 0.568 | |

### 3.2 Métodos publicados

| Método (fonte) | CT (V) | Status | Protocolo / observação |
|---|---|---|---|
| Grey-box: modelo físico 2 + GP-NARX (Worden et al. 2018, Tab. 6, "Grey 2") | 0.1913 | [C] | Usa física (Bernoulli + transbordamento). Melhor de 50 execuções do otimizador (DE/PSO/QPSO/KH), escolhida pelo treino. Caixa-preta GP-NARX no mesmo artigo: 0.4550. Modelo físico 2 sozinho: 0.2799 |
| CT subspace encoder (Beintema, Schoukens, Tóth, ICLR 2023; arXiv 2204.09405 Tab. 1) | **0.22 melhor / 0.30 média** | [C] | Ensemble de 17 modelos que diferem só na inicialização; "melhor" é o mínimo no teste. O DCE 2026 cita 0.306 (não bate com o arXiv; ver §6) |
| DT subspace encoder (mesma tabela) | 0.37 melhor / 0.97 média | [C] | idem |
| Neural ODE com normalização (mesma tabela) | 0.18 melhor / 0.33 média | [C] | idem |
| ASIA, agente LLM (Piga & Forgione, arXiv 2605.10480) | 0.298 | [C] | Claude Code com Sonnet 4.6. 15 configurações; validação cruzada em 2 dobras **só no treino**; modelo final é ensemble de 2 LTC/CfC; k0 = 51. Os autores registram risco de **vazamento implícito do teste** (o RMSE de teste era registrado durante a busca) |
| TNBS-NARX (Karagoz & Batselier, arXiv 2003.07594) | 0.3018 | [C] | NARX com B-splines em rede tensorial; λ por validação cruzada em 3 dobras no conjunto de estimação |
| TSEM (Forgione & Piga 2021, arXiv 2006.02915) | 0.33 | [C] | Estrutura física com redes; minimização do erro de simulação truncado; estado inicial estimado no treino |
| SCI (mesmo artigo) | 0.40 | [C] | idem |
| NLSS2 (Relan et al.; versão longa arXiv 1805.06252, Tab. "Comparison of the nonlinear models") | 0.3433 | [C] | Na "Benchmark Val" (o registro de teste do benchmark). λ escolhido pelo RMSE "on the validation data set": ambíguo, pode ser o registro de teste |
| PNLSS-I (mesmo artigo) | 0.44984 | [C] | Mesmo registro |
| Sparse Bayesian DNN (Zhou, Ibrahim, Pan, arXiv 1911.06847) | 0.344 | [C] | "Best simulation error" entre várias regularizações e λ; N = 1024 (sem descartar `n_ini`). A mesma rede sem regularização teve média de 2.0634 em 20 repetições |
| Hidden SINDy, poly. (Ugolini, Breschi, Manzoni, Tanelli, arXiv 2403.00578) | 0.55 | [C] | Modelo esparso interpretável; NN-ARX 0.47 e ARX 0.77 no mesmo artigo |
| PWARX (Mattsson et al. 2018) | 0.350 | [S] | citado por Zhou e por Karagoz |
| NOMAD (Brunot et al. 2017) | 0.376 | [S] | citado por Zhou e por Karagoz. O repositório OATAO não respondeu |
| Volterra feedback (Schoukens & Scheiwe 2016) | 0.3972 | [C], extensão §10 | Original, Tabela 1; protocolo de inicialização não equiparado ao `n_ini=50` |
| IO stable CT ANN (Weigand et al. 2021) | 0.39 | [S] | citado pelo CT-SUBNET |
| GP-inspired SS (Svensson & Schön 2017) | 0.45 | [S] | O arXiv 1603.05486 **não** contém o resultado do CT; ele estaria só na versão Automatica |
| Volterra (Birpoutsoukis et al. 2018) | 0.54 | [C], extensão §10 | Original, Tabela 1, grau 3 **com remoção de transientes**; sem essa remoção: 2.08 |
| Grey-box (Rogers et al. 2017) | 0.18 | [S] | citado por Forgione & Piga |
| BLA (Relan et al. 2017) | 0.75 | [S] | Na versão longa (arXiv 1805.06252) a BLA vale 0.75331 no "Model Test", que é uma divisão interna diferente |

## 4. Wiener–Hammerstein — RMSE de simulação no teste (mV)

| Método (fonte) | WH (mV) | Status | Observação |
|---|---|---|---|
| DCE 2026, Tabela 6: LTI SS / ARX | 43.4 / 43.4 | [C] | Protocolo `n_ini` |
| DCE 2026: **pNARX** | **30.5** | [C] | Univariado, ordem 5 |
| DCE 2026: GP NARX / MLP NARX / MLP FIR | 12.8 / 87.2 / 17.3 | [C] | |
| DCE 2026: RNN / LSTM / OLSTM / GRU | 4.88 / 1.54 / 1.52 / 1.77 | [C] | |
| State-space encoder / SUBNET (Beintema, Tóth, Schoukens, L4DC 2021; arXiv 2012.07697) | 0.241 | [C] | NRMS 0.0987 %, σ_y = 244.7 mV |
| **TAG + programação genética, multiobjetivo** (Khandelwal, tese TU/e 2020, Tab. 7.10) | **39.0** (otimizado para predição) / **23.5** (otimizado para simulação) | [C] | **É o método mais parecido com o AEGIS**: busca evolutiva de estrutura de modelos polinomiais. O próprio autor diz que fica cerca de duas ordens de grandeza atrás do melhor resultado publicado |
| dynoNet (Forgione & Piga; arXiv 2006.02250) | 1.2 | [C] | Fit 99.5 %. O DCE 2026 e o 2405.10779 citam **0.452** (ver §6) |
| QBLA (Schoukens, Pintelon, Rolain 2014) | 0.279 | [S] | citado por SUBNET e Khandelwal; dynoNet cita 0.28 |
| Pole-zero splitting / NL-LFR | 0.30 / 0.30 | [S] | citados por SUBNET |
| PNLSS (Paduart et al. 2012) | 0.42 | [S] | citado por SUBNET, Khandelwal e DCE |
| Generalized WH (Wills & Ninness) | 0.49 | [S] | citado por SUBNET e Khandelwal |
| LS-SVM (Falck et al.) | 4.07 | [S] | idem |
| Bio-social evolution (Naitali & Giri 2016) | 8.55 | [S] | Evolutivo, com estrutura WH fixa |
| SVM (Marconato & Schoukens) | 47.4 | [S] | |
| BLA (Lauwers et al.) | 56.2 | [S] | |

## 5. Silverbox — RMSE de simulação no teste (mV)

| Método (fonte) | multisine | arrow completo | arrow sem extrap. | Status |
|---|---|---|---|---|
| DCE 2026: LTI SS | 6.96 | 14.4 | 6.58 | [C] |
| DCE 2026: ARX | 6.95 | 14.3 | 6.58 | [C] |
| DCE 2026: **pNARX** (ordem 7) | **0.505** | **1.41** | **0.455** | [C] |
| DCE 2026: GP NARX | 0.418 | 0.772 | 0.373 | [C] |
| DCE 2026: LSTM / OLSTM / GRU | 1.05 / 1.04 / 1.07 | 6.13 / 5.87 / 4.37 | 1.35 / 1.27 / 1.17 | [C] |
| SUBNET, `n_x` = 4 (arXiv 2012.07697) | 0.36 ("Val") | 1.4 | 0.32 | [C] |
| TAG-GP (Khandelwal 2020, Tab. 7.8) | 0.09 (validação = última realização multisine) | 0.36 (teste = parte gaussiana/arrow; não diz se exclui a extrapolação) | — | [C] |
| PNLSS (Paduart et al. 2010) | — | 0.26 | — | [S] |
| LS-SVM / sigmoidal / Poly-LFR | — | 0.32 / 0.30 / 0.35 | — | [S] |

## 6. Divergências encontradas e como foram resolvidas

1. **CT "Relan 0,34" × "PNLSS 0,45".**
   - **Resolvida.** Os dois números estão no mesmo artigo de Relan et al.
     (versão longa): NLSS2 = 0.3433 e PNLSS-I = 0.44984.
   - Forgione & Piga citaram o NLSS2; Champneys/DCE citaram o PNLSS.
2. **dynoNet no WH.**
   - O arXiv 2006.02250 dá **1.2 mV** (fit 99.5 %); as tabelas de SOTA de
     Champneys/DCE dão **0.452 mV**.
   - **Não resolvida.** A versão publicada (IJACSP 35(4) 2021) é paga e não
     foi lida. Use 1.2 mV com a nota, ou não use.
3. **CT-SUBNET.**
   - O arXiv 2204.09405 dá 0.22 (melhor) e 0.30 (média); o DCE 2026 cita
     0.306.
   - Provavelmente é outra versão do artigo ICLR, mas **não conferido**.
4. **Champneys 2024 × DCE 2026.**
   - Os números mudaram entre as versões. O protocolo `n_ini` e a ordem
     máxima do pNARX (7 → 10) mudaram.
   - O DCE 2026 é a versão revisada por pares e com o protocolo do AEGIS.
5. **Zhou e "melhor de N".**
   - O valor 0.344 é o melhor erro de simulação entre configurações.
   - O texto não diz que a escolha foi feita fora do teste.
6. **Worden 0.191.**
   - É o melhor de 50 execuções, escolhido pelo erro de treino.
   - Usa um modelo físico com transbordamento.

## 7. Onde o AEGIS fica no CT (benchmark de desenvolvimento, teste já visto)

Fonte: `experiments/results/cascaded_tanks/analysis/runs.csv`, 10 sementes,
3×10⁵ avaliações, `n_ini` = 50.

| Condição | mediana | mínimo | máximo | nº de parâmetros |
|---|---|---|---|---|
| aegis_full | 0.661 | 0.6557 | 0.899 | 4 em todas as sementes |
| legacy_head (código original) | 0.678 | 0.641 | 1.026 | 4–7 |
| FROLS (seleção pela validação) | 0.752 | — | — | 8 |

Comparação com o mesmo protocolo (DCE 2026):

- O AEGIS fica **pior que o LTI SS (0.600)**, um pouco melhor que o ARX
  (0.682) e bem pior que o pNARX univariado (0.417), o LSTM (0.452) e o OLSTM
  (0.427).
- Mesmo o **mínimo** de 10 sementes (0.656) não alcança o LTI SS. Comparar
  pelo "melhor de N" não muda essa conclusão.
- Os métodos de 0.30–0.35 V usam:
  - erro de simulação no treino (TSEM, SUBNET, ASIA);
  - física (grey-box, Forgione & Piga);
  - aproximadores flexíveis com muitos parâmetros (TNBS-NARX, DNN).

**WH e SB:** os resultados de teste do AEGIS não foram examinados. Não compare
números de validação do AEGIS (FROLS: WH 13.6 mV e SB 2.0 mV na validação) com
os números de teste da literatura. Lembre também que o AEGIS treina com 20 000
amostras, e a literatura com o conjunto inteiro.

## 8. Observações para quem vai propor melhorias

São fatos das fontes. As hipóteses vêm marcadas como tal.

- **pNARX simples, com ~40 parâmetros e sem termos cruzados, vence o AEGIS no
  CT** (0.417 contra 0.661 V). Os campeões do AEGIS têm 4 parâmetros.
  - *Hipótese:* a penalidade de complexidade, ou o viés de um passo do
    objetivo, empurra a busca para modelos parcimoniosos demais.
  - Teste isso só com treino e validação.
- **O método publicado mais próximo do AEGIS é a programação genética
  multiobjetivo com gramática (TAG)** de Khandelwal. Ela fica em 23.5 mV no
  WH, contra 0.24 mV do melhor resultado. Busca evolutiva de estrutura
  polinomial, sozinha, não chegou perto do estado da arte em WH.
- **Worden et al. 2018 usam JADE**, o mesmo DE do AEGIS, mas para estimar
  parâmetros físicos, não estrutura. O melhor resultado em CT dessa linha vem
  de física mais GP-NARX.
- **Quase todos os resultados ≤ 0.35 V no CT treinam para simulação**:
  simulação truncada, encoder com multiple shooting, ou BPTT em modelos
  recorrentes. O AEGIS estima coeficientes por mínimos quadrados de um passo
  (pseudo-linearização).
- **ASIA (agente LLM) chega a 0.298 V**, mas trocando a *classe de modelo* e o
  código, não ajustando hiperparâmetros de um otimizador. Os autores
  registram vazamento implícito do teste.
  - Isso é diretamente relevante para o papel dos agentes no AEGIS.
  - No AEGIS, agentes que ajustam parâmetros do DE não mostraram ganho.
- **Modelos esparsos interpretáveis** (Hidden SINDy) ficam em 0.55 V no CT.
  Interpretabilidade e 0.3 V ainda não apareceram juntas em nenhuma fonte
  conferida.

## 9. Referências e proveniência

| Ref. | Autores, título, veículo | Identificador | Acesso | SHA-256 do arquivo baixado |
|---|---|---|---|---|
| DCE 2026 | Schoukens, Champneys, Beintema et al., "Benchmarking for nonlinear system identification: submission platform and baseline results", *Data-Centric Engineering* 7, e40 (2026) | DOI 10.1017/dce.2026.10067 (lido no PDF) | CC BY, White Rose eprint 245745 | `fd5628599e3da65ce9fd9f846e3dc003a9e1752e3b960a0d022cf0755496e522` |
| Champneys 2024 | Champneys, Beintema, Tóth, Schoukens, Rogers, "Baseline Results for Selected Nonlinear System Identification Benchmarks" (IFAC SYSID 2024, template ifacconf) | arXiv 2405.10779 | arXiv | `66d6d1a9c45692187f6280ec2b6b30305324eda9748614ba1c585af89fd0e0ab` |
| Worden 2018 | Worden, Barthorpe, Cross, Dervilis, Holmes, Manson, Rogers, "On evolutionary system identification with applications to nonlinear benchmarks", *MSSP* 112:194–232 | DOI 10.1016/j.ymssp.2018.04.001 (lido no PDF) | CC BY, White Rose eprint 130344 | `5d5ae39ce9395fee72fcd4c2b49796881c8f144eb72c97928229e20bc81805d7` |
| Forgione & Piga 2021a | "Continuous-time system identification with neural networks: model structures and fitting criteria", *Eur. J. Control* 59:69–81 | arXiv 2006.02915 | arXiv | `1a5e38c67bbc842052aecdb4579c02ea33ec5db2507a472e07ff89f5b8cfbbb0` |
| Forgione & Piga 2021b | "dynoNet: a neural network architecture for learning dynamical systems", *IJACSP* 35(4):612–626 | arXiv 2006.02250 | arXiv | `5fe92871d59638a0b2c01181f4ce273f60b840ddeec8c9b304cffd4c355c8b42` |
| Beintema 2021 | Beintema, Tóth, Schoukens, "Nonlinear state-space identification using deep encoder networks", L4DC 2021, 241–250 | arXiv 2012.07697 | arXiv | `dd53182a53b38cb9c9b3495e792768ce21c0253faf521613307967aa6e2d2952` |
| Beintema 2023 | Beintema, Schoukens, Tóth, "Continuous-time identification of dynamic state-space models by deep subspace encoding", ICLR 2023 | arXiv 2204.09405 | arXiv | `792e0ba85f2f3a3c028464cf6e17debe0bdb1c88bff7a061e2bd81e1bc351e00` |
| Relan (longo) | Relan, Tiels, Marconato, Schoukens, "Data Driven Discrete-time Parsimonious Identification of a Nonlinear State-Space Model for a Weakly Nonlinear System with Short Data Record" | arXiv 1805.06252 (a versão IFAC-PapersOnLine 50(1):452–457, 2017 não foi lida) | arXiv | `9681ca5f947ffad55dded488bc5e56b3774993f78d0821cf1da6fcb4c5b82dad` |
| Zhou | Zhou, Ibrahim, Pan, "A Sparse Bayesian Deep Learning Approach for Identification of Cascaded Tanks Benchmark" (veículo não conferido) | arXiv 1911.06847 | arXiv | `98d9fcb41bfc30a1f72c7a1f252d27df4c53786eab6f66c3c12ed41a3fe0ca9c` |
| ASIA | Piga, Forgione, "ASIA: an Autonomous System Identification Agent" (preprint, 2026) | arXiv 2605.10480 | arXiv | `e2d19702e55fc0c43b9c3d0222eaee3ea3bc9f696fbacf76266a273d7f65bdd5` |
| Karagoz | Karagoz, Batselier, "Nonlinear system identification with regularized Tensor Network B-splines" (veículo não conferido) | arXiv 2003.07594 | arXiv | `1a935104a468b3c915dd59255d977349f070e712b39f9d2056a7a3dfcd77240d` |
| Ugolini | Ugolini, Breschi, Manzoni, Tanelli, "SINDy vs Hard Nonlinearities and Hidden Dynamics: a Benchmarking Study" (template ifacconf; veículo não conferido) | arXiv 2403.00578 | arXiv | `0896add0d58f1052300764fccbd07990df4e332cf7710aed23e9dee629ebc163` |
| Khandelwal 2020 | D. Khandelwal, "Automating data-driven modelling of dynamical systems: an evolutionary computation approach", tese de doutorado, TU Eindhoven | pure.tue.nl/ws/files/147585343/20200304_Khandelwal.pdf | portal TU/e | `1b521ebdcb75b3f6054285dd0fb8aea3a79c74e54d2fd4999b2f3ffe143bbd99` |
| Khandelwal (método) | Khandelwal et al., "Data-driven Modelling of Dynamical Systems Using Tree Adjoining Grammar and Genetic Programming" — não usa CT, WH nem SB | arXiv 1904.03152 | arXiv | `ed41c3c29ed423151a163186604a50022e2980cc2e8b969ba418f56735b4f50f` |
| Hafiz | Hafiz et al., "Multi-Objective Evolutionary Framework for Non-linear System Identification: A Comprehensive Investigation" — seleção multiobjetivo de estrutura NARX polinomial; não usa CT, WH nem SB | arXiv 1908.06232 | arXiv | `c1aaffa56f3643c734e86ed62d875d20e6f748e0110ad1398e289dd10d5a1cc2` |
| Svensson & Schön | "A flexible state space model for learning nonlinear dynamical systems", *Automatica* 80:189–199 (2017) — o arXiv não tem o CT | arXiv 1603.05486 | arXiv | `e7a28a2a0c0f78cc59984ce1aaf7c96e848893b88011d7300ce6adc4e46d12d6` |

**Não verificado** (sem acesso aberto encontrado nesta sessão):

- Mattsson et al. 2018 (PWARX, MSSP 106:40–48);
- Brunot et al. 2017 (NOMAD; o servidor OATAO não respondeu);
- Schoukens & Scheiwe 2016 (Volterra FB);
- Birpoutsoukis et al. 2018;
- Rogers et al. 2017;
- Weigand et al. 2021;
- Paduart et al. 2010 e 2012;
- Naitali & Giri 2016;
- as versões publicadas de dynoNet e de Relan (IFAC 2017).

Também não foi verificado:

- o DOI do Champneys 2024 (IFAC-PapersOnLine);
- os veículos de Zhou, Karagoz e Ugolini.

**Planilha do nonlinearbenchmark.org:** o ASIA usa o leaderboard de
nonlinearbenchmark.org, acessado em 2026-05-06, mas não lista os valores. A
planilha não foi consultada.

## 10. Extensão da conferência — análise arquitetural, 2026-11-20

Esta seção acrescenta a conferência nova; não invalida a proveniência da
leitura anterior. As duas linhas [C] atualizadas na §3.2 prevalecem sobre a
lista histórica de pendências da §9. Fontes acessadas por navegador de
pesquisa, sem download local novo; por isso não há SHA-256 adicional.

### 10.1 Valores promovidos a conferência no original

**Schoukens, Maarten; Scheiwe, Fritjof Griesing.** *Modeling Nonlinear Systems
Using a Volterra Feedback Model*. Workshop on Nonlinear System Identification
Benchmarks, Bruxelas, 25–27 abril 2016. Manuscrito aceito e folha de
proveniência da VUB, Tabela 1 na segunda página do PDF: Cascaded Tanks,
LTI=0.58781; feedback polinomial=0.48715; feedback Volterra=**0.3972**,
erro RMS de simulação na validação do benchmark, saída em V. A tabela não
especifica descarte `n_ini=50`; não transportar a comparação para o protocolo
DCE sem ressalva. Nenhum DOI foi identificado no original consultado.
[PDF original VUB](https://cris.vub.be/ws/portalfiles/portal/24196282/Maarten_Modeling_nonlinear_systems.pdf).

O bloco linear vem da BLA; a não linearidade em realimentação usa memória
e kernels Volterra. Fixado o bloco linear, os coeficientes não lineares
entram linearmente no ajuste. Isso sustenta aproveitar inicialização linear,
não copiar seu bloco como novo modelo final do AEGIS.

**Birpoutsoukis, Georgios; Csurcsia, Péter Zoltán; Schoukens, Johan.**
*Efficient Multidimensional Regularization for Volterra Series Estimation*.
Mechanical Systems and Signal Processing **104**, 896–914 (2018),
DOI [10.1016/j.ymssp.2017.10.007](https://doi.org/10.1016/j.ymssp.2017.10.007).
Postprint [arXiv 1804.10026](https://arxiv.org/pdf/1804.10026), Tabela 1,
página 17 do PDF: modelo grau 3, índice de erro **0.54 V com remoção de
transientes**, **2.08 V sem estimação de transientes**. A §5.3 descreve
estimação do transiente com kernels DC e hiperparâmetros por análise dos
resíduos. Essa compensação não equivale a simplesmente descartar 50 amostras.
O dado de 0.54 é conferido, mas sua comparação direta com AEGIS é limitada.

### 10.2 Tentativas sem promover o número a [C]

| Valor histórico [S] | Fonte/caminho tentado e resultado | Uso nesta proposta |
|---|---|---|
| CT PWARX 0.350 | Página original Elsevier confirma Mattsson, Zachariah, Stoica, MSSP 106:40–48, 2018, DOI [10.1016/j.ymssp.2017.12.027](https://doi.org/10.1016/j.ymssp.2017.12.027); prévia descreve método, tabela numérica indisponível e abertura integral retorna 403 | Número segue [S]; não fundamenta expectativa quantitativa |
| CT NOMAD 0.376 | OATAO `/17993/1/Brunot_17993.pdf` inacessível; Elsevier S2405896317301209 retorna 403; DOI 10.1016/j.ifacol.2017.08.088 localizado como candidato, sem original integral recuperado | Número segue [S]; metadados ainda não certificados nesta extensão |
| CT RKNN 0.39 | Página original Taylor & Francis indexada identifica Weigand, Deflorian, Ruskowski, *Input-to-state stability for system identification with continuous-time Runge–Kutta neural networks*, IJC 96(1):24–40 (2023; online 2021), DOI [10.1080/00207179.2021.1978555](https://doi.org/10.1080/00207179.2021.1978555); PDF integral retorna 403 | Corrigir distinção de ano; número segue [S], sem tomar snippet como leitura da tabela |
| CT GP-SS 0.45 | Busca encontrou tese de Svensson e referência Automatica; original numérico CT não recuperado nesta extensão; arXiv antigo já não o continha (§3) | [S] |
| CT grey-box Rogers 0.18 | [Página original Springer](https://link.springer.com/chapter/10.1007/978-3-319-53841-9_15) confirma capítulo *On a Grey Box Modelling Framework for Nonlinear System Identification*, Rogers, Holmes, Cross, Worden (2017), DOI 10.1007/978-3-319-53841-9_15; pôster dos autores usa NMSE, não certifica aquele RMSE | [S]; não converter NMSE sem variância e protocolo |
| CT BLA 0.75 | Permanece a discrepância de split já identificada em Relan (§3); não encontrada evidência de equivalência ao teste atual | [S], não “baseline no mesmo protocolo” |
| WH QBLA 0.279 | Busca por título original de Schoukens/Pintelon/Rolain localizou metadados e cópias, mas tabela não foi validada no original nesta extensão | [S] |
| WH pole-zero / NL-LFR 0.30 / 0.30 | Buscas dirigidas devolveram sobretudo tabelas secundárias do SUBNET e tese de Beintema; nenhuma promoção baseada nelas | [S] |
| WH PNLSS 0.42 | Busca por Paduart 2012 retornou referências e tabelas secundárias; o artigo de 2010 abaixo não verifica esse resultado de 2012 | [S] |
| WH generalized WH 0.49 | Página Elsevier de Wills/Ninness 2012 localizada, sem certificar tabela; a referência de 2009 nas fontes secundárias é outra versão | [S], manter versão explícita |
| WH LS-SVM 4.07 / SVM 47.4 / BLA 56.2 | Buscas com autores e valores retornaram sobretudo SUBNET e sua tese, fontes secundárias para esses resultados | [S] |
| WH bio-social 8.55 | Busca por Naitali/Giri 2016 e valor não trouxe tabela original; artigo WH-EA 2018 é outro método/versão | [S], não trocar pelo resultado de 2018 |
| SB PNLSS 0.26 | [Prévia Elsevier de Paduart et al. 2010](https://www.sciencedirect.com/science/article/abs/pii/S000510981000021X) confirma método e DOI, sem tabela acessível | [S] |
| SB LS-SVM / sigmoidal / Poly-LFR 0.32 / 0.30 / 0.35 | Buscas dirigidas retornaram tabelas secundárias ou nenhum original numérico acessível | [S]; região arrow ainda precisa ser conferida no original |

Não encontrado aqui não significa inexistente ou incorreto. Esses números
não entram como metas quantitativas nem como evidência de ganho esperado.
As divergências dynoNet e CT-SUBNET da §6 permanecem não resolvidas.

## 11. Técnicas que fundamentam a proposta, com limites de transferência

**Erro de simulação e continuação.** Forgione, Marco; Piga, Dario,
*Continuous-time system identification with neural networks: model structures
and fitting criteria*, European Journal of Control 59:69–81 (2021),
DOI [10.1016/j.ejcon.2021.01.008](https://doi.org/10.1016/j.ejcon.2021.01.008),
[texto original, §4.2](https://arxiv.org/html/2006.02915v3).
O TSEM otimiza parâmetros e estados iniciais de subsequências, regularizando
a consistência dinâmica; a formulação evita depender de uma simulação longa
em cada passo. A analogia com multiple shooting é explicitada pelos autores.
**Transferência proposta:** otimizar coeficientes NARX em blocos e aumentar
horizonte. Usar história medida no início dos blocos é uma simplificação
distinta; não é reproduzir TSEM nem estimar seus estados ocultos. Não
transportar a precisão publicada para essa simplificação.

**Encoder e custo.** Beintema, Gerben; Tóth, Roland; Schoukens, Maarten,
*Nonlinear state-space identification using deep encoder networks*, L4DC,
PMLR 144:241–250 (2021),
[original PMLR](https://proceedings.mlr.press/v144/beintema21a.html),
[arXiv 2012.07697v2](https://arxiv.org/abs/2012.07697).
Divide a loss em seções e estima seu estado inicial a partir de históricos.
O DOI de periódico não é usado para identificar este artigo de conferência;
identificador permanente arXiv: 10.48550/arXiv.2012.07697. A contribuição
relevante é separar condicionamento/inicialização de estado e simulação de
longo prazo. O AEGIS não incorporará encoder neural na primeira etapa.

**Busca evolutiva e ajuste interno.** Khandelwal, Dhruv; Schoukens, Maarten;
Tóth, Roland, *Data-driven modelling of dynamical systems using tree adjoining
grammar and genetic programming*, IEEE CEC (2019),
DOI [10.1109/CEC.2019.8790250](https://doi.org/10.1109/CEC.2019.8790250),
[manuscrito §II-C/II-D](https://arxiv.org/html/1904.03152v1),
[registro TU/e](https://research.tue.nl/p/en/research-outputs/data-driven-modelling-of-dynamical-systems-using-tree-adjoining-g).
GP propõe estruturas válidas pela gramática; LS/LS iterativo estima constantes;
seleção considera predição, simulação e número de coeficientes. Esse artigo
trata outros sistemas, não certifica os números CT/WH/SB da tese de 2020.
**Transferência:** separar busca de S e ajuste de θ preservando DE do AEGIS.
Não copiar GP, gramática de árvores ou prometer que Pareto resolve o ajuste.

**Multiobjetivo.** Hafiz, Faizal; Swain, Akshya; Mendes, Eduardo,
*Multi-Objective Evolutionary Framework for Non-linear System Identification:
A Comprehensive Investigation*, manuscrito de 2019 destinado a Neurocomputing,
[arXiv 1908.06232v1, §3](https://arxiv.org/html/1908.06232v1),
DOI do preprint [10.48550/arXiv.1908.06232](https://doi.org/10.48550/arXiv.1908.06232).
Comparação de NSGA-II/SPEA-II/MOEA-D para subconjuntos polinomiais; duas metas
(cardinalidade e erro de predição) e escolha posterior. Não testa CT/WH/SB.
**Transferência:** arquivo erro–tamanho com regra de escolha explícita;
trocar a meta por simulação longa é hipótese nossa. Não acrescentar mais um
otimizador global nem usar esse artigo como prova de superioridade no AEGIS.

**Semeadura linear e refinamento não linear.** Paduart, Johan; Lauwers, Lieve;
Swevers, Jan; Smolders, Kris; Schoukens, Johan; Pintelon, Rik,
*Identification of nonlinear systems using Polynomial Nonlinear State Space
models*, Automatica 46(4):647–656 (2010),
DOI [10.1016/j.automatica.2010.01.001](https://doi.org/10.1016/j.automatica.2010.01.001),
[prévia original](https://www.sciencedirect.com/science/article/abs/pii/S000510981000021X).
A descrição acessível confirma inicialização pela BLA e expansão não linear.
Ela sustenta avaliar sementes informadas; não demonstra que ARX é BLA, nem
que o NARX do AEGIS recuperará os resultados PNLSS. O número SB 0.26 continua
sem conferência da tabela.

**Seleção ortogonal.** Chen, S.; Billings, S. A.; Luo, W., *Orthogonal least
squares methods and their application to non-linear system identification*,
International Journal of Control 50(5):1873–1896 (1989),
DOI [10.1080/00207178908953472](https://doi.org/10.1080/00207178908953472),
[original disponibilizado pelo autor](https://www.southampton.ac.uk/~sqc/listP/IJC1989-50-5.pdf).
Seleção forward por contribuição ortogonal e ajuste linear fornecem
estruturas candidatas de forma econômica. No AEGIS, ERR serve a sementes e
ordenação de movimentos, não como prova de causalidade física ou de baixa
loss de simulação. Aceitação deve passar pelo mesmo ajuste e validador.

## 12. Implicações delimitadas para o AEGIS

- A literatura sustenta **testar** ajuste orientado à simulação, inicialização
  informada e seleção explícita de tamanho; não sustenta prever um ganho em V.
- O pNARX do DCE e o FROLS local não são o mesmo baseline: bases, dicionários,
  lag, tamanho e critérios diferem. O desempenho FROLS atual não elimina
  a hipótese de um NARX simples melhor configurado.
- Os 20 mil pontos de WH/SB são estimação reduzida, não treino completo.
  `n_ini` igual é condição necessária, não suficiente, de comparabilidade.
- “Melhor de N” e mediana/média não serão fundidos numa classificação única.
  Física, compensação de transientes, região de teste e tamanho de estimação
  acompanham cada número. Arrow completo e sem extrapolação permanecem separados.
- A decisão de orientar agentes a tarefas é hipótese motivada pelo contrato
  e pela baixa utilidade observada das ações atuais; ASIA não prova que o
  mesmo ganho exista para um catálogo fechado NARX. O LLM segue não avaliado
  no AEGIS; não há evidência para adotar política neural.

## 13. Complemento solicitado: capacidade × ajuste

A fórmula e as ordens do pNARX CT no DCE permitem inferir 39 colunas
univariadas; isso não certifica número de coeficientes com intercepto no
código. O registro AEGIS conta apenas coeficientes ajustados, não decisões
de estrutura. A referência também descreve entrada contemporânea, enquanto
o AEGIS começa no atraso um. A comparação precisa controlar essa convenção.
Fonte primária: [DCE 2026, §4.2 e Tabelas 2–3](https://doi.org/10.1017/dce.2026.10067).

O fato de bons resultados usarem ajuste por simulação é motivação, não prova
de que capacidade e física sejam dispensáveis; o pNARX de um passo já é
um contraexemplo à necessidade de trocar a loss para melhorar o AEGIS.
Análise quantitativa das penalidades, teto de nove coeficientes do AEGIS
atual e estudo fatorial proposto estão em
[06_CAPACIDADE_E_AJUSTE.md](06_CAPACIDADE_E_AJUSTE.md).
