# Parecer sobre a proposta A1 (documentos 03, 04, 05 e 06)

Data: 2026-11-20. Parecer pedido pelo usuário sobre:

- [03_PROPOSTA_INTEGRADA.md](03_PROPOSTA_INTEGRADA.md)
- [04_PLANO_EXPERIMENTAL.md](04_PLANO_EXPERIMENTAL.md)
- [05_IMPLEMENTACAO_PRIORIZADA.md](05_IMPLEMENTACAO_PRIORIZADA.md)
- [06_CAPACIDADE_E_AJUSTE.md](06_CAPACIDADE_E_AJUSTE.md)

Nenhum código foi alterado. Não rodei nada novo. Os testes de WH e SB não
foram lidos: dos JSON de WH extraí só o campo `wallSeconds`, por `grep`.

## 1. Veredito

**O diagnóstico está certo e a direção também. O plano, porém, está
superdimensionado e na ordem errada.** Ele gasta semanas de infraestrutura
(contador W, identidades, esquemas v2) antes dos três experimentos baratos
que dizem se a direção compensa.

Proponho:

- uma **Fase 0** de poucos dias, quase toda feita só por configuração do
  binário atual ou por ferramentas avulsas;
- um A1 enxuto depois dela;
- três correções concretas no desenho: o Jacobiano, o comparador do H8 e o
  conflito entre a semeadura e o limite de regressores.

## 2. Com o que concordo

| Ponto | Por quê |
|---|---|
| **O ajuste não é o uso** (03 §3; 01 §3.A). Os coeficientes vêm de QR de um passo mesmo em `simulation`. O `LocalRefiner` usa predição de um passo e não roda em modelos polinomiais | Confirmado no código: `individual_evaluator.cpp:304`, `local_refiner.cpp:31` e `:65`. É a causa mais provável do abismo entre o erro de um passo no teste (0,069 V) e o de simulação (0,66 V) |
| O horizonte longo precisa **vetar** o campeão, não só aparecer no painel | O fitness simula 50 amostras (`individual_evaluator.cpp:365`). A divergência longa só é diagnosticada, não pesa na escolha |
| Separar `fit(S, treino)` de `score(S, θ, contexto)` | É pré-requisito de qualquer refino por simulação |
| Escolher por erro e tamanho, em vez de somar penalidades | A soma atual mistura cinco penalidades numa escala só. Não dá para saber qual delas segura o tamanho do modelo |
| O estudo de capacidade do 06 | Ponto mais importante do pacote. Separa teto de regressores, penalidade e ajuste; sem isso qualquer ganho fica sem explicação |
| A lista do que **não** incorporar (03 §8): rede neural como saída, NSGA-II como segundo motor, LLM gerando código, contração global | Mantém a ideia central e evita a colcha de retalhos |
| A disciplina de teste: reservas, falhas no denominador, Holm, nada de seleção pelo teste | Correta e coerente com as regras do usuário |
| Escape da migração (`de_optimizer.cpp:597`) e identidade do cache (01 §3.D e §3.F) | Confirmados no código |

## 3. Fatos que os documentos não registram e que mudam prioridades

**F1. A penalidade de complexidade é grande perto do erro.**
- Erro de um passo do campeão do CT na validação: 0,0168 em unidades
  normalizadas. Fonte: histórico de `cascaded_tanks/aegis_full/run_1.json`.
- Cada fator custa γ = 0,01, ou seja **cerca de 60 % desse erro inteiro**. Na
  ilha de parcimônia (×2) custa cerca de 120 %.
- Para entrar, um fator novo precisa cortar 60 % do erro de um passo ou
  reduzir em cerca de 0,013 o erro livre de 50 amostras. Esse erro está entre
  0,13 e 0,23 nos registros. **[Errata §10.1: a faixa está errada. Os valores
  finais são 0,042–0,103. A frase "precisa cortar" só vale com as demais
  parcelas fixas.]**
- O valor 0,013 vem do peso do termo livre na fase 3, LocalRefinement: lá
  θ = 0,5 × 1,5 = 0,75 (`identification_pipeline.cpp:556`). A run passa cerca
  de 85 % das gerações nessa fase.
- O 06 §4 faz a conta só contra o termo BIC. Ela devia ser feita contra a
  escala do erro, onde a pressão por parcimônia fica muito mais clara.
- Ainda é hipótese, mas forte.

**F2. O recozimento de γ ficou praticamente desligado no estudo 1.1.0.**
- O progresso é `geração / maxGenerations` (`identification_pipeline.cpp:639`),
  com `maxGenerations = 100000`. As execuções param por avaliações, em cerca
  de 1 977 gerações.
- Com início 0,01 e fim 0,1, o γ efetivo nunca passa de
  0,01 + 0,09 × 0,0198 ≈ **0,0118**. Como ele só é recalculado nas trocas de
  fase, na prática fica em torno de 0,010.
- Isso precisa entrar no `EXPERIMENT_LOG` e nas limitações do artigo: a
  condição `no_curriculum` não mede o efeito do recozimento.
- O 06 manda "desligar annealing" sem perceber que ele já está inerte.

**F3. A semeadura proposta não cabe no limite de regressores.**
- O ARX do DCE para o CT (`n_y` = 2, `n_u` = 11) tem 13 regressores. O limite
  é `maxRegressors = 8`.
- O 04 §3 usa ARX com ny = nu ∈ {5, 10}, ou seja 10 e 20 regressores. Esses
  modelos servem como estrutura fixa, mas não entram no DE.
- O 03 §5.1 diz que sementes acima do limite "não são admitidas". Portanto as
  sementes mais informativas ficam de fora sem que ninguém perceba. Ver M5.

**F4. Metade do H8 roda hoje, sem código novo.**
- `maxRegressors` aceita até 40 (`identification_pipeline.cpp:329`).
- Todas as penalidades são chaves de configuração: `alpha`,
  `complexityPenalty`, `exponentPenalty`, `denominatorPenalty`,
  `noInputPenalty` e `gammaAnneal*`.
- O braço QR do fatorial pode rodar com o `aegis_batch` atual via `--set`, em
  diretório de resultados próprio, depois que o protocolo terminar.
- Para manter WH e SB cegos, rode sem `--data-test`. **[Errata §10.1: sem
  `--data-test` a divisão vira 80/15/5. Fixe `trainEndRow`, `valEndRow` e
  `testStartRow` explicitamente.]**

**F5. Custo real.**
- Uma execução de WH leva cerca de 500 s com 1 thread e 1,5×10⁵ avaliações
  (`aegis_full`: de 482 a 526 s).
- Conta aproximada do A1 com o A1-C:
  - 19 condições × 10 sementes × 3 benchmarks;
  - mais 24 células × 10 × 3 do fatorial;
  - mais a confirmação;
  - total acima de **1 400 execuções**.
- Nesta máquina, de 16 núcleos, dá cerca de 1 a 2 dias de processamento ao
  custo atual. Com LM, provavelmente bem mais.
- **O gargalo é a engenharia, não a CPU:** cerca de 20 etapas de
  implementação, cada uma com testes.

**F6. O campeão é a armadilha clássica do ajuste de um passo.**
- Equação: `0,995 y(k−1) − 0,0095 y(k−30) + 0,046 u(k−5)`. É linear, quase
  raiz unitária, e tem um único atraso de entrada. **[Errata §10.1: o polo
  dominante é 0,9766, lento mas não quase unitário. "Armadilha" é hipótese,
  não causa demonstrada.]**
- Num sinal lento, prever um passo é trivial com y(k−1). Por isso a seleção
  não distingue estruturas pela dinâmica de entrada.
- O pNARX do DCE usa 11 atrasos de entrada e chega a 0,417 V.

## 4. Melhorias que proponho

### M1. Fase 0: três experimentos discriminantes antes de qualquer infraestrutura

Todos usam só treino e validação, com sementes de desenvolvimento 21–30, em
build e resultados separados, depois que o protocolo atual terminar.

| Exp. | O que fazer | Pergunta que responde | Critério decidido antes |
|---|---|---|---|
| **E1. Capacidade em estruturas fixas** | Ferramenta C++ avulsa, ao lado de `cpp/tools/frols_baseline.cpp`. Modelos: ARX e pNARX univariado (monômios de grau 1 a 3), K ∈ {4, 9, 20, 40}, ajuste QR de um passo, erro de simulação livre na validação. Dois controles: atrasos a partir de 1 e entrada contemporânea u(k). Inclui uma **verificação da ferramenta**: reproduzir o pNARX do DCE no CT (n_y = 2, n_u = 11, grau 3, n_ini = 50), com valor publicado de 0,417 V. Isso confere a implementação, não serve para escolher nada | Só capacidade, sem busca evolutiva, já supera o campeão do AEGIS? | Se K ≈ 40 bater o campeão em ≥10 % na validação em ≥2 de 3 benchmarks, capacidade e representação passam à frente do LM |
| **E2. Ajuste por erro de saída em estrutura fixa** | Na mesma ferramenta: LM de horizonte completo sobre as estruturas do E1 e sobre os 10 campeões do CT 1.1.0, inicializado pelo QR, com Jacobiano exato (M3) | Ajustar para simulação melhora uma estrutura dada? | Se a mediana do erro de validação cair ≥10 % em ≥2 de 3 benchmarks, sem mais divergências, implementar o ajustador no núcleo (P1) |
| **E3. Fatorial só por configuração** | Binário 1.1.0 com `--set`, nas combinações: `maxRegressors` ∈ {8, 39}; penalidades padrão ou zeradas (γ, δ, β, α, recozimento); `errorMode` ∈ {`one_step`, `simulation` com validação inteira}. São 8 células × 10 sementes. WH e SB sem `--data-test` | A pressão por parcimônia e o teto prendem o AEGIS em modelos pequenos? | Se as penalidades zeradas com teto 39 melhorarem a validação em ≥10 %, priorizar o seletor e o arquivo erro–tamanho |

Se **nenhum** dos três passar, não construir o A1 como está: a busca de
estrutura NARX partindo do zero é o limite, e é preciso repensar (ver M5).
**[Errata §10.1: o resultado negativo significa "sem apoio para investir
neste pacote", não "classe refutada". A reprodução de 0,417 V sai do gate do
E1; ver §10.4.]**

Estimativa de esforço, só para orientar: E1 de 1 a 2 dias, E2 de 2 a 3 dias,
E3 com meio dia de preparo e cerca de 1 dia de máquina. O A1 completo leva
semanas.

### M2. Baselines internos no mesmo protocolo e nos mesmos dados

- **Problema:** o gate do 04 compara o B3SL só com o B0C, e pede 10 % de
  melhora. No CT, 10 % abaixo de 0,661 dá cerca de 0,595 V. Isso ainda empata
  com o LTI SS publicado (0,600) e perde para o pNARX (0,417).
- **Proposta:** a ferramenta do E1/E2 já produz ARX, pNARX univariado e OE
  linear (LM sobre ARX) **com os mesmos 20 000 pontos de WH e SB**. Esses
  modelos viram referências obrigatórias no relatório de confirmação.
- **Comparação justa:** a literatura usa o treino inteiro, então os números do
  DCE não comparam direto. Os baselines internos resolvem isso. Os números do
  DCE ficam como contexto.
- **Critério secundário pré-registrado:** o A1 não pode ficar pior que o
  pNARX e o OE linear internos. Não é obrigatório passar nele, mas o
  resultado tem de ser reportado.

### M3. Jacobiano exato por sensibilidades recursivas, no lugar de diferenças finitas

O 03 §3 e o 04 §5 propõem diferenças finitas centrais com h = 1e−6.

- **Alternativa:** derivar a recursão do modelo, que dá
  `∂ŷ(k)/∂θ = ∂f/∂θ + Σᵢ ∂f/∂ŷ(k−i) · ∂ŷ(k−i)/∂θ`. É o gradiente padrão de
  identificação por erro de saída.
- **Custo:** uma simulação aumentada com q sensibilidades, contra 2q + 1
  trajetórias completas.
- **Precisão:** exata, inclusive perto de quase-divergência, onde diferenças
  finitas em trajetórias longas se degradam. **[Errata §10.1: "exata" quer
  dizer sem erro de truncamento. Perto de divergência as sensibilidades também
  explodem. A vantagem de custo precisa ser medida.]**
- **Implementação:** a derivada de um produto de potências é fechada. O
  cuidado é com p < 1 perto de y = 0 na base `hybrid`, onde a derivada
  explode. A regra precisa ser explícita: rejeitar o passo ou suavizar, sem
  esconder.
- **Teste:** comparar com diferenças finitas em casos pequenos.

### M4. LM de horizonte completo primeiro; continuação por blocos só se falhar

- O cronograma H = 50 → 200 → completo, preso às frações 30/60/80 % do
  orçamento, acrescenta parâmetros acoplados ao currículo antes de haver
  evidência de que fazem falta.
- Uma simulação completa custa pouco para os poucos candidatos promovidos:
  1 024 amostras no CT, 16 000 no treino de WH e SB.
- **Proposta:** começar com horizonte completo e adotar os blocos só se o E2
  mostrar falha alta, por exemplo mais de 20 % de divergência ou de casos sem
  melhora sobre o QR.
- Isso tira H7 e B1L do plano inicial.

### M5. Hipótese H9: espinha linear fora do limite do DE, como alternativa à semeadura

- **Ideia:** um bloco ARX com ordens escolhidas no treino e na validação
  (AIC) sempre presente, ajustado junto com os termos não lineares. Esse
  bloco não consome os regressores do DE. O DE busca **só a parte não
  linear**.
- **Por que é coerente, e não colcha de retalhos:**
  - continua sendo uma equação NARX explícita;
  - resolve o F3;
  - libera o DE de redescobrir dinâmica linear (F6);
  - segue a prática de PNLSS e Volterra com realimentação, que partem da
    aproximação linear (02 §10–§11).
- **O que deixa de existir:** a semeadura de 20 % (03 §5.1), que seria
  redundante.
- **Quando adotar:** só se o E1 mostrar que o ARX com mais um núcleo não
  linear pequeno bate o pNARX completo. Caso contrário, descartar.

### M6. Corrigir o recozimento de γ e registrar o defeito

No B0C, calcular o progresso pelo orçamento de avaliações, não por
`maxGenerations`. No estudo 1.1.0, documentar o F2 como limitação, sem
reexecutar nada. **[Revisado em §10.1: tornar o recozimento efetivo
multiplicaria γ por até 10, e pelo F1 isso pode piorar o subajuste. Na base
do A1, usar γ constante.]**

### M7. Reduzir e limpar o fatorial H8

- **Células:** 2 × 2 × 2 = 8, com Kmax ∈ {9, 40}, γ ∈ {0; 0,01} e ajuste
  ∈ {QR, LM}. O Kmax = 20 entra só se o E1 mostrar curva não monotônica.
- **α = 0 em todas as células.** O comparador do 06 §6.2 soma
  `α·ln(MSE_treino, um passo)` nos dois braços. Por construção, o LM piora o
  MSE de um passo, então esse termo penaliza o braço LM. É uma confusão de
  efeitos, não um controle.

### M8. Validar o contador W contra o tempo, em vez de discutir pesos

- A fórmula `factorRows + termRows + n·q² + q³` soma grandezas de naturezas
  diferentes com pesos arbitrários.
- **Proposta:** antes de usar o W como orçamento, medir sua correlação com o
  tempo de parede num conjunto de calibração (por exemplo, todas as células do
  E3). Se a correlação for alta (r ≥ 0,9), adotar. Senão, simplificar para
  amostras simuladas e fatores avaliados.
- Os critérios devem reportar sempre W e tempo.

### M9. O veto de admissibilidade vem antes do LM

- O veto é contratual e barato: o `diagnose` atual já calcula a simulação
  longa. Também é independente do ajustador.
- **Proposta:** colocá-lo como a primeira mudança no núcleo (B0C), à frente
  de P0.2 e P0.3.

### M10. Identidade de modelo só onde existe θ refinado

- Se o LM só roda em candidatos promovidos, guardados no arquivo, o cache da
  população continua válido com QR determinístico.
- O `FittedModelId` é necessário **no arquivo e nos promovidos**. O cache
  inteiro não precisa ser refeito, o que reduz o P0.3.

## 5. O que rejeito ou adio, e por quê

| Item | Decisão | Motivo |
|---|---|---|
| P0 completo (contador W, identidade total, capabilities, B0C formal) antes de qualquer evidência científica | **Adiar** para depois da Fase 0 | Muito esforço antes de saber se a direção compensa. A Fase 0 não depende dele |
| Agentes v2 e as condições TF, TU, TRANDOM, TLEGACY e o P3 no A1 | **Retirar deste ciclo** | Nenhum agente mostrou ganho (CT, sementes 1–20). Reposicionar os agentes só faz sentido quando alguma tarefa tiver efeito medido com o escalonador fixo. Manter a interface v1 e reportar o resultado negativo com honestidade |
| EMPS como um dos três benchmarks **primários** de confirmação | **Rebaixar** a transferência secundária, reportada sempre | É um sistema com integrador, em malha fechada e com atrito. No DCE, nenhum baseline não linear superou o LTI com clareza. O gate passaria a depender de uma dificuldade que as hipóteses não tratam, e o EMPS ainda exige obter dados. Gate primário proposto: WH e SB multisine, as duas com ≥10 %, Holm com 2 comparações |
| Comparador do 06 §6.2 com α·ln(MSE de um passo) | **Rejeitar** | Ver M7 |
| Currículo de horizonte preso a frações fixas do orçamento | **Adiar** | Ver M4 |
| 24 células × 10 × 3 no H8 | **Reduzir** | Ver M7. A Fase 0 já responde à maior parte |
| B0C × B0 como braço com gate próprio | **Só descritivo** | São correções de contrato, não hipóteses científicas |
| Substreams de RNG por tarefa e replay de tarefas de agente | **Adiar** com os agentes | Só são necessários quando houver tarefas e agentes |
| Regra final "menor K com erro até 1 % do mínimo" | **Aceitar, com ressalva** | A validação do CT tem cerca de 205 amostras. Uma tolerância de 1 % fica abaixo do ruído e, na prática, escolhe o menor erro. Registrar isso |

## 6. Decisões que são do usuário

1. **Quando abrir os testes de WH e SB da iteração 2.**
   - O HANDOFF manda rodar o `analyze.dart` quando o protocolo terminar, o
     que abre esses testes.
   - O 04 usa WH e SB como **confirmação** do A1 e exige que continuem
     cegos.
   - Se os testes forem abertos antes de o desenho do A1 ser congelado, o que
     se vê do 1.1.0 pode influenciar o desenho, e WH/SB deixam de ser
     confirmação limpa.
   - Opções:
     - **(a)** congelar as decisões do A1 antes de abrir;
     - **(b)** abrir agora para o artigo do 1.1.0 e confirmar o A1 em outros
       dados (EMPS, Bouc–Wen, sintético);
     - **(c)** adiar o artigo do 1.1.0.
   - Recomendo a (a) quando a Fase 0 terminar. Ela leva poucos dias e não
     usa teste.
2. **Estratégia do artigo.**
   - No mesmo protocolo, o 1.1.0 fica pior que o LTI SS no CT. Um artigo de
     método sobre o 1.1.0 dificilmente passa numa revista.
   - Opções:
     - esperar a Fase 0 e, se ela der certo, o A1;
     - reposicionar o artigo como estudo de diagnóstico: ajuste de um passo ×
       simulação e capacidade × parcimônia em busca evolutiva de NARX, com a
       interface de agentes auditável e o resultado negativo dos agentes.
3. **Aprovar a Fase 0.**
   - Usa build e resultados separados e só começa quando o protocolo atual
     terminar.
   - Não exige recompilar o núcleo congelado: E3 só usa configuração; E1 e
     E2 são ferramentas novas num diretório próprio.

## 7. Ordem recomendada

| Etapa | Conteúdo | Gate de saída |
|---|---|---|
| 0 | Protocolo atual termina; nada é aberto em WH/SB | — |
| 1 | Fase 0: E1, E2, E3 (M1), com os baselines internos (M2) e o Jacobiano exato (M3) | Critérios do M1, registrados antes de rodar |
| 2 | Congelar as decisões do A1 enxuto; então decidir sobre abrir WH/SB da iteração 2 (seção 6.1) | Manifesto com SHA-256 |
| 3 | No núcleo, em build próprio: veto de admissibilidade (M9), recozimento corrigido (M6), separar fit e score, migração sem escape | Fixtures B0 inalteradas; testes |
| 4 | Ajustador LM no núcleo, se o E2 passar; identidade só no arquivo e nos promovidos (M10) | H1 na validação |
| 5 | Seletor erro–tamanho e teto de capacidade escolhidos pelo E1/E3 e pelo H8 reduzido (M7). Espinha linear (M5) só se o E1 apoiar | H3/H8/H9 na validação |
| 6 | Confirmação: WH, SB multisine e baselines internos; EMPS como transferência secundária | Critério do 04 com os ajustes da seção 5 |
| — | Agentes v2 | Fora deste ciclo |

## 8. Limites deste parecer

- Não verifiquei todas as referências arquivo:linha do 01. Conferi
  `individual_evaluator.cpp:21`, `:97`, `:304` e `:365`, `local_refiner.cpp:31`
  e `:65`, `de_optimizer.cpp:597`, os limites da configuração e o recozimento.
- As estimativas de custo e de esforço são aproximadas. A de custo vem do
  tempo medido no WH; a de esforço é julgamento meu.
- F1 e F6 são leituras de um único campeão (semente 1, CT). As outras nove
  sementes têm o mesmo número de coeficientes, mas não li todas as equações.
- Nada aqui é resultado experimental novo. Todo ganho continua hipótese até a
  Fase 0.

---

## 9. Comentário crítico ao parecer — conferência adicional

Comentário acrescentado em 2026-11-20 a pedido do usuário. Preservadas as
seções 1–8 do parecer. Esta seção é uma resposta técnica, **não aprovação
para executar a Fase 0 nem alteração retroativa do plano A1**. Foram lidos
código e somente estrutura, histórico de treino/validação e ações das dez
runs CT da referência. Nenhum resultado de teste WH/SB foi aberto, nenhum
código/binário foi modificado e nenhum experimento novo foi rodado.

### 9.1 Síntese: concordo com a mudança de prioridade

A crítica central é procedente. O desenho A1 misturava um destino arquitetural
com todos os pré-requisitos de uma implementação completa. Para **decidir
se esse destino vale o investimento**, E1/E2 e um E3 exploratório precisam
de menos infraestrutura: manifesto, separação treino/validação, ajuste e
avaliação independentes, custos brutos e preservação do binário congelado.
Capabilities v2, agentes de tarefas e contador global detalhado podem esperar.

Também aceito a correção do comparador H8. Manter o mesmo termo de erro
de um passo nos braços QR/LM define um objetivo comum, mas **não isola**
o efeito de alinhar o ajuste à simulação: QR já minimiza essa parcela,
enquanto LM pode sacrificá-la para melhorar a trajetória. O α=0 proposto
é um controle diagnóstico melhor; a regularização deve ser avaliada em
contraste separado. Esta é uma revisão que recomendo incorporar numa
versão seguinte do plano, antes de qualquer execução.

### 9.2 Conferência de F1, F2 e F6 nas dez sementes

Fontes: `experiments/results/cascaded_tanks/aegis_full/run_*.json`, campos
`report.model`, `report.actions`, `report.generations` e `history`, e
`identification_pipeline.cpp:639` (progresso), `:536` (pesos por fase).

| Evidência conferida | Resultado | Consequência |
|---|---|---|
| Coeficientes por campeão | 4 nas dez seeds, incluindo intercepto; denominador 1 em todas | confirma baixa capacidade realizada, mas não sua causa |
| Não linearidade | nove modelos estritamente lineares; seed 5 tem um fator de expoente 0,5 | “quase lineares” é sustentado em dez runs, não apenas na seed 1 |
| Entrada na fase 3 | gerações 246–324; término em 1976–1977 | cerca de 83,6%–87,6% das gerações na fase 3 |
| γ canônico final reconstruído | 0,0102214–0,0102916; seed 1: 0,010243 | annealing de 0,01 até 0,1 praticamente não foi exercitado |
| Último `rmseVal` normalizado, seed 1 | 0,01680186639 | γ/erro ≈0,610 na fase final |
| Último `freeRun` curto, seed 1 | 0,09428858343 | γ/0,75 ≈0,0136573, ou 14,5% desse erro curto |
| Último `freeRun` curto, dez seeds | 0,04231810242–0,103019656 | a faixa 0,13–0,23 citada em F1 não descreve estes valores finais; pode se referir a outro momento ou campo |

Reconstrução de γ: `0,01 + 0,09 × geração_da_última_transição/100000`;
não usar a geração final como se o peso fosse atualizado continuamente.
Esses números são dos campeões, não demonstram a contribuição isolada do
recozimento. A ablação `no_curriculum` mede a retirada de um pacote de
mudanças (espaço, fases, pesos e reflexos), não o annealing isoladamente.

A comparação de escala em F1 é esclarecedora, mas “precisa cortar 60% do
erro” só vale **mantidas as demais parcelas**. BIC, erro livre, contribuição
de entrada e segurança também podem mudar; termo cúbico ou produto sofre
custos diferentes. Melhor escrever: “o custo marginal γ equivale a cerca de
61% do RMSE de um passo desse campeão; a aceitação depende da soma completa”.
Na ilha de parcimônia, erro e campeão locais podem ser diferentes: duplicar
γ não prova uma razão de 122% para o melhor indivíduo dessa ilha.

F6 identifica uma possibilidade conhecida de previsão em sinais lentos,
mas “causa mais provável” ainda é uma hipótese. O coeficiente de y(k−1)
próximo de 1 também não prova um polo quase unitário: na seed 1 o polinômio
característico é `z^30 − 0,995462 z^29 + 0,00948517`. É preciso analisar
o conjunto dos coeficientes/raízes, não só 0,995. Não proibir y(k−1), que
pode ser necessário ao modelo correto.

### 9.3 Fase 0: apoio, com quatro correções antes de executar

**(a) “Sem `--data-test`” não preserva automaticamente o protocolo 80/20.**
Em `aegis_batch.cpp:189`, os índices de treino/validação são preenchidos
automaticamente somente quando há arquivo de teste separado. Sem ele, a
configuração atual deixa `validationRatio=0,15` (`identification_pipeline.cpp:105`)
e `trainRatio=0,8`: o resultado é 80/15/5, com um trecho interno chamado
teste. Isso não abre o teste oficial, mas muda a validação e prejudica a
comparação. A configuração da Fase 0 deve fixar explicitamente:

| Dados de estimação, sem cabeçalho | `trainEndRow` | `valEndRow` | `testStartRow` |
|---|---|---|---|
| CT: 1024 linhas | 819 | 1024 | 1024 |
| WH/SB: 20000 linhas | 16000 | 20000 | 20000 |

Isso deixa o teste vazio. Validar os índices no relatório efetivo e não
carregar os CSVs oficiais de teste no processo de busca. Fixar também
linha inicial, contexto e escala em todos os comparadores novos.

**(b) Retirar a reprodução de 0,417 V do gate inicial de E1.** Conhecer um
número publicado é diferente de executar, inspecionar e iterar a ferramenta
contra o teste para “conferir” a implementação. Além de expor resultados,
split, escala, intercepto, alinhamento de u(k), implementação e versão
podem impedir coincidência exata. Usar sistemas sintéticos de solução
conhecida, equivalência Legendre–monômios e cálculo independente de métricas
no treino/validação. Reproduzir o teste publicado só após congelamento,
como resultado separado, sem calibrar a ferramenta para atingir o número.
CT já é desenvolvimento, mas essa exceção continuaria sendo uma prática
ruim e não deve se estender a WH/SB.

**(c) E3 é diagnóstico conjunto, não prova isolada sobre γ.** Zerar γ, δ,
β e α simultaneamente testa um pacote de regularização. Se houver ganho,
não o atribuir só à complexidade. Com currículo ativo, zerar
`noInputPenalty` tampouco elimina os pisos de ζ (1,5/0,8/1,0), e a ilha
free-run pode impor θ mínimo. Publicar os pesos **efetivos**, congelar
`gammaAnnealStart=gammaAnnealEnd` no contraste e explicitar se racionalidade,
regimes e reflexos continuam ativos. Uma Fase 0 enxuta pode aceitar esse
pacote como triagem, mas a confirmação causal exige decompor a parcela
que parecer útil. QR/LM não são níveis possíveis de E3 apenas por flags:
`errorMode` troca a pontuação, não o ajuste; o braço LM depende de E2.

**(d) Gate negativo não localiza sozinho o limite.** Se E1/E2/E3 falharem,
há razão para não implementar o A1 completo; não há prova de que “NARX
partindo do zero é o limite”. Podem falhar loss, implementação, suporte,
inicialização, capacidade ou orçamento. Separar “sem apoio para investir
neste pacote” de “esta classe de modelos foi refutada”. O limiar de 10%
deve incluir dispersão, falhas e comparação por estrutura. Estruturas fixas
determinísticas não viram dez observações independentes ao repetir seeds;
dez campeões CT são estruturas selecionadas do desenvolvimento, não dez
sistemas físicos independentes.

### 9.4 Jacobiano por sensibilidades: recomendação boa, garantia forte demais

Aceito M3 como implementação preferível para o domínio diferenciável.
Para `f=N/D`, com ϑ incluindo intercepto e todos os coeficientes:

\[
s_j(k)=\frac{\partial f}{\partial\vartheta_j}
 +\sum_{\ell\in\mathcal L_y}
   \frac{\partial f}{\partial\hat y(k-\ell)}s_j(k-\ell),\quad
\frac{\partial f}{\partial z}=
 \frac{D\,\partial N/\partial z-N\,\partial D/\partial z}{D^2}.
\]

Para coeficiente do numerador a derivada direta é φ/D; para denominador,
−Nφ/D²; para intercepto, 1/D. A sensibilidade da história medida inicial
é zero se ela é fixada; se estados iniciais forem otimizados, isso muda.
Somar contribuições de fatores/atrasos repetidos e incluir a dependência
indireta pelas saídas simuladas. Essas fórmulas são nossa derivação do modelo.

“Exato” significa derivar a recursão sem erro de truncamento de diferenças
finitas, **não** precisão numérica garantida perto de divergência. As
sensibilidades também podem crescer exponencialmente com o horizonte;
isso é tratado por Ribeiro, Tiels, Umenberger, Schön e Aguirre,
*On the smoothness of nonlinear system identification*, Automatica 121,
109158 (2020), DOI
[10.1016/j.automatica.2020.109158](https://doi.org/10.1016/j.automatica.2020.109158),
[original dos autores](https://arxiv.org/abs/1905.00820).

Na base híbrida, p<1 em zero não tem derivada finita; perto de zero pode
ser mal condicionado. Suavizar muda a família e a função simulada; não
suavizar só o Jacobiano mantendo outra função no resíduo sem declarar
aproximação. Primeiro usar casos polinomiais diferenciáveis; rejeitar ou
sinalizar trajetórias não diferenciáveis sob regra fixa para o braço híbrido,
sem excluir essas falhas dos resultados. Não derivar a saída saturada como
se fosse a dinâmica original.

Uma trajetória aumentada com q sensibilidades não custa uma trajetória
escalar: seu trabalho e memória crescem com q e o número de dependências
AR. Pode ser mais eficiente e preciso que 2q+1 simulações, mas a vantagem
precisa ser medida. Diferenças centrais ficam como teste independente em
casos pequenos bem condicionados, com varredura de passo, não como requisito
de concordância perto de singularidades.

### 9.5 Decisões M1–M10: aceites e ressalvas

| Proposta | Meu parecer | Ajuste necessário |
|---|---|---|
| M1: Fase 0 | **Aceitar a prioridade** | corrigir splits, retirar teste publicado do gate e limitar interpretação causal de E3 |
| M2: baselines internos | **Aceitar** | mesmos dados, suporte temporal, escala, warmup e validação; publicar também custos. “Não pior que pNARX” é requisito prático, não equivalência estatística provada por p não significativo |
| M3: sensibilidades | **Aceitar com domínio e testes explícitos** | sem promessa de precisão perto de divergência; singularidades da base tratadas e falhas contadas |
| M4: horizonte completo primeiro | **Aceitar como primeiro ensaio** | registrar falta de melhora separada de divergência; QR já ótimo em uma estrutura não significa falha numérica. Os 20% seriam um gatilho proposto a congelar, não uma lei; custo curto não garante bom condicionamento |
| M5: espinha linear | **Manter como H9 opcional** | acrescentar E1b que realmente compare ARX + correção pequena com pNARX; E1 descrito não contém esse braço. Toda a espinha conta em K/custo e deve ser refinada junto; não escondê-la fora da contagem |
| M6: annealing por orçamento | **Registrar limitação agora; testar correção depois** | progresso por avaliações não calibra coeficientes/custos LM; futuro usar saldo consumido do orçamento escolhido. Alterar só essa regra em braço separado: antecipar γ até 0,1 pode piorar o subajuste; não assumir benefício |
| M7: oito células e α=0 | **Aceitar como núcleo discriminante** | o fatorial QR/LM enxuto é distinto da triagem E3 de penalidades em pacote; não misturá-los. Curva de capacidade intermediária de E1 pode permanecer sem multiplicar DE |
| M8: calibrar W | **Aceitar medição, rejeitar r≥0,9 como validação suficiente** | correlação alta pode esconder viés por método/tamanho. Validar erro relativo/custo por grupo e em casos separados; contagem de sensibilidades/QR deve aparecer, não só amostras |
| M9: veto antes do LM | **Aceitar prioridade contratual** | `diagnose` atual cobre campeão, não todos os candidatos. Veto precisa agir na promoção e na substituição/reeleição; não basta apagar o campeão divergente se nunca houve arquivo de alternativas |
| M10: identidade localizada | **Aceitar** | enquanto LM só existir fora da população QR e seu score não usar cache estrutural. Se voltar por migração/reinserção ou avaliação com refit, preservar θ exige ampliar a fronteira; caso contrário o refinamento se perde |

Sobre F3: o conflito existe para ARX de 10/20 termos e para a referência
de 13 lags, mas não elimina todas as sementes possíveis: ARX 2+2 e FROLS
esparso cabem. Sementes acima do limite já eram explicitamente recusadas no
03. O problema real é alinhar a população informada ao estudo de capacidade,
não uma falha silenciosa demonstrada em execução (a proposta não rodou).

H9 preserva uma equação legível, mas restringe a busca a uma correção da
espinha escolhida. Precisa comparar espinha fixa/conjuntamente reajustada,
controle sem espinha e total de coeficientes igualado. Em racionais, declarar
a forma: `(ARX+Nnl)/(1+Dnl)` também divide a espinha pelo denominador,
enquanto `ARX+Nnl/(1+Dnl)` é outra parametrização. Começar com correção
polinomial evita misturar essa mudança com o teste da espinha linear.

### 9.6 Teste cego, EMPS e escopo de confirmação

A preocupação com a abertura WH/SB é correta. A proposta 04 ainda é um
desenho em revisão, não uma confirmação iniciada; congelá-la só para poder
abrir testes seria prematuro. Recomendo manter os testes oficiais fechados
durante a Fase 0 e registrar depois um manifesto aprovado e datado antes
de qualquer análise dos resultados históricos WH/SB. Resultados históricos
abertos depois do congelamento não autorizam alterar o novo método e ainda
chamá-lo de confirmatório nos mesmos testes. Uma mudança posterior exige
novo plano e nova evidência reservada.

Rebaixar EMPS para transferência secundária é defensável para reduzir o
primeiro ciclo, **se decidido antes dos resultados**, por escopo dinâmico
e disponibilidade, não por expectativa de desempenho ruim. Sua presença
de integrador e coleta em malha fechada são descritas no
[DCE 2026](https://doi.org/10.1017/dce.2026.10067). A frase sobre nenhum
baseline não linear superar LTI “com clareza” não estabelece equivalência
nem impossibilidade; a tabela publicada é descritiva.

O gate WH+SB, ambas com ganho ≥10% e Holm em duas comparações, permite uma
conclusão **restrita a esses dois benchmarks**, não uma alegação de
transferência geral. A retirada do terceiro primário precisa constar como
revisão anterior às execuções, com EMPS secundário sempre reportado se
executado. Escolher outro benchmark só após ver que um falhou seria seleção
oportunista; não recomendo esse caminho.

Aceito adiar agentes v2 como implementação, preservando interface v1 e sua
auditoria. O AEGIS continua concebido para supervisão, mas não precisa
acrescentar um agente novo antes de existir uma tarefa comprovadamente útil.
Resultados sem significância não provam ausência de qualquer benefício
possível; limitam a alegação às políticas, dados e orçamento avaliados.

### 9.7 Ordem enxuta que recomendo submeter à aprovação

1. Encerrar naturalmente o protocolo vivo; manter WH/SB fechados. Não tocar
   no build usado por ele. Registrar versão revisada de Fase 0 e seus gates.
2. E1 em ferramenta separada: testes sintéticos e equivalência numérica,
   curvas de capacidade e baselines internos. Identificar cada estrutura e
   ajuste no próprio arquivo de resultado; isso é indispensável mesmo sem
   refazer o cache global.
3. E2: horizonte completo e sensibilidades nos casos diferenciáveis;
   demais casos com política explícita. Medir erro longo treino/validação,
   falhas, iterações, tempo e trabalho. E3 pode rodar independentemente em
   resultados separados, com splits e pesos efetivos fixados.
4. Decidir, com essa evidência, quais componentes justificam o A1 enxuto.
   Não empilhar correções e LM num só contraste: veto, migração, annealing,
   ajustador e seleção têm efeitos diferentes.
5. Só depois integrar no núcleo em outro build, finalizar o orçamento e a
   identidade onde necessários, congelar configuração e confirmar o pacote
   escolhido. E1b/H9 e agentes não entram automaticamente.

O parecer melhora a priorização e identifica dois problemas reais da minha
proposta: comparador H8 e início excessivo pela infraestrutura. Ele não é,
porém, uma especificação pronta para rodar sem as correções acima. Minha
recomendação é **adotar a Fase 0 enxuta corrigida como próximo desenho a
aprovar**, mantendo a análise original como registro da evolução da proposta.
