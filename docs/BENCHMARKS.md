# Benchmarks: provenance, licences and preprocessing

Raw and processed data are **not versioned** (`experiments/data/` is
git-ignored). They are downloaded from the original sources and verified by
SHA-256 by `tool/benchmarks/prepare_benchmarks.dart`. Splits follow the
open-source dataloader `nonlinear_benchmarks` (G. Beintema, M. Schoukens),
which encodes the official protocols of nonlinearbenchmark.org.

## Sources

| Benchmark | Original source (download) | Licence / terms | Cite |
|---|---|---|---|
| Cascaded Tanks | 4TU.ResearchData, doi:10.4121/12960104 — `https://data.4tu.nl/file/d4810b78-6cdd-48fe-8950-9bd601e5f47f/3b697e42-01a4-4979-a370-813a456c36f5` (`CascadedTanksFiles.zip`, MD5 `f832776ed1efdca4572338f467b7baec`, verified) | **CC BY-SA 4.0** (stated on the 4TU record) | M. Schoukens, P. Mattsson, T. Wigren, J.P. Noël, *Cascaded tanks benchmark combining soft and hard nonlinearities*, 4TU.ResearchData, doi:10.4121/12960104; M. Schoukens, J.P. Noël, *Three benchmarks addressing open challenges in nonlinear system identification*, 20th IFAC World Congress, Toulouse, 2017, pp. 448–453, doi:10.1016/j.ifacol.2017.08.071 |
| Wiener–Hammerstein | `http://www.ee.kth.se/~hjalmars/ifac_tc11_benchmarks/2009_wienerhammerstein/WienerHammerBenchMark.mat` (MATLAB 5, 1 707 601 bytes) | **No licence stated** on nonlinearbenchmark.org or at the KTH URL. Used for academic benchmarking as intended by its authors; not redistributed. | J. Schoukens, J. Suykens, L. Ljung, *Wiener–Hammerstein benchmark*, 15th IFAC Symposium on System Identification (SYSID 2009), Saint-Malo, France |
| Silverbox | Google Drive file `17iS-6oBUUgrmiAcrZoG9S5sOaljZnDSy` (`SilverboxFiles.zip`, 5 793 999 bytes), linked from nonlinearbenchmark.org | **No licence stated.** Used for academic benchmarking; not redistributed. | T. Wigren, J. Schoukens, *Three free data sets for development and benchmarking in nonlinear system identification*, European Control Conference 2013, pp. 2933–2938, doi:10.23919/ECC.2013.6669201 |
| (platform) | nonlinearbenchmark.org | — | M. Schoukens, M. Champneys, G.I. Beintema, T.J. Rogers, *Benchmarking for nonlinear system identification: submission platform and baseline results*, Data-Centric Engineering 7:e40 (2026), doi:10.1017/dce.2026.10067 |

The bibliographic entries were taken from the benchmark pages
(nonlinearbenchmark.org, accessed 2026-11-20). Volume/page data for the IFAC
WC 2017 paper should be double-checked against the publisher before
submission.

**Decision pending for the authors:** WH and Silverbox carry no explicit
licence. Before publishing derived data or figures that reproduce the
signals, confirm the terms with the benchmark maintainers. The scripts only
download and hash; they never redistribute.

## Raw file hashes (SHA-256)

| File | SHA-256 |
|---|---|
| `cascaded_tanks/CascadedTanksFiles.zip` | `eb0fa05851e8a7136846c2e3b61fbef87def78d0852c86ab91b02ac5db541b51` |
| `wiener_hammerstein/WienerHammerBenchMark.mat` | `096e6128687efb664d146d28fc17db4c5a94f247c4b3a2e451319be1efb25ae2` |
| `silverbox/SilverboxFiles.zip` | `2398dda503ac4c30f46c7a1ba09d8a8864d001cc71bbeb59f207a054cc592d8c` |

## Preprocessing (deterministic)

| Benchmark | Estimation file used | Test file(s) | fs | Init. window |
|---|---|---|---|---|
| Cascaded Tanks | `uEst, yEst` (1024) | `uVal, yVal` (1024) | 0.25 Hz (Ts = 4 s) | 50 |
| Wiener–Hammerstein | samples [5200, 25200) of the record = first 20 000 samples of the official training set [5200, 105200) | official test [105200, 184000) (78 800) | 51 200 Hz | 50 |
| Silverbox | first 20 000 samples of the multisine training part [40650, 105712) of `SNLS80mV` (V1 input, V2 output) | `test_multisine` [105712, 127400) (21 688); `test_arrow` [100, 40575) (40 475, includes amplitude extrapolation) | 610.35 Hz | 50 |

Processed-file SHA-256: CT est `1478b6870d8273f38323bb3c33da0634aae3a2b19d48fa1667f9863daab3298b`,
CT test `42ad224d2a9083f88038c950023fb3b6861133245ea8de775f607fe192abb87b`,
WH est `823c2a47b9350e30df9feac418c45483a5eca4883a57034eec6d973838a20595`,
WH test `a1b92da4de6ced4cdc6b3777befcaf3626e007654d1d0aa57613dd00b2bce9a2`,
SB est `2f46d88b9c4c332c3c3f5fd9409c813df75a73f24985fa572b0dfce5b1096002`,
SB test_multisine `5c60d9c4aea1d71ca53390474cabb6f41bc0cfcfcb14c8a2a129674166483563`,
SB test_arrow `3613274b0b4a4d11cebd7501f9d640cdad3394cb3d22f7bfa6498097482eb80b`
(all listed in `experiments/data/processed/PROVENANCE.json`).

Within each estimation file the split is temporal: first 80 % training,
last 20 % validation. Normalization (min-max to [−1, 1]) is fitted on the
training rows only and applied without clipping to every row. The test
record is appended after the estimation rows (`testStartRow`); its first 50
samples serve as measured initial conditions and are excluded from the
metric, as in the `nonlinear_benchmarks` convention.

**Deviation from the full protocol (compute budget):** for WH and
Silverbox only the first 20 000 samples of the official training sets are
used for estimation (≈ 20 % and 31 %, respectively); the test sets are
complete. Results are therefore not directly comparable with literature
values obtained with the full training sets.

## Repository file of unknown provenance

`Benchmarks/WH_estimation_uy.csv` (8192 samples, SHA-256
`13925d266c85f46737c5d528b9813bb6c073d98f37bb59090020e76b9997c491`) does
**not** match any segment of the official Wiener–Hammerstein record
(checked sample by sample at 10⁻⁶ tolerance). Its origin is unknown; it is
kept for the app's examples but not used in the evaluation.
