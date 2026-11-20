# Fase 0: relatório de E1 e E2

Data: 2026-11-20. Pré-registro: [PHASE0_PREREG.md](PHASE0_PREREG.md), commit
`d275810`, anterior a todas as execuções. Tabela completa por estrutura:
[SUMMARY_E1E2.md](../results_phase0/SUMMARY_E1E2.md). Dados brutos:
`experiments/results_phase0/<b>/e1e2.jsonl`. Manifesto com hashes:
`experiments/results_phase0/MANIFEST.jsonl`. O E3 (triagem só por
configuração) está agendado para depois do protocolo 1.1.0 e terá relatório
próprio.

**Só validação.** Nenhum dado de teste foi lido. A métrica é o RMSE de
simulação livre na validação, em unidades originais. Não é comparável com os
números de teste da literatura (ver `docs/architecture/02_LITERATURA.md`).

## 1. Integridade

- **Testes da ferramenta:** 11 de 11 passaram antes do uso com dados reais.
- **Consistência:** o simulador da Fase 0 reproduziu o RMSE livre de treino
  do avaliador do núcleo em **todas** as 52 estruturas, com diferença
  relativa ≤ 1e−9.
- **Campeões:** os 7 + 3 + 3 campeões distintos do `aegis_full` 1.1.0 foram
  reajustados por QR com a mesma divisão. Os coeficientes são idênticos aos
  originais (diferença máxima 0), o que confirma que a divisão e o ajuste
  são os mesmos do estudo.
- **Sem execução:** nenhuma estrutura da tabela principal deixou de ser
  executada. Todas são polinomiais e nenhuma excede q = 150.

## 2. Resultado dos critérios pré-registrados

| | CT | WH | SB | Critério (2 de 3) |
|---|---|---|---|---|
| **E1**: PN_K40 (QR) / mediana dos campeões | 1,013 / 0,848 V = **1,19** ✗ | 26,5 / 50,8 mV = **0,52** ✓ | 0,60 / 3,34 mV = **0,18** ✓ | **apoiado** |
| **E2**: mediana de (V_LM − V_QR)/V_QR | **+4,8 %** ✗ (1 divergência com LM) | **−1,1 %** ✗ (1 divergência com LM) | **−52,1 %** ✓ (0 divergências) | **não apoiado** |

**Leitura pré-registrada:**
- **E1:** a capacidade, com estruturas fixas e QR, supera os campeões do
  AEGIS no WH e no SB.
- **E2:** o ajuste por erro de simulação, sem restrição de estabilidade, não
  melhora a validação de forma consistente.

## 3. Números principais (validação, RMSE de simulação livre)

| Estrutura | K | CT (V) QR → LM | WH (mV) QR → LM | SB (mV) QR → LM |
|---|---|---|---|---|
| Campeões AEGIS (mediana) | 4–7 | 0,848 → 0,942 | 50,8 → 48,2 | 3,34 → 1,94 |
| ARX_L (atrasos do DCE) | 14 / 19 / 22 | 0,859 → 0,949 | 48,2 → 48,1 | 6,27 → **76,7** |
| PN_K20 | 20 | 1,101 → **0,727** | 28,8 → 26,1 | 0,92 → 0,31 |
| PN_K40 | 40 | 1,013 → **28,5 (diverge)** | 26,5 → 26,1 | 0,60 → 0,27 |
| PN_DCE | 40 / 91 / 148 | 1,141 → 0,909 | 25,2 → **2 727 (diverge)** | 0,53 → 0,27 |
| E1b_5 (espinha ARX + 5) | 19 / 24 / 27 | 1,658 → 1,059 | 26,4 → 26,1 | 0,70 → 0,28 |

## 4. O que os dados mostram, e o que não mostram

1. **WH e SB: o AEGIS 1.1.0 fica preso em modelos pequenos demais.**
   - No WH, os campeões (6–7 coeficientes) empatam com um ARX linear
     (48–51 mV).
   - Estruturas univariadas simples de 20–40 termos, escolhidas por FROLS
     só no treino e ajustadas por QR, chegam a cerca de 26 mV.
   - No SB a diferença é de 5 a 6 vezes.
   - Isso apoia a hipótese do 06 (capacidade e parcimônia) e o H8.
   - **O que isso não mostra:** se a causa é o teto de regressores, as
     penalidades ou a exploração. O E3 e o H8 reduzido servem para separar
     essas causas.
2. **CT: mais capacidade piora a validação.**
   - Com o registro curto (819 amostras de treino) e uma validação de 205
     amostras, modelos de 20–40 termos ajustados por QR simulam pior que os
     campeões de 4 coeficientes.
   - A hipótese de capacidade **não** vale para o CT. Não se deve
     generalizar a partir de WH e SB.
3. **O ajuste por simulação (LM) ajuda no SB, é neutro no WH e atrapalha no
   CT.**
   - Ele sempre reduz o erro de **treino** (exceto em casos já no ótimo).
   - Mas sobreajusta a trajetória: no CT os campeões pioram de 0,85 para
     0,94 V.
   - Gera modelos que divergem na validação: PN_K40 no CT e PN_DCE no WH.
   - Também piora muito o ARX_L do SB (6,3 → 76,7 mV), apesar de reduzir
     o erro de treino.
   - Sem veto de admissibilidade e sem regularização, **o LM não deve
     entrar como componente padrão.** Isso confirma a ordem defendida no
     parecer: veto de admissibilidade antes do LM.
4. **E1b, a espinha linear (descritivo):**
   - no WH e no SB, a espinha ARX com 3 a 5 termos não lineares chega perto
     do PN_K40 com menos termos: WH 26,4 contra 26,5 mV; SB 0,70 contra
     0,60 mV;
   - no CT é pior que os campeões.
   - Apoia manter o H9 como hipótese, não adotá-lo.
5. **Controle u(k) contemporâneo (descritivo, com QR):**
   - **WH:** muda menos de 1 %.
   - **SB:** melhora de 8 a 16 % (ARX 6,27 → 5,75 mV; PN_DCE 0,529 →
     0,445 mV).
   - **CT:** piora o ARX (0,861 → 0,888 V) e melhora o PN_DCE (1,143 →
     1,092 V).
   - Leitura: a convenção de atrasos do AEGIS (a partir de 1) custa algo no
     SB, mas não explica a diferença principal, que é de 5 a 6 vezes entre
     campeões e estruturas maiores. Incluir u(k) é decisão de representação
     a registrar no A1, não um ajuste silencioso.

## 5. Consequência para o A1, conforme o pré-registro

**Priorizar** capacidade, representação e pressão de seleção:

- teto de regressores;
- pesos de parcimônia;
- avaliação de candidatos maiores;
- a espinha linear como hipótese.

O E3 diz se a triagem só por configuração já mostra esse efeito dentro do
próprio AEGIS. Depois vem o H8 reduzido (M7).

**Não priorizar** o ajustador LM como componente padrão. Ele pode voltar
como refinamento opcional, só depois do veto de admissibilidade e com teste
próprio. Isso seria um plano novo, não este.

**No CT,** qualquer aumento de capacidade precisa de controle de
complexidade que funcione com registros curtos. É um caso de teste
importante para não piorar o CT ao melhorar WH e SB.

## 6. Limitações

- Uma única divisão treino/validação por benchmark. As estruturas não são
  amostras independentes. Os critérios são de desenvolvimento, não
  confirmatórios.
- No WH e no SB a estimação usa 20 000 amostras, não o conjunto completo.
- Os campeões são do estudo 1.1.0, com a configuração `aegis_full`. Outras
  configurações do AEGIS podem gerar modelos maiores; o E3 testa isso.
- O LM seguiu exatamente o pré-registro: sem regularização, sem restrição de
  estabilidade, 100 iterações. Variantes regularizadas não foram testadas e
  não devem ser inferidas destes resultados.
