
d = log(RMSE agente / RMSE referência), pareado por semente; negativo = melhor. Principal: validação final reportada. Secundária: campeão no fim da busca (convenções diferentes entre braços _ctx e none_guard).

| sistema | comparação | n | mediana d fim | melhores / piores | sign p | mediana d final | melhores / piores (final) | ações aceitas (mediana) |
|---|---|---|---|---|---|---|---|---|
| cascaded_tanks | none_guard_ctx vs none_guard | 10 | 0.183 | 3 / 7 | 0.344 | 0.039 | 4 / 6 | 0 |
| cascaded_tanks | cac41_guard_ctx vs none_guard_ctx | 10 | -0.082 | 6 / 4 | 0.754 | -0.004 | 5 / 5 | 9 |
| wiener_hammerstein | none_guard_ctx vs none_guard | 5 | -0.021 | 3 / 2 | 1.000 | -0.005 | 3 / 2 | 0 |
| wiener_hammerstein | cac41_guard_ctx vs none_guard_ctx | 5 | 0.000 | 0 / 0 | 1.000 | 0.000 | 0 / 0 | 0 |
| silverbox | none_guard_ctx vs none_guard | 5 | -0.004 | 3 / 2 | 1.000 | 0.008 | 2 / 3 | 0 |
| silverbox | cac41_guard_ctx vs none_guard_ctx | 5 | 0.000 | 0 / 0 | 1.000 | 0.000 | 0 / 0 | 0 |
