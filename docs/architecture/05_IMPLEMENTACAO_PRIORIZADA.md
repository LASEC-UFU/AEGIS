# Implementação priorizada para aprovação

Data: 2026-11-20. **Lista proposta; nenhuma etapa de implementação científica
abaixo foi iniciada.** Regras e fronteiras em
[03_PROPOSTA_INTEGRADA.md](03_PROPOSTA_INTEGRADA.md); critérios em
[04_PLANO_EXPERIMENTAL.md](04_PLANO_EXPERIMENTAL.md).

O prompt exige: “Não implemente mudanças grandes antes de o usuário aprovar
o desenho.” A entrega atual é o desenho documentado, não autorização implícita
para executá-lo. Cada passo deve permanecer reversível por flag, esquema ou
build separado. Nada exige apagar dados ou reescrever o protocolo 1.1.0.

| Prioridade / passo | Mudança pequena e revisável | Teste ou evidência exigida | Reversão / gate |
|---|---|---|---|
| P0.1 | Manifesto e build `cpp/build_arch_a1`, resultados próprios; registrar SHA do núcleo congelado | nenhum arquivo do build/resultados histórico alterado; manifesto resolve dados e versões | remover só os artefatos novos identificados, mediante regras locais; código antigo intacto |
| P0.2 | Instrumentação passiva W, `BudgetLedger`, reserva de certificação | soma por tarefa em casos manuais, nunca saldo negativo; teste de tentativa LM abortada debitada; limites antes da tarefa | flag desligada reproduz decisões antigas; sem contador correto não executar comparação |
| P0.3 | Separar identidade de estrutura, modelo ajustado e score; capabilities | mesma S com θ/c distintos nunca compartilha score; contexto e split invalidam cache; colisão simulada não troca modelos | esquema v1 permanece; sem identidade correta não inserir LM |
| P0.4 | Formalizar migração e mérito B0C em braço separado | migrante pior/igual rejeitado mesmo com origem estagnada; reavaliação destino; ordem do anel documentada | configuração antiga preserva escape histórico só na reprodução B0 |
| P0.5 | Separar `fit` e `score`, ainda usando só QR | fixture de treino mantém θ, métricas e decisões de B0; score/refit explícitos; validação não altera θ | adaptador legado disponível |
| P1.1 | Loss de simulação em estrutura fixa, incluindo intercepto | polinomial/racional conhecidos, warmup comum, nenhum y medido depois do contexto; dados de teste inacessíveis | loss nova opt-in, sem alterar `errorMode` histórico |
| P1.C | Estudo de capacidade/parcimônia A1-C, `06_CAPACIDADE_E_AJUSTE.md`, antes de fixar Kmax | curvas K=4/9/20/40; base Legendre/monômios equivalente; teto × γ × QR/LM; contabilizar posto, erros de treino/validação e rejeição por tamanho | estudo separado com W fixo; nenhum aumento do teto do protocolo histórico; gate H8 |
| P1.2 | LM de simulação completo e custos, ainda sem blocos | checagem de Jacobiano por diferença independente; caso QR não ótimo em simulação; intercepto move; rollback em NaN/singularidade | seed QR preservada, motivo de rejeição exportado |
| P1.3 | Blocos determinísticos e cronograma de horizonte | contexto dentro do treino, todos os índices cobertos, cauda curta, H maior que dados; nunca rotular loss truncada como longa | comparar com LM longo, gate H1/H7 |
| P1.4 | Admissibilidade canônica longa como veto explícito | AR com divergência tardia passa no curto e falha no longo; denominador bruto; arquivo vazio reporta falha | flag −SAFE; não alegar certificado BIBO |
| P2.1 | Arquivo erro–K e escolha determinística | fronteira conhecida, dominância, empate, ordem de inserção, teto 64, regra 1%; número de θ inclui c | seletor escalar B0 como ablação −PARETO |
| P2.2 | Papéis/regimes/currículo na nova avaliação | mesmo modelo e contexto têm mesmo score; mudança de fase não compara scores incompatíveis; canonização completa mantida | perfis fixos de B0 disponíveis, gate H3 |
| P2.3 | Sementes ARX/FROLS pelo serviço compartilhado | dicionário/limites/custo; 80% aleatórios; sem seleção por teste; nenhuma “BLA” indevida | 100% aleatórios (−SEED), gate H4 |
| P2.4 | Uma tarefa local de estrutura e reinserção no DE | remoção/inserção/troca; coeficientes invalidados; custo; aceitação pelo score e não por ERR | −LOCAL; eliminar poda final duplicada no caminho novo, gate H5 |
| P3.1 | Escalonador fixo e telemetria de tarefas | cotas somam ao teto; crédito em W; finalização consome reserva; nenhuma tarefa extra após orçamento | padrão sem agente mantido |
| P3.2 | Esquemas v2 e agentes fuzzy/UCB1 de tarefas | rejeição de tarefa/limite/backend incapaz; cooldown/kill switch; replay do log reproduz execução; testes nativo/WASM por capacidade | agentes finos v1 apenas no caminho legado; gate H6 |
| P3.3 | Adaptar LLM ao catálogo v2 com mocks | recusa/timeout/schema/orçamento e fallback; replay sem rede | **sem API paga**; ensaio real só com autorização específica de provedor, chamadas e custo |
| P4.1 | Manifestos de dados novos, máscara SB e gerador reservado | hashes/fontes/licenças; máscara oficial sem novo warmup; PRNG/versionamento; teste sintético contra equação conhecida | não consumir reservas em teste de desenvolvimento |
| P4.2 | Análise por W e falhas, sem executar confirmação ainda | fixture inclui falha/duplicata/par incompleto; Holm com família completa; teste de arredondamento; todas as tentativas no denominador | não reutilizar automaticamente o analisador de contagem antiga |
| P4.3 | Execução do plano aprovado e figuras | cumprir gates, registrar resultados negativos, validar medido×simulado/curvas visualmente | A1 preservado; qualquer redesenho vira A2 com novas reservas |

Os novos testes devem verificar comportamento científico/contratos, não
espelhar a implementação. Rodar `core_tests`, `api_tests`, `flutter test` e
`dart analyze lib test tool` no build/contexto correspondente após cada lote
que alterar comportamento; não recompilar o núcleo usado pelo protocolo vivo.
Compilação Windows app/MSVC e WASM continuam gates de ambiente, sem afirmar
que testes MinGW provam paridade entre backends.

## Aprovação sugerida por etapa

1. **Primeiro lote:** P0 e P1, sem alterar agentes nem adotar todos os opcionais.
2. **Segundo lote:** P2 se o ensaio de estrutura fixa sustentar o ajustador.
   A escolha de capacidade também depende de H8; não congelar oito regressores
   como padrão futuro sem testar essa hipótese. P1.C usa LM após P1.2/P1.3;
   suas curvas QR podem preceder essas duas etapas.
3. **Terceiro lote:** P3 só após tarefas úteis sob escalonador fixo.
4. **Confirmação:** P4 após congelamento e validação de todos os contratos.

Aprovar o desenho não obriga manter um componente cujo ensaio falhe. Ganhos
esperados são hipóteses; os riscos principais são custo LM, mínimos locais,
viés por contextos medidos e exploração excessiva da validação. As ablações
e reservas decidem o que permanece.
