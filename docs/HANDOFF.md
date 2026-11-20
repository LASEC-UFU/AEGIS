# AEGIS — Documento de passagem (handoff) para continuidade por outro agente

Última atualização: 2026-11-20 ~10:43 (horário local, UTC−3), após a análise
arquitetural. O registro original da auditoria é de ~09:56. Leia este arquivo inteiro antes de agir.
Ele é autocontido; os demais documentos citados dão o detalhe.

---

## 0. Ação imediata ao assumir

1. Verifique se os processos de experimento ainda rodam (ver §4) — **não os
   interrompa** e não recompile `cpp/build/aegis_core.dll` enquanto rodarem
   (o arquivo fica bloqueado no Windows e o motor está congelado para o
   estudo).
2. Leia §1 (regras do usuário — obrigatórias) e §5 (o que falta fazer).
3. Não faça commit, push, release nem chamadas pagas (§1).

### 0.1 Continuação mais recente — análise arquitetural concluída

Pedido atendido: `docs/PROMPT_ANALISE_ARQUITETURA.md`, **analisar e propor**,
sem implementar mudanças grandes antes da aprovação do desenho. Foram lidos
handoff, auditoria/correções, diário, literatura, configuração/interface,
benchmarks/experimentos e preparação do artigo; o fluxo foi conferido no C++,
nos agentes Dart e nas ferramentas. Entregas para leitura e aprovação:

1. `docs/architecture/01_ARQUITETURA_ATUAL.md`: diagrama, fluxo real,
   referências arquivo:linha, gargalos e divergências entre contrato e código.
2. `docs/architecture/02_LITERATURA.md`: **estendido**, §10–§12; novas
   verificações, tentativas de [S], técnicas e limites de comparabilidade.
3. `docs/architecture/03_PROPOSTA_INTEGRADA.md`: ajustar coeficientes e
   intercepto por simulação, admissibilidade longa e arquivo erro–tamanho;
   DE/JADE, ilhas, papéis/regimes, currículo e equação NARX preservados.
4. `docs/architecture/04_PLANO_EXPERIMENTAL.md`: plano A1 anterior às
   execuções; hipóteses/ablações, custo interno debitado, sementes e benchmarks
   reservados, falhas e critérios explícitos. Aprovação ainda pendente.
5. `docs/architecture/05_IMPLEMENTACAO_PRIORIZADA.md`: passos reversíveis,
   testes e gates, primeiro infraestrutura/ajustador, agentes só depois.
6. `docs/architecture/06_CAPACIDADE_E_AJUSTE.md`: complemento solicitado pelo
   usuário: campeões com quatro coeficientes vs base pNARX de aproximadamente
   40, e bons resultados frequentemente treinados por erro de simulação.
   Conferido teto atual de oito regressores/nove coeficientes; proposto H8,
   fatorial de capacidade × γ × QR/LM, controles de base/atrasos e orçamento.
   O teto futuro depende desse estudo; não aumentar o teto histórico. Os
   documentos 01–05 e literatura foram integrados a esse complemento.

7. `docs/architecture/07_PARECER_REVISAO.md`: parecer crítico sobre 03–06,
   pedido pelo usuário e escrito por outro agente.
   - **Concorda:** com o diagnóstico e a direção.
   - **Propõe:**
     - uma **Fase 0** de poucos dias antes da infraestrutura: E1
       capacidade em estruturas fixas, E2 LM em estrutura fixa, E3
       fatorial só por configuração no binário 1.1.0;
     - baselines internos no mesmo protocolo;
     - Jacobiano exato por sensibilidades recursivas;
     - LM de horizonte completo primeiro;
     - H9, uma espinha linear fora do limite de regressores;
     - H8 reduzido a 8 células com α = 0.
   - **Rejeita ou adia:**
     - P0 completo antes de evidência;
     - agentes v2 neste ciclo;
     - EMPS como benchmark primário;
     - o comparador do 06 §6.2.
   - **Fatos novos:**
     - o recozimento de γ ficou inerte no 1.1.0 (γ ≤ 0,0118, porque o
       progresso é por `maxGenerations` = 100000);
     - γ = 0,01 por fator vale cerca de 60 % do RMSE de um passo na
       validação do CT;
     - as sementes ARX relevantes não cabem em `maxRegressors` = 8.
   - **Decisão pendente do usuário:** quando abrir os testes WH/SB da
     iteração 2, dado o conflito com a confirmação do A1 (§6 do parecer).

Achados importantes: `simulation` muda a pontuação, não o ajuste QR;
refinador usa um passo, só em racionais, com intercepto fixo; diagnóstico
longo não veta o campeão; escape de migração aceita finitos sem exigir
melhora no destino; cache de estrutura não identifica coeficientes refinados;
contador atual não inclui todo o pós-processamento/diagnóstico. **Nada disso
foi alterado no motor congelado.**

Literatura: conferidos Volterra feedback CT **0.3972 V** (Schoukens/Scheiwe
2016, Tab. 1, DOI não identificado) e Volterra grau 3 **0.54 V com remoção
de transientes / 2.08 V sem ela** (Birpoutsoukis et al. 2018, Tab. 1,
DOI 10.1016/j.ymssp.2017.10.007). Não equiparar a remoção de transiente
ao descarte `n_ini=50`. Demais números não confirmados continuam [S].

Estado observado ~10:43: processo `aegis_batch` PID 118748 ativo desde
10:34:32, WH `no_freerun`; WH `aegis_full`, `aegis_sim`, `de_rand1`,
`single_island` e `no_curriculum` concluíram 10/10 segundo o log. Não
interromper; revalidar processo e log na próxima sessão. Nenhum teste WH/SB
foi inspecionado nesta análise; nenhuma compilação, execução experimental
nova, chamada paga, commit ou publicação. A próxima etapa arquitetural é
**aprovação do desenho**, não implementação automática. Os resultados do
protocolo histórico continuam pendentes e não são requisito para entregar
esta análise; não usá-los para escolher o novo desenho.

Correções do estado anterior: a avaliação CT sementes 11–20 já foi analisada
(40 runs; `docs/EXPERIMENTS.md` e diário). Fuzzy aprendida sem ganho; UCB1
pior, p Holm=0.0469. O analisador já aceita `--evaluations <nome.jsonl>` com
`--out` explícito para reavaliações separadas; teste de ingestão passou na
continuação anterior. Falta gerar reavaliações Silverbox após o protocolo;
ainda não há máscara de arrow sem extrapolação. Essas alterações precedem
esta análise, que alterou apenas documentação.

Revalidação ao concluir a documentação: WH `no_freerun` também terminou
10/10; `polynomial_only` está ativo no PID 142780 desde 10:44:25. SHA-256
da DLL igual nas duas leituras desta tarefa:
`78de34e1c9aa7ba850da41c60946261b18a0287c077784e4e8e006f4d1bd55e6`.
Links Markdown locais e cercas de código dos seis documentos conferidos.
Não foram rodados testes de software novos, pois esta tarefa alterou só
documentação. A aprovação do desenho segue pendente, conforme o prompt;
a análise solicitada, incluindo os dois complementos do usuário, está entregue.

---

## 1. Regras do usuário (obrigatórias, vindas do pedido original)

- Trabalhar na cópia existente em `C:\SourceCode\AEGIS` (repo `LASEC-UFU/AEGIS`,
  branch `main`, HEAD `9e4b1d8`). Não clonar/baixar o projeto de novo.
- **Sem commit, push, release ou publicação remota** sem autorização explícita.
- Não descartar/reverter alterações sem identificar origem e impacto; antes de
  apagar/sobrescrever dados **fora** do AEGIS, parar e consultar o usuário.
- Não alterar outros projetos/arquivos do computador. Privilégios de admin só
  se realmente necessários para dependências desta tarefa.
- **Não fabricar resultados nem manipular dados**; registrar resultados
  desfavoráveis, falhas e limitações.
- **Credenciais:** não pedir que o usuário cole segredos na conversa; não gravar
  tokens em código/logs/arquivos versionados; usar variável de ambiente
  (`ANTHROPIC_API_KEY`) ou arquivo git-ignorado. **Não fazer chamadas pagas sem
  informar provedor, finalidade, nº estimado de chamadas e custo e obter
  confirmação específica do usuário.** Nenhuma chamada paga foi feita até agora.
- O teste de cada benchmark **nunca** pode ser usado para escolher estrutura,
  parâmetros ou critério de parada. Divisão temporal.
- O usuário pediu explicitamente para **não usar Python**: manter tudo em
  C++ e Dart (bash como cola). A pasta `python/` existente é legada; não alterar
  nem depender dela. (Alguns one-liners `node -e` foram usados só para
  inspeção ad hoc; não fazem parte de nenhum pipeline.)
- Comunicação com o usuário em português.

---

## 2. Contexto do pedido (resumo)

Auditoria completa do AEGIS (identificação NARX polinomial/racional por DE com
JADE, ilhas, currículo, UCB1, agente LLM, núcleo C++/FFI/WASM, UI Flutter),
correções, interface tipada para agentes (LLM e locais), base para política
local aprendida (fuzzy primeiro; neural só se os dados justificarem), testes,
benchmarks públicos com proveniência, ablações com ≥ 10 sementes, e preparação
de material para artigo na **IFAC Journal of Systems and Control (IFAC-JSC)**
(estrutura: Abstract, Introduction, Methods, Results, Discussion, Conclusions,
References; usar modelo Elsevier do periódico, não o de congresso IFAC).
Entregáveis finais listados no pedido: diagnóstico, problemas e evidências,
alterações/arquivos, dependências, testes e comandos, benchmarks/proveniência/
licenças, resultados completos incluindo falhas, comparação de agentes e
políticas, limitações, etapas que dependem de token/decisão do usuário,
instruções de reprodução, estado final do repositório.

---

## 3. O que já foi feito

### 3.1 Documentos (ler nesta ordem)

| Arquivo | Conteúdo |
|---|---|
| `docs/audit/00_ESTADO_INICIAL.md` | estado do repo, ambiente, linha de base de testes (8 passam / 3 falham no original; batch 0/2) |
| `docs/audit/01_AUDITORIA.md` | lista priorizada P0/P1/P2 com evidência, impacto, correção e teste |
| `docs/audit/02_CORRECOES.md` | o que foi corrigido por item, arquivos, testes, pendências |
| `experiments/EXPERIMENT_LOG.md` | **diário científico**: iterações 0, 1 (descartada) e 2 (final), decisões e divulgação de que o teste do CT foi visto na iteração 1 |
| `docs/CONFIGURATION.md` | todas as chaves de configuração do núcleo |
| `docs/AGENT_INTERFACE.md` | observação, ações, códigos de rejeição, trajetórias, agentes, custo do LLM |
| `docs/BENCHMARKS.md` | fontes, licenças, citações, SHA-256, pré-processamento, desvio de protocolo |
| `docs/EXPERIMENTS.md` | ambiente, build, dados, scripts, análise, tabela de condições |

### 3.2 Código (árvore de trabalho, sem commit)

`git status` mostra ~50 arquivos modificados e novos diretórios
(`cpp/tools/`, `docs/`, `experiments/`, `tool/`, testes novos). Principais:

- **C++** (`cpp/`): normalização sem clamp; base de potência `powerMode`
  (hybrid/signed/legacy) + `exponentStep`; QR correto com colunas dependentes;
  Ψ calculada uma vez (~15× mais rápido); avaliador com ERR guloso, indicador de
  contribuição de entrada com AR primeiro, linha de pontuação comum
  (`score_start = maxDelay`), `errorMode` (`one_step`/`simulation`); simulação
  livre com detecção de divergência; diagnósticos de estabilidade novos;
  `diagnose()` (ACF real, CCF, simulação na validação completa, sobre/subajuste);
  DE reescrito (geração única p/ async e lockstep, campeão canônico com hall of
  fame, crossover que encolhe/cresce, mutação estrutural, `rand1`, orçamento
  `maxEvaluations`, estatísticas por ilha, `numThreads` efetivo); pipeline
  reescrito (config JSON robusta `json_lite.hpp`, interface de ações tipada com
  limites/passo/cooldown/trava de orçamento/kill switch, registro de trajetória
  com desfecho, modo `syncMode`, pós-processamento poda/refino aceitos só se não
  piorar, relatório final com métricas por partição em unidades originais);
  WebSocket seguro; API C nova (`aegis_apply_action`, `aegis_get_final_report`,
  `aegis_get_history`, `aegis_evaluate_model`, …); `aegis_batch` reescrito;
  ferramentas `aegis_frols`, `aegis_evaluate_models`; testes `core_tests.cpp`
  (91 verificações) e `api_tests.cpp` (66).
- **Dart** (`lib/`): `snapshot_parser.dart` compartilhado; serviço FFI com ações
  tipadas e símbolos opcionais; `GenerationSnapshot` estendido (+`IslandStatus`,
  `toObservation()`); `OptimizationAgent` com `AgentDecision`, `consult()`,
  `onActionResult`; UCB1 corrigido; **novo** `FuzzyPolicyAgent` (Takagi–Sugeno,
  base JSON); LLM reescrito (`llm_agent_core.dart`, HTTP direto, JSON schema,
  `claude-opus-5-5`, timeout, orçamentos, recusa/fallback); motor Dart com base
  híbrida, intercepto e sem clamp; UI: modo Fuzzy no seletor, exportação JSON com
  relatório final/log/decisões.
- **Ferramentas** (`tool/`): `benchmarks/mat5.dart` (leitor MAT v5),
  `benchmarks/prepare_benchmarks.dart`, `experiments/run_agent_experiment.dart`
  (compilado em `experiments/bin/aegis_agent_runner.exe`),
  `experiments/analyze.dart`, `experiments/learn_fuzzy_policy.dart`,
  `experiments/select_frols.dart`, `experiments/capture_snapshot_fixture.dart`.
- **Experimentos** (`experiments/`): `configs/` (padrão, 11 condições,
  config do código original), `scripts/` (`run_protocol.sh`,
  `run_conditions.sh`, `run_agents.sh`, `run_legacy_head.sh`, `run_frols.sh`,
  `run_policy_eval.sh`), `tools/legacy_head_runner.cpp`, `policies/`.
  Git-ignorados (confirmado com `git check-ignore`): `experiments/data/`,
  `results/`, `results_archive/`, `results_policy_eval/`, `bin/` e `*.log`.
  Versionáveis: `EXPERIMENT_LOG.md`, `configs/`, `scripts/`, `tools/`, `policies/`.
- Outros: `pubspec.yaml` (+`crypto` como dev_dependency, já resolvida),
  `.gitignore`, README/README_BR (avisos e correções), `.github/workflows/deploy.yml`
  (build Windows restrito ao alvo `aegis_core`).

### 3.3 Verificação (última execução, toda aprovada)

```bash
export PATH="/c/SourceCode/tools/msys64/ucrt64/bin:$PATH"   # MinGW (não há MSVC)
cmake --build cpp/build -j 16
cpp/build/core_tests.exe      # 91 checks, 0 failures
cpp/build/api_tests.exe       # 66 checks, 0 failures
flutter test                  # 28 testes (inclui consistência C++×Dart e mocks do LLM)
dart analyze lib test tool    # sem problemas
```

---

## 4. Processos em execução (no momento da escrita)

### 4.0 Incidente de 2026-11-20 e retomada (LER PRIMEIRO)

**O que aconteceu**
- A máquina congelou por volta das 11:12 e foi reiniciada à força às 15:34
  (Kernel-Power 41, sem tela azul, sem botão de energia, sem erro WHEA).
- O protocolo tinha concluído WH `aegis_full`, `aegis_sim`, `de_rand1`,
  `single_island`, `no_curriculum`, `no_freerun`, `polynomial_only` e
  `agent_ucb1`: 10/10 em cada, 80 JSON validados depois do reinício.
- O travamento ocorreu cerca de 2 minutos depois do início das 10 execuções
  de WH `agent_fuzzy`, junto com um `dart run` de um script curto da sessão.
- Os arquivos vazios dessa condição foram movidos para
  `experiments/results_archive/interrupted_2026-11-20_wh_agent_fuzzy/`.

**Causa:** não determinada.
- Não há evento de limitação térmica nem de erro de hardware.
- A temperatura real da CPU não é legível sem um driver de sensores. As zonas
  ACPI dessa placa mostram valores fictícios.
- **Esta máquina já teve desligamentos inesperados em 04/11 (22:00) e 09/11
  (06:36), antes desta sessão.**
- Fatores possíveis, a verificar pelo usuário:
  - 4 × 16 GB DDR4 a 3200 MT/s com XMP (Kingston KF3200C16D4/16GX), acima
    da especificação AMD para dois módulos por canal. Os módulos são
    provavelmente dual-rank; a especificação é 2666 para dual-rank.
  - BIOS FB de 11/2022.
  - Temperatura sob carga contínua.

**Retomada:** `experiments/scripts/run_protocol_resume.sh`, log em
`experiments/results/protocol_resume.log`.
- Roda WH `agent_fuzzy`, as 7 condições de SB e o código original em WH e SB.
- Limites de carga:
  - 6 processos paralelos;
  - 4 para o código original, que usa 3 threads por execução;
  - prioridade BelowNormal herdada pelos filhos.
- Um monitor grava RAM livre, CPU e número de processos a cada 60 s em
  `experiments/results/protocol_monitor.log`.
- Os resultados não mudam com o paralelismo (semente fixa, 1 thread); só o
  `wallSeconds` deixa de ser comparável com as etapas rodadas a 16 jobs.

**Regra daqui em diante:**
- no máximo 6 processos de cálculo simultâneos nesta máquina;
- nada de compilação ou script extra enquanto o protocolo roda.

**Código e documentos estão no branch remoto `audit/aegis-1.1.0-wip`:**
- não houve push na `main`, porque ela dispara deploy e release;
- dados e resultados estão fora do git (`.gitignore`).

| Tarefa | Comando | Log | Estado |
|---|---|---|---|
| Protocolo principal | `experiments/scripts/run_protocol.sh` | `experiments/protocol.log` | CT completo; WH `aegis_full` 10/10; WH `aegis_sim` em andamento (09:53). Restam WH: de_rand1, single_island, no_curriculum, no_freerun, polynomial_only + agentes ucb1 e fuzzy; depois Silverbox (7 condições); depois `run_legacy_head.sh` WH e SB (1000 gerações) |
| Política aprendida (sementes 11–20, CT) | `ONLY_LEARNED=1 experiments/scripts/run_policy_eval.sh cascaded_tanks 300000 6` | `experiments/policy_eval_learned.log` | relançado após correção de caminho (o 1º disparo falhou com caminho MSYS `/c/...`) |

Duração estimada: ~10 min por condição no WH/SB com 16 jobs; o protocolo
completo leva algumas horas (até ~13–14 h local). Progresso:

```bash
tail -5 experiments/protocol.log
for d in experiments/results/*/*/; do echo "$d $(ls $d/run_*.json 2>/dev/null | wc -l)"; done
```

Cada `run_<seed>.json` contém o relatório final (com métricas de **teste**).
Regra adotada: **não inspecionar métricas de teste de WH e Silverbox antes do
fim do protocolo**; a análise final é feita uma vez, por `analyze.dart`.

Se for preciso interromper: matar os processos `aegis_batch.exe`,
`aegis_agent_runner.exe`, `legacy_head_runner.exe` e o `bash` do script;
registrar no `EXPERIMENT_LOG.md`.

---

### 4.1 Retomada se os processos tiverem parado

Os lotes foram iniciados como tarefas em segundo plano da sessão anterior e
**podem ter sido encerrados junto com ela**. Verifique quantas execuções
existem por condição (comando acima). Cada script grava `run_<seed>.json`
completo ou nada; condições incompletas devem ser **refeitas inteiras** (apague
só o diretório daquela condição, registre no `EXPERIMENT_LOG.md`). Comandos,
na ordem do protocolo (pule o que já estiver com 10 execuções):

```bash
cd /c/SourceCode/AEGIS
S=experiments/scripts
CORE="aegis_full aegis_sim de_rand1 single_island no_curriculum no_freerun polynomial_only"
$S/run_conditions.sh wiener_hammerstein 150000 16 10 <condições faltantes de $CORE>
$S/run_agents.sh wiener_hammerstein 150000 10 10 ucb1
$S/run_agents.sh wiener_hammerstein 150000 10 10 fuzzy
$S/run_conditions.sh silverbox 150000 16 10 $CORE
$S/run_legacy_head.sh wiener_hammerstein 1000 10 10
$S/run_legacy_head.sh silverbox 1000 10 10
ONLY_LEARNED=1 $S/run_policy_eval.sh cascaded_tanks 300000 6   # se agent_fuzzy_learned < 10
```

Não recompile o núcleo antes de terminar o protocolo (motor congelado). O
executor Dart já compilado é `experiments/bin/aegis_agent_runner.exe`; se for
preciso recompilá-lo: `dart compile exe tool/experiments/run_agent_experiment.dart -o experiments/bin/aegis_agent_runner.exe`.

Estado no momento do encerramento (~10:00): CT completo (todas as condições,
agentes, código original, FROLS); WH `aegis_full` 10/10, `aegis_sim` em
andamento; FROLS de WH e SB prontos; avaliação da política aprendida: `aegis_full`,
`agent_fuzzy`, `agent_ucb1` e `agent_fuzzy_learned` concluídas (sementes 11–20;
conferir 10 execuções em cada) — falta só analisá-las com `analyze.dart`.

## 5. O que falta fazer (em ordem)

1. **Quando o protocolo terminar**, rodar a análise (não alterar o motor):
   ```bash
   dart run tool/experiments/analyze.dart --results experiments/results/cascaded_tanks --title "Cascaded Tanks" --convergence aegis_full,aegis_sim,de_rand1,agent_fuzzy
   dart run tool/experiments/analyze.dart --results experiments/results/wiener_hammerstein --title "Wiener-Hammerstein" --convergence aegis_full,aegis_sim,de_rand1,agent_fuzzy
   dart run tool/experiments/analyze.dart --results experiments/results/silverbox --title "Silverbox (test multisine)" --convergence aegis_full,aegis_sim,de_rand1,no_curriculum
   dart run tool/experiments/analyze.dart --results experiments/results_policy_eval/cascaded_tanks --title "CT unseen seeds 11-20"
   ```
   Silverbox também tem o teste **arrow** (extrapolação): reavaliar os modelos
   salvos com `aegis_evaluate_models` usando `--data-test experiments/data/processed/silverbox/test_arrow.csv`
   e `--config experiments/configs/aegis_default.json` (refit 0), ver
   `cpp/tools/evaluate_models.cpp`; o `analyze.dart` ainda **não** lê esse
   arquivo `.jsonl` para condições novas (só para `legacy_head/evaluations.jsonl`)
   — escrever um pequeno passo ou estender o analisador.
2. Abrir os SVGs gerados (`analysis/boxplot_test_freerun.svg`,
   `convergence.svg`) e verificar visualmente (rótulos, sobreposição). Paleta
   validada com o validador do skill dataviz (azul/laranja/água/violeta).
3. Registrar no `EXPERIMENT_LOG.md` a conclusão do protocolo (horário, nº de
   execuções completas, falhas).
4. **Preparação do artigo IFAC-JSC**: rascunho já criado em
   `docs/paper/IFAC_JSC_PREPARACAO.md` (títulos, resumo provisório sem números,
   descrição matemática, protocolo, tabelas/figuras previstas, afirmações
   sustentadas × não sustentadas, limitações, suplementar, referências
   verificadas e a verificar) e esqueleto `paper/manuscript.tex`
   (`elsarticle`). **Falta**: preencher §6–§7 com os resultados de WH/SB após a
   análise única, revisar as afirmações à luz deles e gerar a figura F4
   (saída medida × simulada). Fatos verificados: IFAC-JSC é de acesso aberto, publicado pela Elsevier
   (página de periódicos da IFAC); a Elsevier recomenda a classe `elsarticle`
   (CTAN v3.5, 2026-01-09, LPPL 1.3; pacote
   `https://assets.ctfassets.net/o78em1y1w4i4/4MpsJHO0MOJ2xZuwGTAbOZ/7bc64af36477c5d6cfce335a1f872363/elsarticle.zip`).
   **Não foi possível ler o Guide for Authors** (ScienceDirect retorna 403 para
   acesso automatizado) → tipos de artigo, limites de tamanho, estilo de
   referência, highlights e declarações devem ser conferidos manualmente pelo
   usuário. Não usar o template de congresso IFAC-PapersOnLine.
5. **Comparação com a literatura: FEITA em 2026-11-20.** Está em
   `docs/architecture/02_LITERATURA.md`, com números conferidos nos
   originais, marcados [C], e citações secundárias, marcadas [S]. Lá também
   estão as regras de comparabilidade, as divergências e os SHA-256 das fontes.
   - **Referência comparável:** DCE 2026 (Schoukens, Champneys et al.,
     DOI 10.1017/dce.2026.10067, CC BY). Usa o mesmo protocolo `n_ini` do
     AEGIS.
   - **CT (V) no DCE 2026:**
     - LTI SS 0.600, ARX 0.682;
     - pNARX univariado 0.417;
     - LSTM 0.452, OLSTM 0.427.
   - **AEGIS no CT:** aegis_full tem mediana 0.661 e mínimo 0.656 em 10
     sementes. Fica **pior que o LTI SS** e melhor só que o ARX.
   - **Melhores publicados no CT:**
     - 0.19 V grey-box (Worden 2018);
     - 0.22–0.30 V CT-SUBNET;
     - 0.298 V ASIA (agente LLM);
     - 0.30 V TNBS-NARX.
   - **Método mais parecido com o AEGIS:** TAG-GP de Khandelwal (tese TU/e
     2020), com 23.5 mV no WH contra 0.24 mV do SUBNET.
   - **Pendências:** os valores [S] listados no fim do documento. Os testes
     WH/SB do AEGIS não foram usados nessa comparação.
6. **Relatório final ao usuário** (em português) cobrindo os 12 entregáveis do
   pedido (§2), com resultados completos inclusive desfavoráveis.
6. Opcional: remover o método morto
   `IndividualEvaluator::compute_input_contribution_ratio` (não usado) — só
   depois do protocolo, e rodar de novo `core_tests`/`api_tests`. (Já feito: o
   painel do agente mostra as decisões do agente, a origem e o desfecho de cada
   ação; `dart analyze` limpo e testes de widget aprovados após a mudança.)

### Etapas que dependem do usuário

- **Agente LLM**: precisa de `ANTHROPIC_API_KEY` definido pelo próprio usuário
  (variável de ambiente ou `anthropic_api_key.txt` ao lado do executável,
  git-ignorado). Custo estimado: modelo `claude-opus-5-5` (US$ 4/20 por milhão
  de tokens entrada/saída), ≈ 2–4 mil tokens de entrada por consulta →
  ≈ US$ 0,02–0,06 por consulta; uma execução de 3×10⁵ avaliações no CT tem
  ~40 consultas (`consultEvery=50`) → ≈ US$ 1–2,5 por semente; 10 sementes ≈
  US$ 10–25 (orçamento por execução limitado por `--max-cost`, padrão 5).
  Comando (só após confirmação explícita do custo):
  `experiments/scripts/run_agents.sh cascaded_tanks 300000 2 10 llm`.
- Licenças de WH e Silverbox não declaradas → confirmar com os mantenedores
  antes de publicar dados derivados.
- Autorização para commit/push (sugestão: commits por tema — núcleo numérico,
  DE/pipeline, interface de agentes, agentes Dart, ferramentas/experimentos,
  documentação).

---

## 6. Resultados disponíveis até agora (não definitivos)

**Cascaded Tanks** (atenção: o teste do CT foi visto durante a iteração 1, ver
EXPERIMENT_LOG; tratar como benchmark de desenvolvimento). 10 sementes,
3×10⁵ avaliações, métrica = RMSE de simulação no teste (V), Wilcoxon pareado +
Holm vs `aegis_full` (`experiments/results/cascaded_tanks/analysis/SUMMARY.md`):

| Condição | mediana [IQR] | divergências | p (Holm) |
|---|---|---|---|
| aegis_full | 0,661 [0,659; 0,662] | 0 | ref. |
| legacy_head (código original) | 0,678 [0,658; 0,761] | 0 | 1,00 (Mann–Whitney) |
| agent_fuzzy | 0,658 | 0 | 1,00 |
| agent_ucb1 | 0,734 | 0 | 0,14 |
| aegis_sim | 0,687 | 0 | 0,97 |
| de_rand1 | 0,742 | 0 | 0,66 |
| no_curriculum | 0,714 | 0 | 0,078 |
| no_freerun | 0,748 | 0 | 0,66 |
| polynomial_only | 0,660 | 0 | 1,00 |
| signed_continuous | 0,884 | 2 | **0,025** (pior) |
| single_island | 32,4 (saturado) | 6 | **0,025** (pior) |
| no_roles_regimes | 32,4 (saturado) | 6 | **0,043** (pior) |
| FROLS (n=1, determinístico) | 0,752 | 0 | — |

Leituras: nenhuma vantagem significativa do AEGIS corrigido sobre o código
original nem dos agentes; no teste, o RMSE one-step mediano é 0,053 V
(original) × 0,069 V (corrigido) e o de simulação 0,678 × 0,661 V; sem papéis/regimes de ilha ou com ilha
única, 6/10 campeões divergem na simulação longa de teste (o critério de
validação com horizonte de 50 amostras não detecta isso). `aegis_full` e
`no_postprocessing` são idênticos (poda/refino não alteraram nenhum campeão).

**Aprendizado da política fuzzy** (CT sementes 1–10, 409 ações conclusivas de
UCB1+fuzzy): utilidade ~0 para R1, R2, R4 (as ações não mudaram o campeão em
25 gerações); R7 (`freeRunPenalty`) levemente negativa → desativada na base
`experiments/policies/fuzzy_learned_ct.json` (relatório `_report.json`).
Avaliação em sementes 11–20 em andamento (`experiments/results_policy_eval/`).
Não há dados que justifiquem uma política neural.

**FROLS** (seleção pela validação): CT ny=nu=5 grau 3 (7 termos); WH ny=nu=10
grau 3 (24 termos, validação 13,6 mV); SB ny=nu=10 grau 3 (12 termos,
validação 2,0 mV).

**Agentes no CT**: UCB1 273 ações aceitas, fuzzy 232, 0 rejeitadas pelo núcleo;
muitas decisões "no_action"/"insufficient_evidence" (registradas).

---

## 7. Armadilhas conhecidas (gotchas)

- **Compilador**: só MinGW-w64 (g++ 16.2 em `C:\SourceCode\tools\msys64\ucrt64\bin`;
  pôr no PATH). DLL sai como `aegis_core.dll` (PREFIX vazio) com runtime estático.
  Não há MSVC nem Emscripten nesta máquina (app Windows e WASM não compiláveis
  aqui).
- **DLL bloqueada**: se `cmake --build` falhar com "Permission denied" em
  `aegis_core.dll`, algum processo a está usando — localizar com PowerShell
  (`Get-Process | ... Modules`) antes de qualquer ação.
- **Caminhos**: executáveis nativos Windows não entendem `/c/...` embutido em
  argumentos compostos (ex.: `fuzzy:/c/...`); usar `cygpath -m`.
- **Fim de linha**: `core.autocrlf=true`; arquivos reescritos estão em LF, o
  Git normaliza — `git diff` mostra apenas mudanças reais.
- `flutter pub get` regenera `windows/flutter/generated_*` só com mudança de
  EOL; restaurar com `git checkout -- windows/flutter/`.
- `Running build hooks...` do `dart run` sai sem quebra de linha e pode engolir
  a primeira linha de saída em pipelines com `grep`.
- Arquivo legado `Benchmarks/WH_estimation_uy.csv` **não** corresponde ao WH
  oficial; não usar para afirmações científicas.
- Resultados antigos (`assets/avaliacao_cientifica.md`, R² = 0,99998) são
  one-step em dados normalizados com o código defeituoso; não citar.
- `experiments/results_policy_eval/` foi acrescentado ao `.gitignore`.

---

## 8. Ambiente

AMD Ryzen 9 5950X (16C/32T), 64 GB, Windows Server 2025 (10.0.26100),
Flutter 3.44.2 / Dart 3.12.2, g++ 16.2.0 (MSYS2 UCRT64), CMake 4.4.3, Ninja.
Python 3.12 existe na máquina mas **não deve ser usado** (pedido do usuário).
Nenhuma dependência de sistema foi instalada; única dependência nova:
`crypto` (dev_dependency Dart, já presente transitivamente no lock).
