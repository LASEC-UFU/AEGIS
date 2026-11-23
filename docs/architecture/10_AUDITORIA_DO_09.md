# 10 — Auditoria do documento 09 (estados transpostos e identificação incremental)

Data: 2026-11-23. Auditado:
[09_ESTADOS_TRANPOSTOS_IDENTIFICACAO.md](09_ESTADOS_TRANPOSTOS_IDENTIFICACAO.md),
escrito por outro agente a pedido do usuário. O nome do arquivo tem um erro
de digitação ("TRANPOSTOS"); ele foi mantido para não quebrar referências.
O documento 09 parte do
[08_REALIZACAO_TDF.md](08_REALIZACAO_TDF.md), escrito pelo autor desta
auditoria, e esta auditoria também corrige o 08 (§8).

**Método:**
- conferência de cada afirmação [código] do 09 no código da árvore
  `audit/aegis-1.1.0-wip`;
- leitura dos núcleos de custo do avaliador (`individual_evaluator.cpp`,
  `regressor_library.cpp`, `rational_model.cpp`, `de_optimizer.cpp`);
- análise de escala dos tempos de parede do E3
  (`experiments/results_phase0/SUMMARY_E3.md`).

**Restrições:**
- nada foi compilado nem executado além do resumo do E3;
- só foram lidos dados de **validação** e tempos de parede; nenhum dado de
  teste foi aberto.

Etiquetas: **[código]** conferido no código; **[dado]** tirado dos resumos;
**[inferência]** conclusão dos dados com as ressalvas declaradas;
**[recomendação]** proposta desta auditoria.

---

## 1. Veredito

1. **A matemática do 09 está correta** nos pontos conferidos: a regra de
   validade dos estados (§3.3), a fórmula de ΔSSE (§5), a derivada da
   divisão (§6.1), a derivada em p e a descontinuidade da base `hybrid`
   (§6.3).
2. **Quase todos os fatos de código estão corretos.** Há uma citação de
   linhas imprecisa (§2 desta auditoria).
3. **O diagnóstico de custo do 09 está incompleto, e isso muda a ordem das
   prioridades.** Os dados do E3 e a leitura do avaliador indicam que, nos
   modelos grandes, o custo por avaliação é dominado por **álgebra densa
   O(N·K²)**:
   - um QR de Householder;
   - **duas** passagens gulosas de ERR.

   A simulação livre, alvo dos anéis transpostos do 08 e do 09, é uma
   fração pequena do tempo (§3).
4. **Existem ganhos que mantêm o resultado bit a bit idêntico** e que nem o
   08 nem o 09 mencionam:
   - calcular o vetor ERR completo só quando necessário: ele **não entra
     no fitness**;
   - reordenar os laços do QR para acesso contíguo à memória;
   - usar cache de fatores na montagem de Ψ.

   Com eles é possível acelerar sem alterar nenhuma trajetória de busca, e
   a prova de equivalência é simples: reproduzir execuções já feitas.
5. **O QR incremental e a vizinhança dirigida do 09 não aceleram o laço
   atual do DE.** Os filhos do JADE diferem do pai em quase todos os
   regressores (§4.3). Esses mecanismos só servem a um **operador novo**,
   que é pesquisa, não otimização.
6. **Recomendação de ordem:**
   1. medir;
   2. otimizações exatas;
   3. otimizações quase exatas;
   4. mudanças de estimador;
   5. operador dirigido;
   6. sensibilidade adjunta.

   Os anéis transpostos ficam no trilho de ponto fixo e implantação, não
   no trilho de velocidade (§6).

---

## 2. Conferência dos fatos marcados [código] no 09

| Afirmação do 09 | Situação | Observação |
|---|---|---|
| `Regressor::evaluate` multiplica `power_basis` dos fatores (`regressor_library.cpp:37`); `build_psi_matrix` percorre fatores em todas as linhas (`:131`) | **Confirmada** | `build_psi_matrix` usa `int_power` para inteiros e retorno direto para p = 1; `pow` só para fracionários |
| `evaluate` constrói Ψ, ajusta por `fit_from_psi`, calcula ERR, Ψ de validação e simula (`individual_evaluator.cpp:289–379`) | **Confirmada** | O 09 não destaca que **duas** ERR são calculadas por avaliação (`:321` e `:322`). Ver §3.2 |
| Denominador vira `−y_medido·φ` e há intercepto; o QR minimiza erro de equação de um passo (`rational_model.cpp:12–36`) | **Confirmada** | — |
| QR de Householder sem pivoteamento, descarta colunas dependentes (`regressor_library.cpp:190–266`) | **Confirmada** | Limiar de posto global: `eps·max(m,n)·max|A|·10`. A coluna é descartada **em ordem**; trocar a ordem pode mudar qual coluna recebe θ = 0. O alerta do 09 sobre equivalência procede |
| `simulate` copia `md+n` linhas, aquece com y medido, repete a última previsão após divergência (`rational_model.cpp:117–158`) | **Confirmada** | — |
| Expoente contínuo com `exponentStep ≤ 0` (`safe_power.hpp:114–122`) | **Confirmada** | — |
| E3 `mr39_zero_simulation`: mediana K = 22 (CT) e 33 (WH), com intercepto; 874 s e 24 752 s | **Confirmada** [dado] | `numParameters` = regressores + 1 (`identification_pipeline.cpp:1230`) |
| O ajuste começa no maior atraso do próprio cromossomo | **Confirmada** | `build_psi_matrix`, `off = md − delay` |
| Janela comum de atraso 40 proposta no `06_CAPACIDADE_E_AJUSTE.md:184` | **Confirmada** | Linhas 183–187 |
| Risco do cache por hash em `01_ARQUITETURA_ATUAL.md:127–134` | **Imprecisa** | A seção F começa na linha 133 e vai até ~141; 127–132 são da seção E |
| ERR e razão de entrada em `individual_evaluator.cpp:177–246, 321–325` | **Confirmada** | Ver §3.2: uma das duas é dispensável no fitness |
| Referências externas (Billings e Chen; Golub e LeVeque) | **Não conferidas** | Os URLs não foram abertos nesta auditoria. O trabalho clássico de seleção ortogonal costuma ser citado como Chen, Billings e Luo (1989), *Int. J. Control* 50(5); o revisor da bibliografia deve confirmar autores, título e páginas |

**Conferência matemática:**

- **ΔSSE (§5):** com r = y − Aθ ortogonal ao espaço das colunas aceitas e
  q = a − Q(Qᵀa), tem-se qᵀr = aᵀr, e a redução de SSE ao acrescentar a
  coluna é (qᵀr)²/(qᵀq). **Correta**, com as ressalvas que o próprio 09 faz
  (uma coluna por vez, posto, objetivo de um passo).
- **δy = (δN − y·δD)/D (§6.1):** correta para y = N/D, com N incluindo c e
  D incluindo 1.
- **∂g_p/∂p = g_p·ln|x| (§6.3):** correta no ramo sign(x)·|x|^p; o limite
  em x = 0 é 0 para p > 0.
- **Descontinuidade `hybrid` (§6.3):** correta, e só nos **inteiros pares**.
  Para x < 0, em p = 2 vale x² > 0, enquanto p → 2 não inteiro dá
  −|x|^p → −x². Nos ímpares e em p = 1 a base é contínua, porque xⁿ =
  sign(x)·|x|ⁿ. O 09 poderia dizer isso explicitamente.
- **Regra de validade (§3.3):** correta e importante. Ela mostra que
  "editar o anel global" para avaliar uma mutação não é exato quando a
  trajetória de y muda. Isso elimina, para velocidade, a ideia de estados
  por regressor.

---

## 3. Evidência nova: onde está o custo

### 3.1 Escala dos tempos do E3 [dado, inferência]

Tempo por avaliação = mediana do tempo de parede por execução ÷ avaliações.
K = mediana de `numParameters` do campeão.

| Benchmark | N treino | K ≈ 5–7 | K ≈ 8–9 | K ≈ 22–33 |
|---|---|---|---|---|
| CT | ~780–819 | 0,10–0,18 ms | 0,35 ms | 2,9 ms (K 22–25) |
| WH | ~16 000 | 3,6–6,1 ms | 9,0–9,3 ms | 165–183 ms (K 33) |
| SB | ~16 000 | 3,3–6,0 ms | 8,3–8,7 ms | 128 ms (K 32, só `one_step`; a célula `simulation` ainda roda) |

- **Expoente em K:** entre K ≈ 9 e K ≈ 32–33 o tempo cresce com K^2,1 a
  K^2,3 no WH e no SB, e com ~K^1,9 no CT.
- **Escala em N:** CT contra WH com K ≈ 8–9 dá razão ≈ 26. A razão de
  linhas de treino é ≈ 19,5, e corrigindo por (9/8)² fica ≈ 25.
- **Compatível com custo ∝ N·K².**
- **O modo de erro quase não muda o tempo nos modelos grandes:**
  - WH: `mr39_zero_simulation` 24 752 s contra `one_step` 27 432 s;
  - CT: 874 s contra 863 s.
  - No modo `simulation`, cada avaliação simula o segmento de validação
    inteiro; no `one_step`, só 50 amostras. Se a simulação pesasse, o modo
    `simulation` seria claramente mais lento. Não é.
  - Nos modelos pequenos do WH (`mr8_default`), `simulation` leva 38 % a
    mais, mas o K também difere (7 contra 6): (7/6)² = 1,36 explica quase
    tudo.

**Ressalvas:**
- K é o do **campeão**, não a distribuição dos candidatos avaliados;
- o tempo de parede inclui 6 processos concorrentes;
- inclui operações fora da avaliação (DE, migração, diagnósticos);
- esta máquina não é a original.

É uma **indicação forte, não uma medição**. O *profiling* da §6 (P0)
confirma ou derruba.

### 3.2 Leitura do avaliador [código]

Por avaliação (`IndividualEvaluator::evaluate`), sobre o treino com N linhas
e K colunas:

| Etapa | Código | Ordem de custo (flops) |
|---|---|---|
| Montagem de Ψ de treino | `build_psi_matrix` | N·F multiplicações + N·F_nf `pow` |
| QR de Householder | `qr_solve` | ≈ 2·N·K² |
| **ERR guloso completo** (`chrom.err`) | `compute_err_from_psi` → `compute_err_grouped` com grupo único (`:321`) | ≈ 4·N·K²: em cada passo recalcula ww e wy de **todas** as colunas ativas (4N por coluna) e ortogonaliza as restantes (4N por coluna) |
| **ERR guloso por grupo** (razão de entrada) | `input_contribution_from_psi` (`:322`) | ≈ 4·N·K² (mesma rotina, grupos AR e entrada) |
| Ψ de validação e predição | `build_psi_matrix` na validação | N_val·F |
| Simulação livre | `simulate` | N_sim·F + N_sim·F_nf `pow`; N_sim = 50 em `one_step`, segmento inteiro em `simulation` |

- **Estimativa:** a parte densa soma ≈ 10·N·K² flops, dos quais **≈ 80 % são
  ERR**.
- **Ordem de grandeza:** no WH com K = 33, 10 × 16 000 × 33² ≈ 1,7×10⁸ flops
  por avaliação. O tempo observado de ~170 ms implica ~1 Gflop/s efetivo,
  baixo para um núcleo moderno.
- **Isso sugere ineficiência de memória**, coerente com o acesso do QR
  (§3.3). [inferência]

### 3.3 Três fatos de código que nenhum dos documentos usou

1. **O ERR completo não entra no fitness.** [código]
   - O fitness usa só a **razão de entrada**, que vem do ERR por grupo
     (`assemble_fitness`, `individual_evaluator.cpp:117–121`).
   - `chrom.err` é consumido apenas:
     - pelo podador (`automatic_pruner.cpp:36`), no fim da execução;
     - pelo relatório do melhor da geração (`de_optimizer.cpp:676`);
     - pela exportação JSON (`identification_pipeline.cpp:1235, 1359, 1536`).
   - `compute_input_contribution_ratio`, que leria `chrom.err`, é o método
     morto já registrado no HANDOFF §5.
   - **Calcular `chrom.err` só para o melhor e o campeão elimina ≈ 4·N·K²
     por avaliação sem mudar nenhum fitness.** Por consequência, também não
     muda nenhuma decisão da busca.
2. **O QR percorre a matriz por colunas numa matriz guardada por linhas.**
   [código]
   - Em `qr_solve`, para cada coluna k o produto interno e a atualização
     andam em i com passo n (`R[(row+i)*n + k]`).
   - Com N = 16 000 e n ≈ 34, a matriz tem ~4,4 MB, maior que o cache L2,
     e cada coluna toca uma linha de cache por elemento.
   - **Reordenação equivalente:** uma varredura por linhas que acumula, ao
     mesmo tempo, os produtos internos de todas as colunas k ≥ j.
   - Para cada k, a ordem das somas em i continua a mesma, portanto **o
     resultado é idêntico bit a bit**.
   - Ganho esperado: grande, mas só a medição diz quanto. [inferência]
3. **Os fatores formam um dicionário pequeno e finito na grade de 0,5.**
   - Uma coluna de fator g_p(x_v(k − d)) é a mesma série g_p(x_v)
     deslocada. Na grade atual há 2 variáveis × 6 expoentes = 12 séries
     por segmento de dados.
   - Guardar essas 12 séries completas (treino ≈ 12 × 16 000 × 8 B ≈
     1,5 MB) **elimina todo `pow` da montagem de Ψ**.
   - **Atenção:** o cache é por série, não por (série, atraso); o atraso é
     só um deslocamento de índice. O 09 (§4.1) estimou memória por coluna
     de regressor, o que superestima o problema para fatores.
   - **Resultado idêntico bit a bit**, desde que o produto mantenha a ordem
     dos fatores (1,0 · v₁ · v₂ …, como em `build_psi_matrix`).
   - Com expoentes contínuos (`exponentStep` = 0) o dicionário deixa de ser
     finito, e o cache vira LRU com hit rate a medir.

---

## 4. O que aproveitar do 09

1. **§3.3, regra de validade.** Adotar como está. Ela deve constar também no
   08: a realização transposta acelera a **simulação de um modelo dado**,
   não a avaliação incremental de mutações.
2. **§4.1, chave e orçamento do cache.** Adotar a chave completa (dados,
   divisão, normalização, modo de potência, receita, linhas, revisão do
   algoritmo), a comparação estrutural em colisões de hash e a regra de não
   compartilhar expoentes contínuos quase iguais. **Ajustar:** cachear
   **séries de fator** completas, por linha absoluta, e fatiar por atraso
   (§3.3, item 3). Isso torna o cache imune a mudanças de `md`.
3. **§4.2, janela de linhas.** Correto. Manter a semântica histórica como
   padrão e tratar a janela comum (atraso 40) como **mudança de estimador**
   com braço controle, como o 09 propõe.
4. **§5, ΔSSE, posto e ordem do QR.** Correto e útil para o operador
   dirigido (P4). O alerta de que a ordem das colunas muda o posto efetivo
   é essencial para qualquer comparação.
5. **§5, último parágrafo.** "Otimizar só o QR não equivale a otimizar o
   avaliador." Os dados confirmam com força: o ERR é a maior parte.
6. **§6.3, expoentes.** Adotar os ramos discretos para inteiros pares e o
   refinamento só dentro de ramos não inteiros. Acrescentar a evidência
   existente: a condição `signed_continuous` foi **pior** no CT (0,884 contra
   0,661 V, p = 0,025). O teste do CT já tinha sido visto, então é evidência
   de desenvolvimento, mas é razão para não priorizar expoentes contínuos.
7. **§8, métricas e controles.** Adotar integralmente:
   - fronteira qualidade × **tempo total**;
   - tempo frio × quente;
   - ablações separadas;
   - custos de compilação e de cache contados.
8. **§9, fronteiras.** Adotar. Em especial: ponto fixo fora do primeiro gate
   de velocidade, e o cache de fitness por hash insuficiente quando houver
   coeficientes refinados.

---

## 5. O que mudar no 09

### 5.1 Faltou medir antes de desenhar

O 09 reconhece que os tempos do E3 não isolam as etapas, mas desenha uma
arquitetura de quatro componentes (anéis, cache, QR incremental,
sensibilidade adjunta) sem um passo zero de medição.

**[recomendação]** Antes de qualquer protótipo:
- (a) a análise de escala da §3.1, já feita aqui;
- (b) um *profiling* com tempos por etapa (Ψ, QR, ERR, ERR por grupo, Ψ de
  validação, simulação, diagnóstico, operadores do DE).

O (b) pode ser feito sem tocar no motor congelado: uma ferramenta separada
que liga as fontes do núcleo e cronometra cada função sobre as estruturas
reais dos campeões do E3 (lidas de `report.model`), nos segmentos de treino
e validação.

### 5.2 Os anéis transpostos não são alavanca de velocidade

Pela §3, a simulação é pequena diante de O(N·K²). Mesmo onde ela pesa, a
comparação justa não é anéis contra o `simulate` atual. É anéis contra uma
**forma direta com reaproveitamento de características**: calcular
g_{v,p}(x(t)) uma vez por amostra, ler os atrasos de um histórico e não
copiar o buffer. Essa forma obtém as mesmas economias de `pow` sem
transposição. A transposição só se paga em **ponto fixo**, pela análise de
acumuladores (08 §7).

**[recomendação]** Retirar os anéis do trilho de velocidade e mantê-los no
trilho de implantação.

### 5.3 Estados por regressor: de mecanismo de velocidade a recurso de interpretação

Pela própria §3.3 do 09, os registros por regressor não aceleram a
avaliação de mutações. Mas a série de contribuições e_j(t) = θ_j·z_j(t) na
trajetória exata **mostra quanto cada termo da equação contribui para a
saída ao longo do tempo**. É um recurso valioso de interpretabilidade para
o app e para o artigo, e barato, porque é calculado durante a simulação.

**[recomendação]** Reclassificar como diagnóstico.

### 5.4 Dizer explicitamente que o QR incremental não serve ao DE atual

[código] O cruzamento binomial (`de_optimizer.cpp:292–310`) toma cada
regressor do mutante com probabilidade CR, que adapta em torno de 0,9. O
mutante, por sua vez, mistura atrasos e expoentes de três indivíduos
(`:259–264`). O filho difere do alvo em quase todas as colunas. **Não
existe fatoração do pai que valha a pena atualizar.**

O QR incremental e a ΔSSE só servem a um operador **novo** de vizinhança
dirigida (inserir, remover ou trocar uma coluna). Esse operador é uma
mudança do algoritmo de busca, e o ganho dele deve ser medido como
**convergência**, não como velocidade por avaliação. O 09 até separa os
dois efeitos (§8), mas apresenta o pacote como "ganho de velocidade na
arquitetura atual". **Corrigir a tese da §1.**

### 5.5 Adiar a sensibilidade adjunta (§6.1–6.2)

- Custo de implementação alto: derivação reversa por características,
  produtos, atrasos e divisão, mais *checkpointing*.
- O próprio 09 mostra que o ranking com θ congelado não prevê o efeito
  depois do reajuste por QR.
- O E2 da Fase 0 mostrou que o ajuste por erro de simulação, sem
  regularização, **não melhorou** de forma consistente e gerou
  divergências.

**[recomendação]** Só considerar depois que um operador dirigido simples,
com triagem por ΔSSE barata, tiver mostrado ganho de convergência.

### 5.6 Acrescentar as alavancas que faltam

Ver a §6: ERR sob demanda, QR com acesso contíguo, cache de séries de
fator, ERR por grupo com *downdating* e redução de orçamento pelas curvas
de convergência.

### 5.7 Alinhamento de objetivo com o usuário

O 08 tinha como motivação o ponto fixo de 16/32 bits com expoentes reais,
pedido explícito do usuário nesta conversa. O 09 declara que o objetivo
principal passou a ser velocidade da identificação, "após a precisão do
usuário". Esta auditoria **não tem como verificar** essa precisão.
**[recomendação]** Que o usuário confirme se são dois trilhos (velocidade e
implantação) ou um só.

---

## 6. Ordem recomendada

| Prioridade | Trabalho | Efeito nos resultados | Como provar | Ganho esperado [inferência] |
|---|---|---|---|---|
| **P0** | *Profiling* por etapa sobre estruturas reais do E3 (ferramenta separada); curvas de convergência do E3 (histórico de validação já gravado) para ver quando o campeão se estabiliza | Nenhum | — | Decide o resto |
| **P1** (exato) | (a) `chrom.err` só para melhor, campeão e podador; (b) QR com varredura por linhas, mesma ordem de somas; (c) cache de séries de fator para Ψ de treino e de validação; (d) eliminar cópias redundantes (`psi_aug`, buffer de `simulate`) | **Nenhum**: fitness e trajetória idênticos bit a bit | Reproduzir execuções existentes e comparar `report.model`, `evaluations` e validação, como na reprodução entre máquinas de 21/11 | Moderado a grande. Pela contagem de flops, (a) remove ~40 % da parte densa; (b) depende do gargalo de memória; (c) remove os `pow`. Hipótese grosseira: 1,5–3× nos modelos grandes |
| **P2** (quase exato) | ERR por grupo com *downdating* das normas (ww ← ww − (qᵀw)²/qᵀq; wy idem), recalculando exatamente quando a razão de cancelamento for alta; ou Gram centrado K×K para o ERR, mantendo Householder para θ | Arredondamento muda: fitness difere no último dígito, e a busca, caótica, diverge depois de algumas gerações | Equivalência por avaliação (mesmo modelo, diferença ≤ tolerância) e **estatística** (qualidade das sementes pareadas) | ERR de ~4·N·K² para ~2·N·K² (*downdating*) ou ~N·K² + O(K³) (Gram) |
| **P3** (estimador) | Subamostragem do treino na triagem; janela comum de atraso 40 | Muda o estimador | Braço controle próprio, pré-registrado | A medir |
| **P4** (algoritmo) | Operador de vizinhança dirigida com QR incremental e ΔSSE (09 §5, §7) | Muda a busca | Qualidade × tempo total sob orçamento igual (09 §8) | Desconhecido |
| **P5** (algoritmo) | Sensibilidade adjunta para triagem e refino de expoentes (09 §6) | Muda a busca | Idem, com controle de LM/QR (09 §6.3) | Desconhecido; custo alto |
| Trilho separado | Realização transposta em ponto fixo para implantação (08) | Não afeta a busca | R0–R2 do 08 | Não é objetivo de velocidade |

**Notas:**
- **P1 é o ponto de melhor relação risco/benefício:** por ser idêntico bit a
  bit, nem sequer altera as conclusões do estudo 1.1.0 nem da Fase 0.
- Mesmo assim, o motor do estudo continua congelado. P1 entraria como nova
  versão do núcleo, com a prova de reprodução registrada.
- **Redução de orçamento:** se as curvas de convergência do P0 mostrarem que
  os campeões das células `mr39_zero` se estabilizam com uma fração das
  1,5×10⁵ avaliações, essa é a alavanca mais barata de todas. Mas é **mudança
  de protocolo**, decidida antes de olhar qualquer teste, com braço próprio.

---

## 7. Respostas ao pedido do 09 (§10)

1. **Matemática:** a regra de validade e a equivalência do anel global
   estão corretas, inclusive para termos cruzados, com o aquecimento do 08
   §4.1. Edição exata mais barata: quando a mutação toca só termos
   disparados por u **e** o modelo não realimenta y (sem termos em y), a
   trajetória é FIR e a edição é exata. Isso é irrelevante na prática,
   porque todos os campeões têm y(k−1).
2. **Custo:** ver a §3. Os anéis individuais não preservam ganho que
   importe; a simulação não é o gargalo nos modelos grandes.
3. **QR:** a fórmula está correta; a falta de pivoteamento e o limiar global
   estão confirmados. Para *update*/*downdate* defensáveis: inserção por
   reortogonalização (Gram–Schmidt clássico com reortogonalização, ou
   Householder aplicado à nova coluna); remoção por rotações de Givens no R
   (*downdate* de QR) ou refatoração quando a estimativa de condição
   piorar. A literatura clássica de mínimos quadrados (Björck, *Numerical
   Methods for Least Squares Problems*) cobre esses métodos; **conferir
   edição e seções**.
4. **Objetivo racional:** concordo com o risco. Proteção sem teste: exigir
   que a ΔSSE pseudo-linear e a simulação livre de **validação** concordem
   antes da aceitação, e vetar |den| mínimo abaixo de um limiar na
   trajetória de validação.
5. **Sensibilidade:** adiar (§5.5).
6. **Expoentes:** confirmado; a descontinuidade é só nos pares (§2).
7. **Experimental:** os controles da §8 do 09 bastam. Acrescentar:
   - P1 provado por reprodução bit a bit;
   - P2 em dois níveis (por avaliação e estatístico);
   - cache sempre reportado frio e quente.
8. **Novidade:** a seleção ortogonal incremental de termos por ERR é o
   método clássico FROLS/OLS, que o próprio AEGIS já calcula na forma
   gulosa. Buscas evolutivas com refinamento local (meméticas) para NARX
   também têm literatura. **Não há contribuição publicável evidente** em
   P1–P4 como engenharia; uma contribuição só apareceria pelo **resultado**
   (qualidade × tempo) e, no trilho de implantação, pela garantia de
   ausência de estouro em ponto fixo com expoentes reais. A busca
   bibliográfica fica pendente.
9. **Recomendação:**
   - **reduzir** a investida do 09 a P0 + P1, que dão ganho sem risco
     científico;
   - **adiar** P4 e P5 até haver dados;
   - **retirar** os anéis do objetivo de velocidade.

---

## 8. Correções que esta auditoria impõe ao 08

1. O 08 §5 já suspeitava que QR e Ψ dominavam; a §3 desta auditoria
   reforça. **O critério R4 do 08 (≥ 2× na simulação) não justifica nada
   para a busca**: mesmo um ganho de 10× na simulação muda pouco o tempo
   total nos modelos grandes.
2. O R4 do 08 deve comparar **três** braços:
   - o `simulate` atual;
   - a forma direta com reaproveitamento de características;
   - a realização transposta.

   Assim se separa o ganho da transposição do ganho do reaproveitamento.
3. A motivação do 08 fica restrita a **ponto fixo e implantação**, mais a
   decomposição e_j(t) por termo como diagnóstico (§5.3).

---

## 9. Decisões do usuário

- ~~Confirmar os objetivos~~: **resolvido na §10** (só velocidade e
  arquitetura; sem implantação).
- Autorizar P0 e P1. Exigem compilador C++ nesta máquina (MSYS2 UCRT64), que
  não está instalado. Uma nova versão do núcleo é decisão sua, mesmo sendo
  idêntica bit a bit.
- Qualquer redução de orçamento ou mudança de estimador (P3) é mudança de
  protocolo, com pré-registro próprio.

---

## 10. Atualização após a precisão do usuário (2026-11-23)

**O usuário declarou:** não há interesse em embarcar o código. O objetivo é
**ganho de velocidade e de arquitetura**, mantendo a identidade do AEGIS
(**expoentes reais**), com um algoritmo **por estados**, em uma ou mais
etapas, que pode ou não usar ponto fixo, no espírito do que a TDF-II faz
pelos filtros IIR.

### 10.1 Consequências para esta auditoria

1. **§5.7 resolvida:** há um só trilho, velocidade e arquitetura. O ponto
   fixo só entra se trouxer velocidade.
2. **O "trilho de implantação" do 08 deixa de ser objetivo.** A §8 desta
   auditoria e o 08 §7–§8 ficam como referência técnica, sem prioridade.
3. **A conclusão da §3 se mantém:** nos modelos grandes, o custo está no
   ajuste e no ERR (O(N·K²)), não na simulação. Portanto, **para dar
   velocidade, a ideia da TDF-II precisa ser aplicada ao ajuste**, não só à
   simulação. A §10.2 propõe como.
4. **P1 (exato) continua a primeira etapa,** porque dá ganho sem risco.

### 10.2 A "TDF-II do ajuste": estatísticas deslocáveis como estado

**[recomendação]** Proposta desta auditoria, a ser revisada.

**O que a TDF-II faz de essencial:** reorganiza a conta para que cada
produto seja calculado **uma vez** e os atrasos virem **posições de
memória**, não recomputação. O equivalente no ajuste NARX é este.

**Observação-chave: invariância a deslocamento.**
- Toda coluna de Ψ é uma série-forma z deslocada: φ_j(k) = z_j(k − m_j)
  (08 §3.2, 09 §3).
- A **forma** z_j (fatores, expoentes, atrasos relativos r_f) não depende
  de m_j.
- Logo, cada entrada da matriz de Gram do candidato é uma
  **correlação cruzada deslocada** entre duas formas:

```
G_ab = Σ_{k=k0}^{k1} z_a(k − m_a) · z_b(k − m_b) = C_{ab}(m_a − m_b) + correções de borda
(Ψᵀy)_a = Σ_k z_a(k − m_a) · y(k) = C_{a,y}(m_a) + correções de borda
```

- C é a correlação na janela de referência; as correções de borda somam no
  máximo `maxDelay` termos em cada ponta, porque a janela de cada candidato
  começa em md (§4.2 do 09). Isso torna a conta **exata** a menos da ordem
  de arredondamento.

**O "estado" do problema** passa a ser uma tabela de correlações
deslocáveis entre formas:
- **formas de um fator** (o caso mais comum nos campeões): 2 variáveis × 6
  expoentes = 12 séries na grade de 0,5. Todas as correlações com
  deslocamentos de −40 a +40 somam ≈ 12 × 12 × 81 ≈ 11 700 números,
  calculados **uma única vez** por execução (≈ 2×10⁸ multiplicações no
  treino do WH, uma vez só);
- **formas com produtos** (termos cruzados, denominador −y·φ): entram num
  cache preguiçoso, uma entrada (forma a, forma b, deslocamento) por vez,
  calculada uma vez em O(N) e reaproveitada. O DE recombina regressores de
  um mesmo *pool*, então a taxa de acerto tende a ser alta. **[hipótese] a
  medir.**
- **expoentes contínuos:** o dicionário de formas deixa de ser finito, e o
  cache vira LRU. **O expoente real continua suportado**: o estado depende
  da forma, não de o expoente ser inteiro.

**Custo por candidato, ajuste e ERR:**

| | Hoje | Proposto |
|---|---|---|
| Montar G e Ψᵀy | ≈ 10·N·K² (QR + 2 ERR, §3.2) | ≈ K² consultas + K²·2·maxDelay correções de borda |
| Resolver θ | dentro do QR | Cholesky K×K, O(K³/3) |
| ERR por grupo (fitness) | ≈ 4·N·K² | seleção gulosa no espaço K×K (Gram centrado), O(K³) |
| Resíduos e SSE de treino (BIC, correlação resíduo–entrada) | O(N·K) | O(N·K), ou SSE = yᵀy − θᵀΨᵀy com risco de cancelamento |

**Ordem de grandeza** no WH com K = 33 e N = 16 000:
- hoje ≈ 1,7×10⁸ flops;
- proposto ≈ 33² × 80 + 33³ + 16 000 × 33 ≈ 0,6×10⁶ flops.
- **Isso transforma a avaliação de O(N·K²) em O(N·K).** [inferência]

O ganho real depende do cache, da memória e do que passar a dominar, e só
a medição confirma.

**Segunda etapa: aí a simulação passa a importar.** Removido o O(N·K²), o
que sobra é linear em K: resíduos de treino, predição de validação e
simulação livre. No modo `simulation` a simulação do segmento de validação
passa a ser parte relevante do custo. É nesse momento que a realização em
estados do 08/09 entra como **etapa 2**:
- características calculadas uma vez por amostra;
- uma raiz para toda a grade de 0,5;
- sem cópia de buffer;
- com o controle "forma direta com reaproveitamento" do §8 item 2.

**Ponto fixo:** opcional e de valor limitado aqui. A tabela de correlações
é calculada uma vez, então acelerar essa soma não muda o tempo total. Uma
variante com características int16 e acumulação **int64 exata** daria
correlações sem erro de arredondamento e independentes da ordem
(reprodutíveis bit a bit, paralelizáveis), ao custo de quantizar as
características em 2⁻¹⁵. Fica como opção a comparar, não como base.

### 10.3 Riscos e cuidados

1. **Equações normais:** resolver por Cholesky do Gram eleva ao quadrado o
   número de condição. Mitigações, a avaliar:
   - colunas centradas e escalonadas;
   - estimativa de condição barata (pela diagonal de Cholesky);
   - quando ela passar de um limiar fixado antes, refazer **aquele**
     candidato com o Householder atual;
   - refinamento iterativo com resíduo em O(N·K) (equações semi-normais
     corrigidas; Björck, *Numerical Methods for Least Squares Problems*,
     conferir seção).
2. **Não é idêntico bit a bit:** os resultados mudam no último dígito e a
   busca diverge por caos. A validação é estatística, nível P2 da §6, com
   sementes pareadas e qualidade × tempo total.
3. **Posto e ordem:** o QR atual descarta colunas dependentes **na ordem**
   com um limiar global (§2). O Cholesky na mesma ordem, com limiar
   equivalente no pivô, imita isso, mas não identicamente. Contar os casos
   em que o posto efetivo difere.
4. **Memória do cache de produtos:** S formas geram até S²/2 × 81 entradas.
   É preciso orçamento e LRU, e medir o acerto.
5. **Os dados mudam por ilha?** As **dobras de validação** variam por ilha
   (regimes), mas o ajuste usa sempre o treino completo. O estado de
   correlações é um só por execução. Conferir no código antes de
   implementar.
6. **Modo `legacy`:** fora do escopo (base com +1e−6).

### 10.4 Ordem atualizada

| Etapa | Conteúdo | Validação |
|---|---|---|
| **P0** | *Profiling* por etapa e curvas de convergência do E3 | — |
| **P1** | Exatos: ERR completo sob demanda, QR por linhas, cache de séries de fator, sem cópias | Reprodução bit a bit de execuções existentes |
| **P2'** | **Ajuste por estatísticas deslocáveis** (§10.2), com *fallback* para Householder por condição | Por candidato: θ, posto, SSE, ERR e fitness contra o núcleo, com tolerância; estatística: qualidade × tempo total com sementes pareadas |
| **P3'** | Realização em estados para a simulação livre (08/09) contra a forma direta com reaproveitamento | Equivalência R0/R1 do 08; tempo |
| P4, P5 | Operador dirigido e sensibilidades (09) | Como na §6 |

**Resumo para o usuário:** a ideia da TDF-II se mantém, aplicada onde está
o custo. Os atrasos viram índices numa tabela de correlações calculada uma
vez, e o expoente real continua no centro da representação.

---

## 11. Resposta à revisão externa da §10 (2026-11-23)

Um revisor leu a §10 e recomendou: (1) P0 com *profiling* por etapa em
candidatos pequenos e grandes, registrando a distribuição de K,
racionalidade, fatores e expoentes; (2) P1 com cada otimização exata
avaliada **separadamente**; (3) P2′ como **pesquisa**, derivando as
estatísticas corretas para os pares NN, ND e DD e estimando cache frio,
cache quente e *fallback* antes de prometer O(N·K); (4) a simulação só
depois, se o *profiling* indicar; (5) operadores locais e sensibilidades
por último, medidos por qualidade × tempo total. Conclusão do revisor: a
ideia é promissora, mas a §10.2 **ainda não é um algoritmo correto** para
o AEGIS racional.

**Veredito desta auditoria: a revisão procede nos dois pontos decisivos.**
A ordem dela substitui a §10.4.

### 11.1 O erro da §10.2: colunas do denominador não são deslocáveis

[código] `fit_from_psi` (`rational_model.cpp:18–28`) pseudo-lineariza as
colunas do denominador como −y(k)·ψ_j(k), com **y no atraso 0**. A §10.2
tratou essas colunas como "formas com produtos" no mesmo cache das demais.
Está errado. O fator y(k) fica preso ao instante k e não se desloca junto
com o atraso m_j, então a forma de −y·φ_j **muda com m_j**. As entradas do
Gram ficam assim (z = forma, m = atraso de disparo):

| Par | Entrada | Índices | Deslocável? |
|---|---|---|---|
| N·N | Σ z_a(k−m_a)·z_b(k−m_b) | 1 (m_a − m_b) | sim: C_ab(Δ) |
| N·y | Σ z_a(k−m_a)·y(k) | 1 (m_a) | sim |
| N·D | −Σ y(k)·z_a(k−m_a)·z_b(k−m_b) | **2 (m_a, m_b)** | **não**: correlação tripla |
| D·D | Σ y(k)²·z_a(k−m_a)·z_b(k−m_b) | **2 (m_a, m_b)** | **não**: tripla, peso y² |
| D·y | −Σ y(k)²·z_b(k−m_b) | 1 (m_b) | sim, peso y² |
| intercepto | Σ z_a, Σ y·z_b, Σ 1 | 1 | sim (somas de prefixo) |

**Consequências:**
- As tabelas de ND e DD têm **dois índices de atraso**. Só para formas de
  um fator: 12 × 12 × L² por peso (y e y²). Com L = 40, ≈ 2,3×10⁵
  entradas por peso, ≈ 4,6×10⁵ no total (≈ 3,7 MB). Cada entrada custa
  O(N), ≈ 7×10⁹ multiplicações por execução no WH, metade por simetria.
  [inferência] Ainda é pequeno diante de horas de execução, mas a
  estimativa de "11 700 números" da §10.2 vale **só para NN**.
- Com formas de produto (termos cruzados), as tabelas de dois índices
  crescem como S² × L² e **precisam** de cache preguiçoso.
- Os modelos de penalidade zero do E3 têm muitos fatores no denominador
  (resumo da sessão). O caso ND/DD é a regra nesses modelos, não a exceção.

### 11.2 Cache frio e o ganho que não depende do cache

A revisão pede o custo com o cache frio. A conta separa duas fontes de
ganho que a §10.2 misturou:

1. **Mover o ERR e a solução para o espaço K×K** (Gram → Cholesky → ERR
   guloso sobre o Gram). Isso independe da invariância a deslocamento.
   Mesmo formando o Gram de forma ingênua, sem cache algum (½·N·K² por
   simetria), o custo cai de ≈ 10·N·K² para ≈ 0,5–1·N·K² + O(K³).
   [inferência] Esse é o **piso garantido com cache frio**: cada falta
   custa O(N), o mesmo que uma entrada do Gram ingênuo.
2. **Cache de estatísticas deslocáveis.** Leva o termo N·K² para ≈ K²·L
   consultas mais as correções de borda, mas **só na fração de acertos**.

Por isso P2′ passa a ter duas sub-etapas, medidas separadamente:
- **P2′a:** equações normais com Gram ingênuo + ERR no espaço K×K +
  *fallback* Householder por condição. Sem cache. Valida a numérica
  (§10.3, itens 1–3) sozinha.
- **P2′b:** tabelas NN/N·y/D·y (um índice) e ND/DD (dois índices) com
  cache preguiçoso e LRU. Antes de implementar, medir no P0 a taxa de
  acerto que o *pool* do DE produziria, registrando os pares (forma a,
  forma b, m_a, m_b) pedidos pelos candidatos.

**A promessa de O(N·K) fica retirada** até P2′b medir a taxa de acerto.
O que se pode dizer agora: O(N·K²) com constante ≈ 10× menor no pior caso
(P2′a), e O(N·K) no limite de acerto total (P2′b). [inferência]

### 11.3 P0 e P1 como a revisão pede

- **P0** registra, por candidato avaliado e não só pelo campeão: K,
  número de termos de denominador, fatores por termo, expoentes
  (inteiros × não inteiros) e tempo por etapa (montagem de Ψ, QR, ERR por
  grupo, ERR completo, validação, simulação). Só os campeões já estão nos
  `report.model` do E3; a distribuição dos candidatos exige um *build*
  instrumentado.
- **P1** mede cada otimização exata isoladamente (ERR completo sob
  demanda, QR por linhas, cache de séries de fator), confirmando fitness e
  relatórios idênticos bit a bit e tempo total.
- **Restrição operacional:** os binários de `cpp/build` e
  `cpp/build_phase0` estão congelados, e esta máquina não tem compilador
  C++. P0 e P1 exigem um diretório de *build* **novo e separado** e a
  instalação de um compilador. As duas coisas dependem de autorização do
  usuário.

### 11.4 Ordem final (substitui a §10.4)

| Etapa | Conteúdo | Critério para avançar |
|---|---|---|
| **P0** | *Profiling* por etapa; distribuição de K, racionalidade, fatores e expoentes dos candidatos; registro dos pares de estatísticas pedidos | Saber qual fração do tempo é ajuste/ERR em candidatos pequenos e grandes |
| **P1** | Exatos, um de cada vez: ERR sob demanda, QR por linhas, cache de fatores | Fitness e relatórios idênticos bit a bit; ganho de tempo total |
| **P2′a** | Gram ingênuo + Cholesky + ERR no espaço K×K, com *fallback* | θ, posto, SSE, ERR e fitness por candidato dentro de tolerância; contagem de *fallbacks* |
| **P2′b** | Estatísticas deslocáveis NN/ND/DD com cache | Taxa de acerto medida; qualidade × tempo total com sementes pareadas |
| **P3′** | Simulação em estados (08/09) contra forma direta com reaproveitamento | Só se o *profiling* pós-P2′ mostrar a simulação como parcela relevante |
| **P4/P5** | Operadores dirigidos e sensibilidades (09) | Qualidade alcançada por tempo total |

**O expoente real não é afetado em nenhuma etapa:** as tabelas são
indexadas por forma, e a forma carrega o expoente qualquer que seja.
