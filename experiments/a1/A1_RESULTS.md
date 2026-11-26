# A1: resultados (teste aberto uma vez)

Gerado por `tool/experiments/a1_analysis.dart` (A1_PREREG.md §4–§5).

| benchmark | pares | mediana teste A1 | mediana teste 1.1.0 | razão | p (Wilcoxon, unilateral) | divergências teste A1 / 1.1.0 | mediana validação A1 / 1.1.0 | K mediano A1 / 1.1.0 | refino aplicado | wall mediano s A1 / 1.1.0 |
|---|---|---|---|---|---|---|---|---|---|---|
| wiener_hammerstein | 10 | 0.009320 | 0.04610 | 0.202 | 0.0010 | 0 / 0 | 0.008549 / 0.05077 | 34.0 / 6.0 | 8/10 | 2294 / 502 |
| silverbox | 10 | 0.0003486 | 0.003775 | 0.092 | 0.0010 | 0 / 0 | 0.0003092 / 0.003335 | 28.5 / 7.0 | 10/10 | 2136 / 502 |
| cascaded_tanks | 10 | 0.7124 | 0.6606 | 1.078 | 0.8623 | 3 / 0 | 0.4312 / 0.8341 | 28.0 / 4.0 | 6/10 | 127 / 29 |

## Critério primário (WH e SB)

- wiener_hammerstein: razão 0.202, p Holm 0.0020 → atingido
- silverbox: razão 0.092, p Holm 0.0020 → atingido

**Gate primário: ATINGIDO.**
