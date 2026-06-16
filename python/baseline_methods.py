"""
baseline_methods.py — DE Classic, JADE, GA, PSO baselines for NARX identification.

All methods share the same:
  - Chromosome: binary mask over pre-enumerated polynomial candidate regressors
  - Fitness:    RMSE_val + alpha*BIC/n + gamma*complexity  (from narx_utils)
  - Dataset:    same CSV, same 70/15/15 split, same MinMax normalization

Each method exposes a run(evaluator, cfg, seed) → (best_mask, best_fitness, metrics, history)
"""

from __future__ import annotations
import time
from typing import Callable, Optional

import numpy as np

from narx_utils import NarxEvaluator, NarxConfig


# ─── Shared helpers ─────────────────────────────────────────────────────────

def _random_binary(rng: np.random.Generator, n: int, p_on: float = 0.2) -> np.ndarray:
    """Random binary chromosome with roughly p_on fraction of 1s."""
    return (rng.random(n) < p_on).astype(np.float64)


def _ensure_at_least_one(mask: np.ndarray, rng: np.random.Generator) -> np.ndarray:
    if mask.sum() == 0:
        mask[rng.integers(len(mask))] = 1.0
    return mask


# ─── DE Classic (rand/1/bin, fixed F and CR) ────────────────────────────────

def run_de_classic(
    evaluator: NarxEvaluator,
    n_cands:   int,
    *,
    pop_size:    int   = 100,
    max_gen:     int   = 5000,
    F:           float = 0.5,
    CR:          float = 0.9,
    seed:        int   = 0,
    verbose:     bool  = False,
) -> tuple[np.ndarray, float, dict, list]:
    """
    Classic DE/rand/1/bin on a binary (thresholded) chromosome.

    The continuous DE operates on [0,1]^n; binarization: x[i] > 0.5 → 1 else 0.
    Returns (best_mask, best_fitness, metrics, history).
    history: list of [gen, fitness] pairs.
    """
    rng = np.random.default_rng(seed)

    # Initialize population in [0,1]^n
    pop     = rng.random((pop_size, n_cands))
    fitness = np.full(pop_size, np.inf)

    # Evaluate initial population
    best_fit = np.inf
    best_idx = 0
    history  = []

    for i in range(pop_size):
        mask = (pop[i] > 0.5).astype(np.float64)
        f, _ = evaluator.evaluate(mask)
        fitness[i] = f
        if f < best_fit:
            best_fit = f
            best_idx = i

    history.append([0, float(best_fit)])

    for gen in range(1, max_gen + 1):
        for i in range(pop_size):
            # Mutation: rand/1
            idxs = rng.choice([j for j in range(pop_size) if j != i], 3, replace=False)
            a, b, c = pop[idxs[0]], pop[idxs[1]], pop[idxs[2]]
            mutant = np.clip(a + F * (b - c), 0.0, 1.0)

            # Crossover: binomial
            cross_mask = rng.random(n_cands) < CR
            cross_mask[rng.integers(n_cands)] = True  # ensure at least one dim
            trial = np.where(cross_mask, mutant, pop[i])

            # Selection
            mask = (trial > 0.5).astype(np.float64)
            _ensure_at_least_one(mask, rng)
            f, m = evaluator.evaluate(mask)
            if f <= fitness[i]:
                pop[i]     = trial
                fitness[i] = f
                if f < best_fit:
                    best_fit = f
                    best_idx = i
                    best_m   = m

        history.append([gen, float(best_fit)])
        if verbose and gen % 500 == 0:
            print(f"    [DE-Classic] gen={gen:5d}  fitness={best_fit:.4f}")

    best_mask = (pop[best_idx] > 0.5).astype(np.float64)
    _, best_metrics = evaluator.evaluate(best_mask)
    return best_mask, float(best_fit), best_metrics, history


# ─── JADE (self-adaptive F and CR) ──────────────────────────────────────────

def run_jade(
    evaluator: NarxEvaluator,
    n_cands:   int,
    *,
    pop_size:    int   = 100,
    max_gen:     int   = 5000,
    mu_F:        float = 0.5,
    mu_CR:       float = 0.9,
    c:           float = 0.1,    # JADE learning rate
    p:           float = 0.05,   # top-p fraction (current-to-best)
    seed:        int   = 0,
    verbose:     bool  = False,
) -> tuple[np.ndarray, float, dict, list]:
    """
    JADE: DE/current-to-pbest/1 with self-adapting mu_F and mu_CR.
    Ref: Zhang & Sanderson (2009).
    """
    rng = np.random.default_rng(seed)

    pop     = rng.random((pop_size, n_cands))
    fitness = np.full(pop_size, np.inf)

    for i in range(pop_size):
        mask       = (pop[i] > 0.5).astype(np.float64)
        fitness[i], _ = evaluator.evaluate(mask)

    archive: list[np.ndarray] = []
    history = [[0, float(fitness.min())]]
    best_fit = fitness.min()

    for gen in range(1, max_gen + 1):
        S_F, S_CR = [], []
        top_p_n = max(1, int(p * pop_size))
        top_p_idx = np.argsort(fitness)[:top_p_n]

        for i in range(pop_size):
            # Sample F and CR
            Fi  = np.clip(rng.standard_cauchy() * 0.1 + mu_F,  0.0, 1.0)
            CRi = np.clip(rng.standard_normal() * 0.1 + mu_CR, 0.0, 1.0)
            while Fi <= 0:
                Fi = np.clip(rng.standard_cauchy() * 0.1 + mu_F, 0.0, 1.0)

            # current-to-pbest/1
            pbest = pop[rng.choice(top_p_idx)]
            union = np.vstack([pop, archive]) if archive else pop
            idxs  = rng.choice([j for j in range(len(union)) if j != i], 2, replace=False)
            r1, r2 = union[idxs[0]], union[idxs[1]]
            mutant = np.clip(pop[i] + Fi * (pbest - pop[i]) + Fi * (r1 - r2), 0.0, 1.0)

            cross_mask = rng.random(n_cands) < CRi
            cross_mask[rng.integers(n_cands)] = True
            trial = np.where(cross_mask, mutant, pop[i])

            mask = (trial > 0.5).astype(np.float64)
            _ensure_at_least_one(mask, rng)
            f, _ = evaluator.evaluate(mask)

            if f <= fitness[i]:
                archive.append(pop[i].copy())
                pop[i]     = trial
                fitness[i] = f
                S_F.append(Fi)
                S_CR.append(CRi)
                if f < best_fit:
                    best_fit = f

        # Trim archive
        if len(archive) > pop_size:
            rng.shuffle(archive)
            archive = archive[:pop_size]

        # Update mu_F (Lehmer mean) and mu_CR (arithmetic mean)
        if S_F:
            lm = sum(x**2 for x in S_F) / sum(S_F)
            mu_F  = (1 - c) * mu_F  + c * lm
        if S_CR:
            mu_CR = (1 - c) * mu_CR + c * float(np.mean(S_CR))

        history.append([gen, float(best_fit)])
        if verbose and gen % 500 == 0:
            print(f"    [JADE]       gen={gen:5d}  fitness={best_fit:.4f}  muF={mu_F:.3f}  muCR={mu_CR:.3f}")

    best_idx  = int(np.argmin(fitness))
    best_mask = (pop[best_idx] > 0.5).astype(np.float64)
    _, best_metrics = evaluator.evaluate(best_mask)
    return best_mask, float(best_fit), best_metrics, history


# ─── Genetic Algorithm (binary chromosome, tournament, uniform crossover) ────

def run_ga(
    evaluator: NarxEvaluator,
    n_cands:   int,
    *,
    pop_size:      int   = 100,
    max_gen:       int   = 5000,
    crossover_prob: float = 0.9,
    mutation_prob:  float = 0.02,  # per-bit flip probability
    tournament_k:  int   = 3,
    elitism:       int   = 2,
    seed:          int   = 0,
    verbose:       bool  = False,
) -> tuple[np.ndarray, float, dict, list]:
    """
    Standard binary GA: tournament selection + uniform crossover + bit-flip mutation.
    """
    rng = np.random.default_rng(seed)

    pop     = (rng.random((pop_size, n_cands)) < 0.2).astype(np.float64)
    fitness = np.full(pop_size, np.inf)

    for i in range(pop_size):
        fitness[i], _ = evaluator.evaluate(pop[i])

    history  = [[0, float(fitness.min())]]
    best_fit = fitness.min()
    best_chr = pop[np.argmin(fitness)].copy()

    for gen in range(1, max_gen + 1):
        new_pop = np.empty_like(pop)

        # Elitism: keep top individuals
        elite_idx = np.argsort(fitness)[:elitism]
        new_pop[:elitism] = pop[elite_idx]

        for i in range(elitism, pop_size):
            # Tournament selection (twice)
            def tournament():
                contestants = rng.integers(pop_size, size=tournament_k)
                return pop[contestants[np.argmin(fitness[contestants])]]

            p1, p2 = tournament(), tournament()

            # Uniform crossover
            if rng.random() < crossover_prob:
                mask_x = rng.random(n_cands) < 0.5
                child  = np.where(mask_x, p1, p2)
            else:
                child = p1.copy()

            # Bit-flip mutation
            flip = rng.random(n_cands) < mutation_prob
            child = np.abs(child - flip.astype(np.float64))  # XOR via subtraction

            _ensure_at_least_one(child, rng)
            new_pop[i] = child

        pop     = new_pop
        fitness = np.full(pop_size, np.inf)
        for i in range(pop_size):
            fitness[i], _ = evaluator.evaluate(pop[i])
            if fitness[i] < best_fit:
                best_fit = fitness[i]
                best_chr = pop[i].copy()

        history.append([gen, float(best_fit)])
        if verbose and gen % 500 == 0:
            print(f"    [GA]         gen={gen:5d}  fitness={best_fit:.4f}")

    _, best_metrics = evaluator.evaluate(best_chr)
    return best_chr, float(best_fit), best_metrics, history


# ─── PSO (binary PSO via sigmoid velocity transfer) ────────────────────────

def run_pso(
    evaluator:  NarxEvaluator,
    n_cands:    int,
    *,
    swarm_size: int   = 100,
    max_gen:    int   = 5000,
    w_start:    float = 0.9,
    w_end:      float = 0.4,
    c1:         float = 2.0,  # cognitive
    c2:         float = 2.0,  # social
    v_max:      float = 4.0,
    seed:       int   = 0,
    verbose:    bool  = False,
) -> tuple[np.ndarray, float, dict, list]:
    """
    Binary PSO with sigmoid velocity transfer function.
    Velocity clamped to [-v_max, v_max]; position binarized via sigmoid.
    """
    rng = np.random.default_rng(seed)

    # Initialize positions (binary) and velocities
    pos      = (rng.random((swarm_size, n_cands)) < 0.2).astype(np.float64)
    vel      = rng.uniform(-v_max / 2, v_max / 2, (swarm_size, n_cands))
    pbest    = pos.copy()
    pbest_f  = np.full(swarm_size, np.inf)

    for i in range(swarm_size):
        pbest_f[i], _ = evaluator.evaluate(pos[i])

    gbest_idx = int(np.argmin(pbest_f))
    gbest     = pbest[gbest_idx].copy()
    gbest_f   = float(pbest_f[gbest_idx])

    history = [[0, gbest_f]]

    for gen in range(1, max_gen + 1):
        w = w_start - (w_start - w_end) * gen / max_gen  # linear decay

        r1 = rng.random((swarm_size, n_cands))
        r2 = rng.random((swarm_size, n_cands))

        vel = (w * vel
               + c1 * r1 * (pbest - pos)
               + c2 * r2 * (gbest  - pos))
        vel = np.clip(vel, -v_max, v_max)

        # Sigmoid binarization
        sig = 1.0 / (1.0 + np.exp(-vel))
        pos = (rng.random((swarm_size, n_cands)) < sig).astype(np.float64)

        for i in range(swarm_size):
            _ensure_at_least_one(pos[i], rng)
            f, _ = evaluator.evaluate(pos[i])
            if f < pbest_f[i]:
                pbest[i]   = pos[i].copy()
                pbest_f[i] = f
                if f < gbest_f:
                    gbest   = pos[i].copy()
                    gbest_f = f

        history.append([gen, gbest_f])
        if verbose and gen % 500 == 0:
            print(f"    [PSO]        gen={gen:5d}  fitness={gbest_f:.4f}  w={w:.3f}")

    _, best_metrics = evaluator.evaluate(gbest)
    return gbest, float(gbest_f), best_metrics, history
