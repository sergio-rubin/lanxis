#!/usr/bin/env python3
"""Regenerate deterministic SciPy cases checked by the Dart test suite."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import scipy
from scipy import stats


def cases() -> dict:
    sample = np.array([5.0, 8.0, 9.0, 10.0, 12.0])
    experimental = np.array([12.0, 13.0, 14.0, 15.0, 16.0])
    baseline = np.array([1.0, 2.0, 3.0, 4.0, 5.0])
    welch = stats.ttest_ind(experimental, baseline, equal_var=False,
                            alternative="greater")
    mean_ci = stats.t.interval(0.95, len(sample) - 1,
                               loc=float(np.mean(sample)), scale=stats.sem(sample))
    variance_stat = (len(sample) - 1) * np.var(sample, ddof=1) / 4.0
    wilson = stats.binomtest(7, 20).proportion_ci(0.95, method="wilson")
    return {
        "generator": "tools/generate_scipy_reference.py",
        "scipy_version": scipy.__version__,
        "numpy_version": np.__version__,
        "binomial_pmf_20_5_p02": float(stats.binom.pmf(5, 20, 0.2)),
        "binomial_cdf_20_5_p02": float(stats.binom.cdf(5, 20, 0.2)),
        "poisson_cdf_k2_lambda3": float(stats.poisson.cdf(2, 3)),
        "student_cdf_t183_df9": float(stats.t.cdf(1.83, 9)),
        "chi_square_cdf_x132_df6": float(stats.chi2.cdf(13.2, 6)),
        "normal_area_20_50_mu32_sd12": float(
            stats.norm.cdf(50, loc=32, scale=12)
            - stats.norm.cdf(20, loc=32, scale=12)
        ),
        "exponential_cdf_x34_rate07": float(stats.expon.cdf(3.4, scale=1 / 0.7)),
        "mean_ci95_sample": [float(mean_ci[0]), float(mean_ci[1])],
        "wilson_ci95_7_of_20": [float(wilson.low), float(wilson.high)],
        "welch_greater_statistic": float(welch.statistic),
        "welch_greater_pvalue": float(welch.pvalue),
        "variance_greater_statistic": float(variance_stat),
        "variance_greater_pvalue": float(stats.chi2.sf(variance_stat, 4)),
        "exact_proportion_greater_4_of_10_p01": float(
            stats.binomtest(4, 10, 0.1, alternative="greater").pvalue
        ),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    rendered = json.dumps(cases(), ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered, encoding="utf-8")
    else:
        print(rendered, end="")


if __name__ == "__main__":
    main()
