# Plano experimental proposto — versão A1, anterior às execuções

Data de redação: 2026-11-20. **Pré-registro documental do desenho; execução
condicionada à aprovação.** Não foram executados novos componentes. Resultados
de teste WH/SB da iteração 2 não foram lidos para formular este plano.
O estudo 1.1.0-audit continua separado e congelado. CT é desenvolvimento.

Antes da primeira execução, salvar SHA-256 deste plano, código, binário,
configurações, geradores, máscaras e lista de sementes num manifesto A1.
Mudança posterior cria A2 com justificativa e novas reservas; não substituir
hipóteses após observar resultados. Nada aqui autoriza mudar o protocolo ativo.

## 1. Perguntas e hipóteses falsificáveis

| ID | Hipótese anterior aos resultados | Comparação isolada | Medidas e refutação |
|---|---|---|---|
| H1 | Ajustar θ e intercepto por simulação melhora equações com estrutura fixa | QR × LM curto→longo; mesmas S e inicializações | RMSE longa de validação, convergência e custo; refutada se ganho mediano <10% ou falhas aumentarem |
| H2 | Seleção com admissibilidade longa evita campeões que já divergem em validação | B1 × B2 abaixo | taxa de falhas na validação completa e erro; não alegar prova BIBO nem supor zero falhas no teste |
| H3 | Arquivo erro–tamanho permite sair de soluções pequenas demais sem crescimento arbitrário | B2 × B3 | erro, K, fatores, frente e escolha final; sem apoio se não melhorar erro ≥10% ou exceder teto de tamanho |
| H4 | Sementes ARX/FROLS economizam exploração útil | B3 × B3S | erro em checkpoints de trabalho, diversidade, custo total incluindo semeadura |
| H5 | Um operador local de estrutura ajuda além das sementes | B3S × B3SL, e pacote × sem operador | inclusão no arquivo por tarefa, erro e diversidade; efeito nulo remove o operador |
| H6 | Supervisão por tarefas acrescenta valor ao mesmo catálogo determinístico | B3SL × TF/ TU; controles de ação aleatória e legado | ganho por crédito, erro, falhas, latência; sem melhora ≥10% não recomendar agente como padrão |
| H7 | Continuação por blocos oferece custo/robustez melhores que LM longo desde o início | B1 × B1L | erro por trabalho, convergência e falhas; se equivalente, preferir implementação mais simples |
| H8 | Teto de capacidade, penalidade de fatores e ajuste interagem na retenção de modelos pequenos | Fatorial A1-C em `06_CAPACIDADE_E_AJUSTE.md` | curvas de capacidade, erro/gap, modelos propostos e eliminados; aumentar só o teto não é evidência suficiente |

H1–H8 são hipóteses do AEGIS, não resultados inferidos dos números publicados.
Correlação entre complexidade baixa e erro não prova H3. H2 não depende de
inspecionar os testes WH/SB: é verificável na seleção e nas trajetórias de
validação, inclusive em sistemas sintéticos com divergência tardia conhecida.

## 2. Dados e reservas

| Uso | Dados e sementes | Política |
|---|---|---|
| Desenvolvimento mecânico e protocolo | CT estimação: treino temporal 80%, validação 20%; sementes 21–30 | O teste CT já foi visto nas iterações anteriores; não é confirmação externa. Nenhum teste guia ajuste novo. |
| Checagem transversal de desenvolvimento | Somente estimação WH/SB, mesmo prefixo de 20 mil, 80/20 temporal; sementes 21–30 | Não carregar CSV de teste no processo de busca. Não abrir JSON antigos que carregam teste. |
| Confirmação no domínio | WH e SB; sementes **1001–1020** por condição | Desenho/configuração congelados antes de abrir qualquer teste. Testes existentes da iteração 2 permanecem cegos durante esta tarefa. |
| Transferência reservada | **EMPS**, ainda não executado no AEGIS nesta tarefa, sementes **2001–2020** | Usar fonte oficial e seu protocolo, verificando licença/hash e índices antes de rodar. Sem parâmetros específicos selecionados pelo teste. |
| Checagem estrutural reservada | Gerador sintético A1, sementes de dados **3001–3020**, semente de busca **4001–4020** pareada por índice | Gerar só depois do congelamento; não usá-las para calibrar limites. |

Números das reservas designam novos conjuntos nesta proposta; manifesto deve
verificar inexistência de execuções anteriores com esses papéis antes de
consumi-los. Se houver colisão, registrar novos IDs **antes** de qualquer leitura
de resultado. Trocar semente não produz um novo sistema físico: inferência
entre sementes mede variabilidade do otimizador nesses registros.

EMPS é candidato externo fundamentado nas fontes de Forgione/Piga (§11 da
literatura). Aquisição legal e protocolo são um gate de preparação, não
motivo para trocar por um benchmark fácil após ver erro. Se indisponível,
marcar transferência real como não executada; não afirmar generalização
externa com o sintético como substituto silencioso.

WH/SB: primeira comparação usa exatamente os dados de estimação do estudo
atual, sem afirmar equivalência a treino completo da literatura. Um estudo
secundário com estimação completa tem manifesto próprio, mesmos 80/20 e
orçamento por amostra explicitado; seus resultados nunca substituem os do
prefixo. CT e WH: teste oficial com `n_ini=50`. Silverbox: **multisine**, **arrow
completo**, **arrow sem extrapolação**, três relatórios separados, uma única
equação escolhida antes deles. A máscara da região sem extrapolação deve
ser a oficial versionada do dataloader, não um corte de erro ou amplitude
inventado depois. Simular o arrow completo uma vez e mascarar apenas o score;
não reinicializar a cada trecho da máscara. A ferramenta atual só prepara os
dois CSVs; suporte à máscara ainda precisa ser implementado e testado.

## 3. Experimento de estrutura fixa antes de DE novo

Escolher estruturas **sem teste**: ARX com ny=nu em {2,5,10}, FROLS com
dicionário predefinido e até oito regressores, e dez estruturas sintéticas
geradas com sementes 31–40. Ajustar no treino de cada benchmark; coeficientes
e intercepto QR são a inicialização comum dos braços. Não selecionar a melhor
estrutura pelo teste, nem os campeões antigos por desempenho de teste.

Comparar QR, LM longo desde o início e LM H=50→200→completo. Todos recebem a
mesma cota de trabalho; QR pode usar menos, o saldo não é tempo gratuito para
escolher outras estruturas neste ensaio. Contar tentativas rejeitadas,
trajetórias e soluções lineares. Inspecionar apenas treino/validação.

Gate: H1 precisa de redução mediana ≥10% na validação em pelo menos dois dos
três benchmarks de desenvolvimento, sem aumento de falhas; senão não afirmar
que o ajustador ajuda e não avançar ao pacote como se estivesse validado.
Pode-se investigar com novo plano, preservando o resultado negativo A1.

## 4. Condições e ablações

| ID | Alteração cumulativa, salvo indicação |
|---|---|
| B0 | Algoritmo 1.1.0-audit com instrumentação passiva de custo e identidade; mesmas decisões antigas verificadas em fixture de treino. É referência executada de novo sob contador comum; binário histórico permanece preservado. |
| B0SIM | B0 com `errorMode=simulation`, coeficientes QR; separa pontuação de ajuste. |
| B1 | B0SIM + ajustador de simulação curto→longo para promovidos; seletor escalar mantido. |
| B1L | B1 com LM longo desde o início, sem continuação. |
| B2 | B1 + veto de admissibilidade longa canônica. |
| B3 | B2 + arquivo de duas metas e retirada das penalidades canônicas redundantes. |
| B3S | B3 + 20% de sementes informadas. |
| B3SL | B3S + movimento local de estrutura; escalonador fixo. Pacote proposto sem agente. |
| −FIT, −SAFE, −PARETO, −SEED, −LOCAL | Remover um componente do pacote B3SL por vez; cada remoção usa defaults B0 correspondentes e mantém os demais. Não usar apenas cadeia cumulativa como prova de contribuição independente. |
| TF, TU | B3SL com fuzzy/UCB1 escolhendo tarefas; cota e catálogo iguais. |
| TRANDOM | Mesmo catálogo, escolha aleatória com seed registrada e mesma cota; controla vantagem de simplesmente ter ações novas. |
| TLEGACY | B3SL supervisionado por ações finas UCB1 v1, catálogo legado; custo debitado e objetivo final fixo. Controle de nível de supervisão. |

Sem contar condições duplicadas duas vezes (−LOCAL=B3S; −SEED mantém local
e 100% aleatórios; −PARETO mantém segurança com soma B0; −SAFE mantém arquivo,
mas remove veto longo). Registrar mapa de equivalências no manifesto.
Complementar diagnóstico 2×2 para ajuste sim/não × seleção Pareto/não sob
segurança constante, usando B2/B3 e dois braços QR equivalentes. Isso verifica
interação: um componente pode só ajudar em conjunto.

Todos usam JADE, três ilhas × 50, papéis e regimes, mesma gramática híbrida,
expoentes em passos de 0,5, oito regressores, três fatores, atraso máximo 40
como ponto de partida. Os braços só alteram o item declarado. Não trocar DE
por GP ou NSGA-II. Em B3, preferências de ilha só mudam o necessário para
ordenar erro–tamanho; perfil e critério de migração são registrados.

**Extensão A1-C solicitada pelo usuário antes das execuções:** o estudo H8 em
[06_CAPACIDADE_E_AJUSTE.md](06_CAPACIDADE_E_AJUSTE.md) varia capacidade,
penalidade e ajuste em desenvolvimento. A escolha do teto para confirmação
é congelada após esse estudo, pela regra de validação ali especificada;
o teto de oito regressores acima é o braço histórico, não uma restrição a
testar a hipótese. Nenhum teto do protocolo vivo é alterado.

Correções de contrato futuras (escape da migração e identidade de modelo)
devem existir em um braço **B0C** separado de B0 histórico; B1 em diante usa
B0C como base. Comparar B0C×B0 para não atribuir essas correções ao LM.
A política escolhida para A1 remove o escape não filtrado, mantendo anel
sequencial; anel simultâneo é hipótese futura, não mudança escondida.

## 5. Orçamento igualado, sem avaliações internas grátis

Uma chamada `evaluate` não é unidade suficiente. Implementar contador
determinístico de **operações modeladas**: soma de avaliações de fatores por
amostra; termos acumulados; trabalho QR proporcional a n·q²; trabalho de
solução pequena proporcional a q³. Fórmula A1 em inteiros:

`W = factorRows + termRows + qrRowsTimesColumnsSquared + solveDimensionCubed`.

Contar todas as rotinas, inclusive Ψ para ERR/sementes, diferenças finitas,
passos rejeitados, diagnósticos, migração, reavaliação, seleção e finalização.
Contador não promete FLOPs nem segundos iguais: é proxy explícito e
reproduzível. Medir também tempo de parede, memória de pico, número de
trajetórias, amostras simuladas, fits e avaliações de estrutura. Não comparar
apenas a contagem antiga com a nova.

Fixar antes das execuções:

- Unidade de referência U = `(N_train + N_val) × (24 + 8 + 9²) + 9³`,
  correspondente a contagens convencionais de oito regressores/três fatores
  e nove coeficientes; é escala do contador, não medição de custo antigo.
- Teto por run = 300000·U para CT e 150000·U para WH/SB/EMPS/sintético,
  calculado dos tamanhos de treino/validação registrados, sem usar teste.
- 10% do teto reservado à certificação canônica final e escolha. Um modelo
  sem certificação concluída não pode ser eleito. Custos de teste final
  são registrados fora do orçamento de busca, iguais por modelo/registro.
- Dos 90% restantes no pacote: 5% para sementes, 60% DE, 20% LM e 5% movimento
  local. Em ablações, verba do componente ausente retorna a DE; parcela sem
  uso no braço com componente também retorna a DE em checkpoints fixos.
- Checkpoints a cada 5% de W. Promoção de no máximo um candidato por ilha
  por checkpoint, preferindo candidato local ainda não refinado. Comparar
  pais e trials sob o mesmo contexto; limites do contador verificados antes
  da tarefa. Não ultrapassar o teto para completar uma iteração de LM.

Currículo de treino: 0–30% de W reservado à busca: QR e exploração;
30–60%: LM H=50; 60–80%: H=200; 80–100%: H=treino completo. Blocos contíguos
não sobrepostos percorrem todo o treino; cauda curta é incluída, com contexto
anterior do próprio treino. Janela de pontuação comum: 50 amostras iniciais
do registro; para blocos internos, pontuar desde o primeiro passo previsto.
`H=min(H,N_usable)`; se não houver contexto suficiente, declarar dados
insuficientes, sem usar validação como warmup de treino.

LM: máximo 20 iterações por promoção, tolerância relativa de loss 1e−6,
diferença central h=1e−6·max(1,|θ_j|), amortecimento inicial 1e−3,
×10 após passo rejeitado, ÷3 após aceito, no máximo cinco tentativas por
iteração. Saldo pode encerrar antes. Norma de passo relativa ≤1e−6 encerra;
não existe parada pelo teste. Refinamentos com orçamento insuficiente ficam
registrados como não concluídos. Estes são defaults propostos A1, não valores
calibrados por resultados. CPU sequencial por run; paralelo só entre seeds.

Para tarefas de agentes, a cota por janela é 5% do teto total e nunca amplia
a verba do componente: uma proposta usa o mínimo entre cota da janela, saldo
do componente e saldo global não reservado. Janela de crédito = 5% do teto;
uma ação por janela. Cronograma fixo é o controle. Mudança de fase durante
a janela invalida atribuição, mas nunca apaga o resultado final da run.

## 6. Métricas, falhas e critério decidido agora

**Primária:** RMSE de simulação livre longa em unidades originais; inicialização
conforme protocolo, sem realimentar saídas medidas depois do warmup. Na
confirmação, a família primária contém WH, Silverbox multisine e EMPS;
CT é descritivo, os dois scores arrow são secundários separados.

**Sucesso do pacote B3SL vs B0C:** pelo menos dois dos três benchmarks reais
confirmatórios têm redução mediana pareada de RMSE ≥10%, Wilcoxon bilateral
exato p<0,05 após Holm nas três comparações, nenhuma run inválida do pacote
nesses benchmarks, e nenhuma degradação mediana >5% no terceiro. Gate de
viabilidade: mediana de tempo ≤2× a referência sob W igualado e nenhuma
equação com mais de 40 coeficientes. Preferir a menor capacidade dentro
da tolerância de 1% na validação, conforme A1-C, sem impor mediana K≤20
antes de testar a hipótese de capacidade. Essa revisão foi feita durante
a redação, a pedido do usuário, sem qualquer execução A1 ou A1-C.

Se EMPS não puder ser executado, reportar confirmação incompleta; WH/SB podem
sustentar conclusão restrita, mas não satisfazem sozinhos o gate de três
benchmarks. Redução de 10% é limiar de utilidade escolhido nesta proposta,
não previsão ou cálculo de poder. Vinte seeds não garantem poder suficiente.

Para ablações H1/H3–H7, aplicar o limiar de 10% na validação e Holm na família
de hipóteses H1–H7; H2 é gate de contrato, testado também por construção, não
uma promessa de significância quando ambos os braços têm zero falhas.
Só promover componentes com contribuição mensurável ou função de contrato
demonstrada, mesmo sem ganho de RMSE (p.ex. impedir eleição de modelo inválido).
Não relatar “sem diferença” como equivalência estatística.

Falhas de processo, JSON ausente, modelo não admissível e divergência são
contadas nas 20 tentativas previstas, nunca descartadas para melhorar a
mediana. Reportar erro finito/saturado e flag separadamente, tempo até
falha e denominador de todas as runs. Se qualquer braço de uma comparação
primária tiver falha, o gate estatístico de RMSE dessa comparação não passa;
usar p=1 na família Holm para esse gate e apresentar os erros finitos apenas
descritivamente. Não converter infinito para zero nem imputar melhora.
Falhas de infraestrutura podem ser repetidas com a mesma seed e motivo,
preservando arquivos de ambas as tentativas; falhas algorítmicas não são
substituídas por seeds novas.

Secundárias: one-step RMSE, FIT, erro por horizonte e região, admissibilidade,
K/fatores/atraso, diversidade, correlações de resíduos, ações/recusas,
trajetórias por crédito, latência e custo de API (zero sem autorização).
Curvas em função de W, e também tempo. Bootstrap pareado de 10000 reamostras
de seeds, RNG 12345, para IC de efeito; não interpretar IC entre seeds como
incerteza de nova série temporal. Testes e ordenação sempre bilaterais.

## 7. Gerador sintético reservado e testes de mecanismo

Pré-fixar dois sistemas discretos (histórias iniciais zero):

- Polinomial: `y[k]=0.5*y[k-1]+0.2*u[k-1]+0.1*u[k-2]^2`.
- Racional: `y[k]=(0.4*y[k-1]+0.3*u[k-1])/(1+0.1*u[k-1]^2)`.

Entrada uniforme [−1,1], PRNG com algoritmo e versão explícitos no futuro
gerador C++/Dart, N=6000, primeira metade de cada seed em treino (3000),
1000 seguintes em validação, 2000 finais em teste. Ruído de medição gaussiano
σ=0 e σ=0,02 aplicado só à saída observada, não à dinâmica latente; mesmas
realizações nos braços. Normalizador só no treino. Dados sintéticos de
desenvolvimento usam seeds 41–50, não as reservas. O propósito é recuperar
mecanismos com verdade conhecida, não simular a dificuldade dos benchmarks.

Testes unitários adicionais usam AR `y[k]=1.05*y[k-1]` com contexto pequeno
para divergência tardia, denominador próximo de zero, matriz dependente,
intercepto não nulo e mesma estrutura com coeficientes distintos. Não usar
estes casos como novas evidências de desempenho real.

## 8. Gates de execução e artefatos

1. Aprovação do desenho; nenhum código científico novo antes dela.
2. Build separado, fixtures de invariância B0, contador/identidade/contrato e
   acesso proibido ao teste verificados.
3. Estrutura fixa H1/H7, depois desenvolvimento de ablações; registrar todas
   as falhas e decidir A1 ou novo plano sem abrir teste.
4. Congelar manifesto, política, dados, seeds e máscaras; verificar reservas.
5. Rodar confirmação uma única vez; resultados de todos os braços completos
   antes de abrir o relatório conjunto. Permitir monitorar status, não teste.
6. Gerar `manifest.json`, `runs.csv`, trajetórias, tabelas de efeitos/falhas,
   boxplots e curvas W/tempo, equações e medido×simulado. Verificar figuras
   visualmente. Relatório separa A1, estudo histórico e comparações publicadas.

Nenhuma corrida, download de benchmark novo, chamada paga ou compilação foi
realizada para este plano. Os comandos finais de execução dependem da
implementação aprovada; não se inventam flags já disponíveis no runner atual.
