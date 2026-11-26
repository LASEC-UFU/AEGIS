# P2′a: pré-registro da validação estatística

Data: 2026-11-25. Autorização: o usuário pediu "o P2′a em seguida" em
2026-11-25. Origem: [13_P0_PROFILING.md](../../docs/architecture/13_P0_PROFILING.md) §3.2.

**Escrito e enviado ao git antes das execuções de qualidade do P2′a.** A
auditoria por candidato (§2) e a medição de tempo já rodaram e servem só
para conferir a implementação. Os números delas estão no relatório.

## 1. O que é o P2′a

- Opção de configuração `fitMethod` = `"normal"`. O padrão continua `"qr"`,
  idêntico bit a bit ao 1.1.0 + P1.
- Com `"normal"`, só os avaliadores das ilhas (laço interno) usam o novo
  caminho:
  - ajuste por Gram centrado + Cholesky, com colunas dependentes
    descartadas na mesma ordem do QR;
  - ERR por grupo (razão de entrada) no espaço K×K;
  - *fallback* para o caminho exato (Householder) quando um pivô ou um
    resíduo do ERR cai na zona que o Gram não resolve, entre 1e−12 e
    1e−8 da norma original da coluna.
- O avaliador canônico, que reavalia o campeão, continua no QR. **O modelo
  reportado é sempre ajustado pelo QR.**
- Os resultados mudam no último dígito, e a busca diverge por caos. Por isso
  a validação é estatística.

## 2. Conferência por candidato (antes da qualidade)

Com `AEGIS_P2A_AUDIT`, cada candidato é resolvido pelos dois caminhos. Antes
de usar o P2′a, deve valer em CT (6×10⁴ avaliações) e WH (5×10³):
- *fallback* em menos de 5 % dos candidatos;
- descarte de colunas igual ao do QR em mais de 99 % dos candidatos;
- percentil 99 de |SSE_normal − SSE_QR| / SSE_QR < 1e−6.

## 3. Qualidade

- **Célula:** `mr39_zero_simulation` do E3, sementes 21–30, nos três
  benchmarks, com a mesma divisão, orçamento e overrides do E3, mais
  `fitMethod` = `"normal"`. Build: 1.1.0 + P1 + P2′a.
- **Referência:** as execuções do E3 da mesma célula e sementes (binário
  congelado, QR).
- **Medidas:** RMSE de simulação livre na validação (unidades originais),
  divergências e tempo de parede por execução.
- **Critério de equivalência:** em cada benchmark, a razão das medianas
  (P2′a / E3) fica entre 0,90 e 1,10, e o número de divergências na
  validação não aumenta mais de 1.
- **Critério de ganho de tempo:** mediana do tempo de parede por execução
  menor que a do E3 na mesma máquina. No WH e no SB a referência de tempo é
  a do E3, que rodou nesta máquina com 6 processos em paralelo; o P2′a roda
  com até 6.
- **Se a equivalência falhar:** o P2′a não é adotado, e a falha é
  investigada pela auditoria por candidato.
- Nenhum dado de teste é usado. Nenhum parâmetro do P2′a é ajustado depois
  de ver resultados de qualidade.
