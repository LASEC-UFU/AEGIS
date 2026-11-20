# Preparação do artigo — IFAC Journal of Systems and Control (rascunho)

Status: **rascunho de trabalho**. Nada aqui é afirmação final; os números do
Wiener–Hammerstein e do Silverbox serão preenchidos somente após a análise
única do protocolo congelado (ver `experiments/EXPERIMENT_LOG.md`).

## 0. Periódico e modelo

- IFAC-JSC: periódico de acesso aberto publicado pela Elsevier (fonte: página
  de periódicos da IFAC, consultada em 2026-11-20).
- Modelo: classe Elsevier `elsarticle` (CTAN v3.5, 2026-01-09, LPPL 1.3),
  pacote oficial `elsarticle.zip` indicado na página "LaTeX instructions" da
  Elsevier. Esqueleto em `paper/manuscript.tex`. **Não** usar o template de
  congresso IFAC-PapersOnLine.
- **A verificar manualmente** (o Guide for Authors no ScienceDirect não pôde ser
  lido por acesso automatizado — HTTP 403): tipos de artigo e limites de
  tamanho, estilo de referência (numérico ou autor-ano), highlights, resumo
  gráfico, declarações (dados/código, conflitos de interesse, CRediT, uso de IA
  generativa), modelo de revisão.

## 1. Títulos possíveis

1. *Auditable agent supervision of evolutionary NARX identification: an empirical study on public nonlinear benchmarks*
2. *What helps multi-island differential evolution identify NARX models? Ablations, agent supervision and reproducibility on three benchmarks*
3. *A typed action interface for supervising evolutionary system identification with local and language-model agents*

(Escolher depois dos resultados; o título 1 é o mais compatível com o que os
dados do CT sustentam até agora.)

## 2. Problema científico e contribuição (formulação provisória)

**Problema.** Métodos evolutivos para seleção de estrutura NARX têm muitos
hiperparâmetros cujo ajuste costuma ser manual; propostas de "agentes" que
ajustam a busca on-line raramente são avaliadas com protocolos que separem o
efeito do agente do ruído entre sementes, e frequentemente reportam métricas
one-step, que são pouco informativas para sistemas amostrados rapidamente.

**Contribuições que o trabalho pode sustentar (sujeito aos resultados):**

1. Uma arquitetura de supervisão **auditável**: interface de ações tipada e
   limitada (faixa, passo máximo, cooldown, trava de orçamento, kill switch),
   aplicação entre gerações, registro de trajetória com estado anterior,
   desfecho medido contra uma linha de base de deriva, e modo lockstep que torna
   experimentos com agentes reprodutíveis por semente.
2. Um estudo de ablação com ≥ 10 sementes, orçamento de avaliações igualado e
   testes pareados, sobre três benchmarks públicos, medindo separadamente JADE,
   multi-ilha, migração, papéis/regimes de ilha, currículo, termo de simulação,
   representação racional e base de potência.
3. Comparação de supervisores: nenhum, UCB1 heurístico, política fuzzy
   interpretável e política fuzzy ajustada a partir de trajetórias (e LLM, se
   houver orçamento autorizado), com custo e latência.
4. Uma auditoria que documenta defeitos com impacto numérico em uma
   implementação anterior (corte de dados de teste, teste de estabilidade
   invertido, divergência mascarada) — útil como lição de reprodutibilidade.

**Diferenciação**: em relação a FROLS (Chen, Billings & Luo, 1989; Billings,
2013), o AEGIS busca expoentes reais e termos racionais com objetivo composto;
em relação a abordagens de DE adaptativo (JADE, Zhang & Sanderson, 2009), o foco
é a supervisão externa auditável e a separação experimental do efeito do
supervisor.

## 3. Resumo provisório (sem números ainda)

> We study the on-line supervision of a multi-island differential evolution
> method for polynomial and rational NARX identification. Supervisors — a UCB1
> heuristic bandit, an interpretable fuzzy policy, a fuzzy policy adjusted from
> logged trajectories and, optionally, a large language model — act only
> through a typed, bounded and logged action interface and are evaluated in a
> lockstep mode that makes every run reproducible from its seed. On the
> Cascaded Tanks, Wiener–Hammerstein and Silverbox benchmarks, with ten seeds
> per condition, equal evaluation budgets and paired non-parametric tests on
> the free-run (simulation) error of the official test sets, we quantify the
> contribution of each algorithmic component and of each supervisor.
> [Resultados principais — preencher.] We also report the defects found in an
> earlier implementation and their effect on reported accuracy.

## 4. Descrição matemática (para a seção Methods)

**Modelo.** Para entradas u e saída y (normalizadas por min-max ajustado no
treino, sem corte):

ŷ(k) = (c + Σ_{j∈N} θ_j φ_j(k)) / (1 + Σ_{j∈D} θ_j φ_j(k)),
φ_j(k) = Π_m b(x_{i_m}(k − d_m), p_m),

com b(x,p) = x^p para p inteiro e sign(x)|x|^p para p não inteiro (base
"hybrid"), d_m ∈ {1,…,d_max}, p_m ∈ [p_min, p_max] em passos de 0,5.

**Estimação.** Pseudo-linearização dos regressores do denominador
(ψ_j = −y(k)φ_j(k)) e mínimos quadrados com intercepto por QR de Householder
(estimador de erro de equação, enviesado sob ruído na saída para modelos
racionais — limitação a declarar).

**Objetivo** (menor é melhor):
f = E + α·B + β·n_D + γ·n_F + δ·Σ|p−1| + η·P_S + ζ·P_I + θ·E_fr, com
E = RMSE one-step na validação (modo `one_step`) ou RMSE de simulação na
validação inteira (modo `simulation`); B = BIC/n; P_S = singularidade do
denominador + divergência da simulação; P_I = déficit da contribuição das
entradas, c = Σ ERR_entradas / (1 − Σ ERR_AR) com termos AR primeiro.
Todos os candidatos pontuados a partir da mesma amostra (d_max).

**Busca.** N_I ilhas × NP indivíduos; JADE DE/current-to-pbest/1 sem arquivo
(F ~ Cauchy(μF, 0,1) truncada em 1, CR ~ N(μCR, 0,1)); variação de estruturas
de comprimento variável; migração em anel com filtro de reavaliação; papéis de
ilha (pesos) e regimes (dobras contíguas da validação); campeão canônico
reavaliado na validação completa; currículo de quatro fases.

**Supervisão.** Observação o_t (`aegis.observation/1`), ação a_t ∈ A (tabela de
parâmetros com faixa e passo máximo), aplicação em t+1, desfecho
s = (−Δrel_após) − (−Δrel_antes) do RMSE de validação em H = 25 gerações.

**Política fuzzy.** Takagi–Sugeno ordem zero, t-norma mínimo, consequentes Δp
por parâmetro, agregação por média ponderada, ação única se a ativação máxima
≥ 0,4; ajuste offline por utilidade ponderada das ações compatíveis nas
trajetórias de treino (desativa regras com utilidade negativa; inverte o sinal
quando a direção oposta tem utilidade positiva maior).

## 5. Protocolo experimental

Ver `docs/EXPERIMENTS.md` e `docs/BENCHMARKS.md`. Pontos a constar no artigo:
benchmarks e citações; desvio (20 000 amostras de estimação para WH e SB);
divisão 80/20 temporal; normalização no treino; teste usado uma única vez;
janela de inicialização de 50 amostras; orçamento (3×10⁵ / 1,5×10⁵ avaliações);
10 sementes; uma thread por execução; testes de Wilcoxon pareados exatos com
correção de Holm; IC por bootstrap; hardware e software.

## 6. Tabelas e figuras previstas

| Item | Fonte |
|---|---|
| T1 Benchmarks e protocolo | `docs/BENCHMARKS.md` |
| T2 Condições | `docs/EXPERIMENTS.md` §6 |
| T3 RMSE de simulação no teste (mediana [IQR], divergências) por condição × benchmark | `experiments/results/*/analysis/SUMMARY.md` |
| T4 Testes pareados vs `aegis_full` (Δ mediano, p Holm) | idem |
| T5 Supervisores: ações, rejeições, decisões, custo/latência | idem ("Agent activity") |
| T6 Comparação com FROLS e com o código original | idem |
| F1 Arquitetura (núcleo, interface de ações, agentes) | a desenhar |
| F2 Boxplots por condição | `analysis/boxplot_test_freerun.svg` |
| F3 Convergência (mediana e IQR vs avaliações) | `analysis/convergence.svg` |
| F4 Saída medida × simulada no teste (melhor/mediana semente) | a gerar a partir dos modelos salvos |

## 7. Afirmações

### Sustentadas até agora (CT, benchmark de desenvolvimento — confirmar em WH/SB)
- Remover papéis/regimes de ilha ou usar uma única ilha aumentou a frequência
  de campeões que divergem na simulação longa (6/10 vs 0/10), com piora
  significativa após Holm.
- A base `signed` contínua foi significativamente pior que a base híbrida
  quantizada.
- Nenhum supervisor (UCB1, fuzzy) melhorou significativamente o erro de
  simulação no teste; o UCB1 tendeu a piorar.
- As correções da auditoria não produziram melhoria significativa do erro de
  simulação em relação ao código original no CT.

### Não devem ser feitas
- Que o AEGIS supera métodos do estado da arte ou mesmo baselines lineares.
  - No CT, com o mesmo protocolo `n_ini`, o AEGIS (mediana 0,661 V) fica
    pior que o LTI SS (0,600 V) e que o pNARX univariado (0,417 V) do DCE 2026
    (Schoukens et al., DOI 10.1017/dce.2026.10067).
  - Em WH e SB, a estimação usa um subconjunto dos dados.
  - Ver `docs/architecture/02_LITERATURA.md`, cujos números foram conferidos
    nas fontes originais.
- Que o agente LLM melhora a convergência (não executado).
- Que a política local substitui o LLM ou aprende a imitá-lo.
- Que R² one-step próximo de 1 indica boa identificação.
- Qualquer conclusão baseada em uma única execução.
- Que os resultados do CT são independentes do desenvolvimento (o teste do CT
  foi visto na iteração 1).

## 8. Limitações e trabalho adicional

### Avaliação adicional da política aprendida (CT, sementes 11–20)

Dez execuções por condição, sem divergência. RMSE de teste (V), mediana
[IQR]: referência 0,6718 [0,6616; 0,6742]; fuzzy aprendida 0,6718
[0,6616; 0,6742]; UCB1 0,7182 [0,7045; 0,7405]; fuzzy heurística 1,091
[0,7051; 1,383]. A aprendida coincide com a referência em nove sementes e
piora uma; p Holm = 1, sem evidência de superioridade. UCB1 piora o RMSE
de teste (p Holm = 0,0469); fuzzy heurística p Holm = 0,0547. A família
de correção contém três comparações com a referência. Sementes novas
não tornam CT independente do desenvolvimento. Fonte completa:
`experiments/results_policy_eval/cascaded_tanks/analysis/SUMMARY.md`.

- Estimação com 20 000 amostras (WH, SB); orçamento fixo; uma configuração
  padrão sem ajuste por benchmark.
- Estimador de erro de equação para modelos racionais (viés sob ruído).
- Critério de seleção com simulação curta (50 amostras) no modo padrão não
  detecta divergências de longo prazo.
- Supervisores avaliados com horizonte de desfecho de 25 gerações; efeito das
  ações frequentemente nulo em regime estagnado.
- LLM não avaliado (depende de orçamento autorizado); política neural não
  justificada pelo volume de dados.
- Comparar com mais referências (p.ex. modelos de espaço de estados, redes) e
  com o conjunto completo de estimação.

## 9. Material suplementar recomendado

Código e scripts versionados; `EXPERIMENT_LOG.md`; configurações; relatórios
finais por execução (JSON) e trajetórias de agentes (JSONL); `PROVENANCE.json`
com SHA-256; binários do código original para reprodução da linha de base;
instruções de reprodução (`docs/EXPERIMENTS.md`).

## 10. Referências verificadas (fonte entre parênteses)

1. J. Schoukens, J. Suykens, L. Ljung, *Wiener–Hammerstein benchmark*, 15th IFAC SYSID, Saint-Malo, 2009 (página do benchmark).
2. T. Wigren, J. Schoukens, *Three free data sets for development and benchmarking in nonlinear system identification*, ECC 2013, pp. 2933–2938, doi:10.23919/ECC.2013.6669201 (página do benchmark).
3. M. Schoukens, J.P. Noël, *Three benchmarks addressing open challenges in nonlinear system identification*, 20th IFAC World Congress, 2017, pp. 448–453, doi:10.1016/j.ifacol.2017.08.071 (página do benchmark).
4. M. Schoukens, P. Mattsson, T. Wigren, J.P. Noël, *Cascaded tanks benchmark combining soft and hard nonlinearities*, 4TU.ResearchData, doi:10.4121/12960104 (registro 4TU).
5. M. Schoukens, M. Champneys, G.I. Beintema, T.J. Rogers, *Benchmarking for nonlinear system identification: submission platform and baseline results*, Data-Centric Engineering 7:e40, 2026, doi:10.1017/dce.2026.10067 (página inicial do site).

**A verificar antes de citar** (vêm do README do projeto, não conferidos na
fonte nesta sessão): Zhang & Sanderson 2009 (JADE, IEEE TEVC 13(5):945–958);
Billings 2013 (NARMAX, Wiley); Chen, Billings & Luo 1989 (IJC 50(5):1873–1896);
Storn & Price 1997 (JGO 11(4):341–359); Schwarz 1978 (Ann. Statist. 6(2):461–464);
Auer, Cesa-Bianchi & Fischer 2002 (UCB1); Takagi & Sugeno 1985.
