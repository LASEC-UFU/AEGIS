# P1 e P2′a: relatório de velocidade

Data: 2026-11-26. Origem: [13_P0_PROFILING.md](../../docs/architecture/13_P0_PROFILING.md).
Pedido do usuário (2026-11-25): "faça o P1 agora, o P2′a em seguida". Patch
completo (P0 + P1 + P2′a + ferramenta do P6):
[p1_p2a_p6.patch](p1_p2a_p6.patch), aplicado num git worktree separado;
`cpp/build` e `cpp/build_phase0` não foram tocados. Compilador: g++ 16.1 do
MSYS2 desta máquina.

**Só validação.** As execuções de WH e SB usam a divisão do E3, sem segmento
de teste.

## 1. P1: otimizações exatas

**O que mudou:**
1. **ERR completo só no avaliador canônico.** O ERR completo (`chrom.err`)
   não entra no fitness. As ilhas deixam de calculá-lo. O campeão é sempre
   reavaliado pelo avaliador canônico, que continua calculando, então
   relatório, exportação JSON, poda e agentes recebem o mesmo valor.
2. **Cache de séries de fator na montagem de Ψ.** Cada série g_p(x_v(r)) é
   calculada uma vez por bloco de dados (identificado por ponteiro,
   dimensões e impressão digital do conteúdo, recalculada a cada chamada) e
   reaproveitada. Ψ é preenchida linha por linha, com os fatores
   multiplicados na mesma ordem de antes.
3. **QR por linhas.** A atualização de Householder acumula os produtos
   internos de todas as colunas numa varredura por linhas. Para cada coluna,
   a ordem das somas é a mesma.

**Validação (bit a bit):** `experiments/perf/check_bitid.sh` compara o JSON
inteiro da execução, menos campos de tempo e caminho.

| Comparação | Resultado | Tempo antes → depois |
|---|---|---|
| CT `aegis_full` semente 1, com teste do CT, contra a saída do binário congelado | idêntico | 23,9 → 23,5 s |
| CT E3 `mr39_zero_simulation` semente 21, contra o `run_21.json` do E3 | idêntico | 936 → 398 s |
| WH `mr39_zero_simulation`, 3×10⁴ avaliações, contra o P0 | idêntico | 2 628 → 1 438 s |
| WH `mr39_zero_one_step`, 3×10⁴ avaliações, contra o P0 | idêntico | 2 497 → 1 371 s |
| SB `mr39_zero_simulation`, 10⁴ avaliações, novo contra congelado | idêntico | 1 202 → 459 s |
| CT `powerMode` = `signed`, 5×10⁴, novo contra congelado | idêntico | 168 → 70 s |
| CT `powerMode` = `legacy`, 5×10⁴, novo contra congelado | idêntico | 171 → 70 s |

`core_tests` 91/0, `api_tests` 66/0 e `phase0_tests` 11/0 nos builds novos.
**Ganho do P1: 1,8–2,6× nos modelos grandes, sem mudar nenhum número.** Nos
modelos pequenos (CT `aegis_full`, K ≈ 3), o ganho é ≈ 2 %.

## 2. P2′a: ajuste pelo Gram centrado

**O que mudou:** opção `fitMethod` = `"normal"` (padrão `"qr"`, que segue
idêntico bit a bit; conferido no CT `aegis_full` semente 1). Com `"normal"`,
as ilhas:
- ajustam pelo Gram centrado + Cholesky, descartando colunas dependentes na
  mesma ordem do QR;
- calculam o ERR por grupo (razão de entrada) no espaço K×K;
- caem para o caminho exato quando um pivô ou resíduo do ERR fica entre
  1e−12 e 1e−8 da norma original.

O campeão reportado continua ajustado pelo QR. Pré-registro:
[P2A_PREREG.md](P2A_PREREG.md), commit `dba3e22`, anterior às execuções de
qualidade.

### 2.1 Auditoria por candidato (pré-registro §2)

Cada candidato resolvido pelos dois caminhos (`AEGIS_P2A_AUDIT`,
`tool/experiments/p2a_audit.dart`):

| | CT, 6×10⁴ avaliações | WH, 5×10³ avaliações | Exigido |
|---|---|---|---|
| Caminho rápido usado | 60 013 de 60 015 (2 *fallbacks*) | 5 115 de 5 115 | > 95 % |
| Descarte de colunas igual ao do QR | 100 % | 100 % | > 99 % |
| p99 de \|ΔSSE\|/SSE | 4,7e−9 | 2,5e−9 | < 1e−6 |
| Mediana de \|Δθ\|/max\|θ\| | 1,1e−12 | 2,1e−13 | — |
| Máximo de \|Δ razão de entrada\| | 1,3e−8 | 2,0e−9 | — |

### 2.2 Qualidade e tempo (pré-registro §3)

Célula `mr39_zero_simulation`, sementes 21–30, contra o E3
(`tool/experiments/p2a_quality.dart`):

| Benchmark | RMSE val. mediano, P2′a / E3 | Razão | Divergências | Campeão idêntico ao do E3 | Tempo mediano por execução, P2′a / E3 | Ganho |
|---|---|---|---|---|---|---|
| CT | 0,4943 / 0,4943 V | 1,000 ✓ | 0 / 0 | 10 de 10 | 134 / 874 s | **6,5×** |
| WH | 10,84 / 10,73 mV | 1,010 ✓ | 0 / 0 | 5 de 10 | 1 704 / 24 752 s | **14,5×** |
| SB | 0,331 / 0,343 mV | 0,965 ✓ | 0 / 0 | 4 de 10 | 1 484 / 25 746 s | **17,3×** |

**Critério de equivalência atingido nos três benchmarks** (razão entre 0,90
e 1,10, nenhuma divergência nova). Critério de tempo atingido nos três.

**Ressalvas do tempo:**
- No E3, cada célula rodou com 6 execuções em paralelo. No P2′a, o CT rodou
  com 1 execução por vez (com outros processos na máquina), o WH com 3 e o SB
  com 2. A disputa por CPU foi menor no P2′a, o que favorece o P2′a. Os
  ganhos de tempo são ordem de grandeza, não medidas controladas.
- **Desvio operacional:** WH e SB começaram com 1 execução por vez e foram
  interrompidos 3 minutos depois, sem nenhum resultado, para rodar com 3 e 2
  em paralelo. Nenhum parâmetro foi alterado.

## 3. Consequência

- **P1:** pode entrar no núcleo sem nova validação estatística, porque é
  idêntico bit a bit. Decisão do usuário: quando aplicar ao código principal
  (hoje está só no patch).
- **P2′a:** equivalente em qualidade e 6–17× mais rápido que o 1.1.0 nas
  células grandes. Uma execução do WH com K ≈ 33 cai de ≈ 7 h para ≈ 30 min.
  Recomendado como padrão das ilhas para os experimentos do A1, com o
  campeão sempre certificado pelo QR.
- **P2′b** continua fora (13 §3.2).
