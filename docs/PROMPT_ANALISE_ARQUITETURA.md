# Prompt — análise de arquitetura e incorporação de técnicas no AEGIS

Você vai trabalhar no projeto AEGIS em `C:\SourceCode\AEGIS` (repositório
`LASEC-UFU/AEGIS`, já clonado; não clone de novo). Responda ao usuário em
português.

## Objetivo

Analisar a arquitetura atual do AEGIS e o que a literatura publicada nos
benchmarks Cascaded Tanks, Wiener–Hammerstein e Silverbox faz melhor, e
propor um **desenho integrado** que melhore a ferramenta **sem perder a ideia
central do AEGIS**. O resultado deve ser uma evolução coerente do AEGIS, não
uma colagem de técnicas ("colcha de retalhos"). Combinar técnicas é
bem-vindo quando cada uma ocupa um papel definido na arquitetura e o conjunto
continua explicável em uma frase.

Nesta tarefa você **analisa e propõe**. Não implemente mudanças grandes antes de
o usuário aprovar o desenho.

## Leia primeiro (nesta ordem)

1. `docs/HANDOFF.md` — estado do projeto, regras do usuário, processos em
   execução, resultados parciais, armadilhas. É obrigatório.
2. `docs/audit/01_AUDITORIA.md` e `docs/audit/02_CORRECOES.md` — defeitos
   encontrados e o que foi corrigido.
3. `experiments/EXPERIMENT_LOG.md` — iterações, decisões e o que já foi visto
   no conjunto de teste.
4. `docs/architecture/02_LITERATURA.md` — literatura conferida e onde o
   AEGIS fica.
5. `docs/CONFIGURATION.md`, `docs/AGENT_INTERFACE.md`, `docs/BENCHMARKS.md`,
   `docs/EXPERIMENTS.md`, `docs/paper/IFAC_JSC_PREPARACAO.md`.
6. O código: `cpp/src/` (`individual_evaluator.cpp`, `de_optimizer.cpp`,
   `identification_pipeline.cpp`, `rational_model.cpp`, `regressor_library.cpp`),
   `lib/services/` (agentes) e `tool/experiments/`. Confirme no código, não
   apenas nos documentos.

## Regras (obrigatórias)

- Sem commit, push, release ou publicação sem autorização explícita do usuário.
- Sem chamadas pagas a APIs sem informar custo e obter confirmação específica.
  Nunca peça segredos na conversa.
- Não use Python. O projeto é C++ e Dart (bash como cola).
- Não interrompa nem recompile o núcleo enquanto o protocolo experimental
  descrito no HANDOFF estiver rodando. O motor `1.1.0-audit` está congelado
  para esse estudo. Se precisar rodar algo, use outro diretório de build.
- **Disciplina de teste:** os conjuntos de teste do Wiener–Hammerstein e do
  Silverbox não foram examinados e não podem orientar nenhuma decisão de
  desenho. O Cascaded Tanks já foi visto e é benchmark de desenvolvimento.
  Use apenas treino e validação para decidir. Reserve sementes e benchmarks
  novos para confirmar.
- Não fabrique nem arredonde a favor resultados. Valores da literatura só
  entram com a referência verificada (autores, título, veículo, ano, DOI e o
  número exato, com a métrica e o protocolo usados). Se não conseguir
  verificar, marque como "não verificado". O site nonlinearbenchmark.org lista
  resultados em planilhas Google que podem não ser acessíveis
  automaticamente; procure as publicações originais.

## O que é a ideia central do AEGIS (preservar)

Descreva-a com suas palavras depois de ler o código; o ponto de partida é:

- busca evolutiva da **estrutura** de modelos NARX polinomiais e racionais,
  com expoentes reais e atrasos explícitos, produzindo modelos **interpretáveis**
  (equação legível);
- evolução diferencial multi-ilha com JADE, **papéis de ilha** (perfis de
  objetivo) e **regimes** (dobras da validação), com migração filtrada por
  reavaliação no destino;
- **currículo** de identificação em fases;
- **supervisão por agentes** através de uma interface de ações tipada,
  limitada, registrada e reprodutível (modo lockstep), com agentes locais
  (UCB1, fuzzy) e LLM.

Uma proposta que troque o AEGIS por outro método (por exemplo, uma rede neural
caixa-preta no lugar da busca de estrutura) está fora do escopo. Técnicas de
outros métodos podem entrar como **componentes** que servem a essa ideia.

## Evidência já disponível (usar como ponto de partida, não como conclusão)

- Cascaded Tanks, 10 sementes:
  - AEGIS corrigido: 0,661 V (mediana do RMSE de simulação no teste; mínimo
    0,656, com 4 parâmetros);
  - código original: 0,678 V;
  - FROLS: 0,752 V.
  - Não houve diferença significativa entre o AEGIS corrigido e o original.
- Literatura conferida: `docs/architecture/02_LITERATURA.md`.
  - **Mesmo protocolo (DCE 2026):** LTI SS 0,600 V, ARX 0,682, pNARX
    univariado de um passo 0,417, LSTM 0,452. O AEGIS fica pior que o LTI SS.
  - **Melhores publicados:** 0,19–0,34 V, com física ou treino por erro de
    simulação.
  - **Mais parecido com o AEGIS:** TAG-GP evolutivo de Khandelwal, 23,5 mV no
    WH contra 0,24 mV do melhor resultado.
- Os campeões convergem para estruturas quase lineares dominadas por y(k−1).
  O objetivo `one_step` favorece a precisão de um passo; o termo de simulação
  usa só 50 amostras e não detecta divergências longas. O modo `simulation`
  (validação inteira) não resolveu na checagem feita.
- Ilha única ou sem papéis/regimes: 6/10 campeões divergem na simulação longa.
  A base de potência `signed` contínua foi pior que a `hybrid` quantizada.
- Agentes (UCB1, fuzzy): sem ganho; a maioria das ações não mudou o campeão em
  25 gerações; o UCB1 tendeu a piorar. Dados insuficientes para política neural.
- Coeficientes de modelos racionais são estimados por pseudo-linearização
  (erro de equação), estimador enviesado sob ruído na saída.
- Resultados de WH e Silverbox: ver `experiments/results/*/analysis/SUMMARY.md`
  quando o protocolo terminar.

## Famílias de técnicas a avaliar (avalie; não adote por obrigação)

Para cada uma, diga se resolve um problema **observado** no AEGIS e onde ela se
encaixaria. Exemplos de direções, não uma lista de tarefas:

- estimação dos coeficientes por erro de simulação (output error), simulação
  truncada ou *multiple shooting*, refinamento por Levenberg–Marquardt após a
  seleção de estrutura;
- busca memética: DE para a estrutura global combinada com seleção ortogonal
  (ERR/FROLS) ou eliminação regressiva como busca local;
- objetivo multiobjetivo (frente de Pareto entre erro de simulação,
  complexidade e estabilidade) no lugar da soma ponderada de penalidades;
- semeadura da população a partir de análise de correlação, modelos lineares
  (BLA) ou FROLS;
- critérios de estabilidade e de seleção que detectem divergência no horizonte
  longo;
- o papel dos agentes: que decisões da busca (orçamento, reinício, troca de
  objetivo por fase) teriam efeito mensurável, e se a supervisão deve agir em
  outro nível que não o de parâmetros finos do DE.

## Entregáveis

Crie `docs/architecture/` com:

1. `01_ARQUITETURA_ATUAL.md` — diagrama e descrição do fluxo real (dados →
   busca → avaliação → seleção → agentes → relatórios), com os pontos fracos
   identificados e a evidência de cada um (arquivo:linha ou resultado).
2. `02_LITERATURA.md` — **já existe** (conferido em 2026-11-20). Leia antes
   de propor qualquer coisa e **estenda** o arquivo, sem refazê-lo:
   - tente verificar os valores marcados [S];
   - acrescente a descrição técnica dos métodos que você usar como argumento;
   - respeite as regras de comparabilidade da §2 (`n_ini`, melhor de N ×
     média, uso de física, tamanho do treino, os três testes do Silverbox).
3. `03_PROPOSTA_INTEGRADA.md` — o desenho proposto:
   - a ideia central do AEGIS em uma frase, e a mesma frase após a proposta;
   - cada técnica incorporada com: o problema observado que resolve, o papel
     exato que ocupa na arquitetura (que componente substitui ou estende), o
     que deixa de existir, custo computacional, risco e alternativas
     descartadas com o motivo;
   - um teste de coerência: o que **não** incorporar e por quê (evitar colcha de
     retalhos), e como evitar componentes redundantes ou sem função;
   - impacto na interface de agentes e na reprodutibilidade.
4. `04_PLANO_EXPERIMENTAL.md` — hipóteses pré-registradas antes de qualquer
   execução, ablações para medir a contribuição de cada componente novo,
   orçamento igualado, número de sementes, sementes e benchmarks reservados para
   confirmação e critério de sucesso decidido antes de ver os resultados.
5. Uma lista priorizada de implementação (pequenos passos reversíveis, cada um
   com teste) para o usuário aprovar.

Ao final, apresente ao usuário um resumo curto com a recomendação principal,
os ganhos esperados com a incerteza honesta, os riscos e o que precisa da
aprovação dele. Atualize `docs/HANDOFF.md` com o que você fez e o que ficou
pendente.
