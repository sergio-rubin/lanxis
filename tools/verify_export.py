#!/usr/bin/env python3
"""Independent numerical review of a real LANXIS JSON or CSV export.

This optional program is never used by the Flutter application. It preserves
failed requests in SLA counts and excludes warm-up observations from analysis.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

import numpy as np
import pandas as pd
import scipy
from scipy import stats


def load_measurements(path: Path) -> pd.DataFrame:
    if path.suffix.lower() == ".json":
        payload = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(payload, dict) or not isinstance(
            payload.get("measurements"), list
        ):
            raise ValueError("JSON LANXIS sin lista measurements")
        frame = pd.DataFrame.from_records(payload["measurements"])
    elif path.suffix.lower() == ".csv":
        frame = pd.read_csv(path)
    else:
        raise ValueError("Use una exportación .json o .csv de LANXIS")
    if frame.empty and not len(frame.columns):
        frame = pd.DataFrame(columns=["id_escenario", "latencia_ms", "exito_sla"])
    required = {"id_escenario", "latencia_ms", "exito_sla"}
    missing = required - set(frame.columns)
    if missing:
        raise ValueError(f"Columnas requeridas ausentes: {sorted(missing)}")
    if "warmup" in frame:
        is_warmup = frame["warmup"].map(
            lambda value: value is True or str(value).lower() in {"true", "1"}
        )
        frame = frame.loc[~is_warmup].copy()
    frame["latencia_ms"] = pd.to_numeric(frame["latencia_ms"], errors="coerce")
    frame["exito_sla"] = pd.to_numeric(frame["exito_sla"], errors="coerce")
    if not frame["exito_sla"].isin([0, 1]).all():
        raise ValueError("exito_sla debe contener solamente 0 o 1")
    if "clientes" in frame:
        frame["clientes"] = pd.to_numeric(frame["clientes"], errors="coerce")
    if "success" in frame:
        frame["success"] = frame["success"].map(
            lambda value: value is True or str(value).lower() in {"true", "1"}
        )
    else:
        frame["success"] = frame["latencia_ms"].notna()
    return frame


def finite_latencies(frame: pd.DataFrame) -> np.ndarray:
    values = frame.loc[frame["success"], "latencia_ms"].to_numpy(dtype=float)
    return values[np.isfinite(values) & (values >= 0)]


def summarize(frame: pd.DataFrame) -> dict:
    values = finite_latencies(frame)
    n = len(values)
    requests = len(frame)
    sla = int((frame["exito_sla"] == 1).sum())
    result = {
        "solicitudes": requests,
        "latencias_validas": n,
        "fallidas_o_sin_latencia": requests - n,
        "sla_cumplidas": sla,
        "proporcion_sla": sla / requests if requests else None,
        "media_ms": float(np.mean(values)) if n else None,
        "mediana_ms": float(np.median(values)) if n else None,
        "varianza_muestral_ms2": float(np.var(values, ddof=1)) if n > 1 else None,
        "desviacion_muestral_ms": float(np.std(values, ddof=1)) if n > 1 else None,
        "percentiles_ms": {
            str(p): float(np.percentile(values, p)) if n else None
            for p in (50, 90, 95, 99)
        },
    }
    if n > 1 and np.std(values, ddof=1) > 0:
        sem = stats.sem(values)
        result["ic95_media_t_ms"] = list(
            map(float, stats.t.interval(0.95, n - 1, loc=np.mean(values), scale=sem))
        )
    else:
        result["ic95_media_t_ms"] = None
        if n > 1:
            result["advertencia_ic_media"] = (
                "Datos constantes: no se interpreta un intervalo t inferencial."
            )
    if requests:
        interval = stats.binomtest(sla, requests).proportion_ci(
            confidence_level=0.95, method="wilson"
        )
        result["ic95_sla_wilson"] = [float(interval.low), float(interval.high)]
    else:
        result["ic95_sla_wilson"] = None
    return result


def compare_dart_summary(path: Path, reference: dict) -> dict | None:
    if path.suffix.lower() != ".json":
        return None
    summary = json.loads(path.read_text(encoding="utf-8")).get("summary")
    if not isinstance(summary, dict):
        return None
    fields = {
        "n_total": "solicitudes",
        "n_valid": "latencias_validas",
        "n_failed": "fallidas_o_sin_latencia",
        "mean_latency_ms": "media_ms",
        "median_latency_ms": "mediana_ms",
        "sample_sd_ms": "desviacion_muestral_ms",
        "p95_latency_ms": ("percentiles_ms", "95"),
        "sla_probability": "proporcion_sla",
    }
    differences = {}
    for dart_key, python_key in fields.items():
        expected = (
            reference[python_key]
            if isinstance(python_key, str)
            else reference[python_key[0]][python_key[1]]
        )
        observed = summary.get(dart_key)
        if expected is None or observed is None:
            match = expected is None and observed is None
            error = None
        else:
            error = abs(float(observed) - float(expected))
            match = math.isclose(float(observed), float(expected), rel_tol=1e-8, abs_tol=1e-9)
        differences[dart_key] = {
            "dart": observed,
            "python": expected,
            "error_absoluto": error,
            "coincide": match,
        }
    return {
        "coinciden_todos": all(v["coincide"] for v in differences.values()),
        "campos": differences,
    }


def original_design_probabilities(frame: pd.DataFrame) -> dict:
    design = frame.loc[frame["id_escenario"].isin([f"E{i}" for i in range(1, 7)])]
    if design.empty:
        return {"disponible": False, "motivo": "No hay escenarios E1–E6"}
    lag = (design["latencia_ms"] > 50) & design["success"]
    multi = design["id_escenario"].isin(["E4", "E5", "E6"])
    critical = (~design["success"]) | (design["latencia_ms"] > 100)
    distance = design["id_escenario"].map(
        {"E1": "corta", "E4": "corta", "E2": "media", "E5": "media", "E3": "larga", "E6": "larga"}
    )
    denominator = int(critical.sum())
    return {
        "disponible": True,
        "n": len(design),
        "p_lag": float(lag.mean()),
        "p_multicliente": float(multi.mean()),
        "p_lag_y_multicliente": float((lag & multi).mean()),
        "p_lag_dado_multicliente": float(lag[multi].mean()) if multi.any() else None,
        "p_multicliente_dado_lag": float(multi[lag].mean()) if lag.any() else None,
        "p_critica": float(critical.mean()),
        "p_distancia_larga_dado_critica": (
            float(((distance == "larga") & critical).sum() / denominator)
            if denominator
            else None
        ),
        "prior_distancia": {
            band: float((distance == band).mean())
            for band in ("corta", "media", "larga")
        },
        "advertencia": (
            "Las probabilidades son descriptivas; las mediciones repetidas por "
            "dispositivo o ensayo no son observaciones independientes."
        ),
    }


def make_plots(frame: pd.DataFrame, directory: Path) -> list[str]:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    directory.mkdir(parents=True, exist_ok=True)
    outputs = []
    valid = frame.loc[frame["success"] & frame["latencia_ms"].notna()]
    if not valid.empty:
        fig, ax = plt.subplots(figsize=(8, 4.5))
        for scenario, group in valid.groupby("id_escenario", sort=True):
            ax.hist(group["latencia_ms"], bins=12, alpha=0.45, label=str(scenario))
        ax.set(xlabel="Latencia de aplicación (ms)", ylabel="Frecuencia")
        ax.legend()
        fig.tight_layout()
        path = directory / "histograma_latencia.png"
        fig.savefig(path, dpi=160)
        plt.close(fig)
        outputs.append(str(path))

        fig, ax = plt.subplots(figsize=(8, 4.5))
        groups = list(valid.groupby("id_escenario", sort=True))
        ax.boxplot([g["latencia_ms"].to_numpy() for _, g in groups],
                   tick_labels=[str(name) for name, _ in groups])
        ax.set(xlabel="Escenario", ylabel="Latencia de aplicación (ms)")
        fig.tight_layout()
        path = directory / "cajas_latencia.png"
        fig.savefig(path, dpi=160)
        plt.close(fig)
        outputs.append(str(path))

    if "tipo_anomalia" in frame:
        counts = frame["tipo_anomalia"].dropna().value_counts()
        if not counts.empty:
            fig, left = plt.subplots(figsize=(8, 4.5))
            left.bar(counts.index.astype(str), counts.to_numpy())
            left.set_ylabel("Eventos")
            right = left.twinx()
            right.plot(counts.index.astype(str),
                       counts.cumsum().to_numpy() / counts.sum() * 100,
                       marker="o", color="#427aa1")
            right.axhline(80, linestyle="--", color="#d05c67")
            right.set_ylim(0, 105)
            right.set_ylabel("Porcentaje acumulado")
            fig.tight_layout()
            path = directory / "pareto_anomalias.png"
            fig.savefig(path, dpi=160)
            plt.close(fig)
            outputs.append(str(path))
    return outputs


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="Exportación LANXIS .json o .csv")
    parser.add_argument("--output", type=Path, help="Ruta del informe JSON")
    parser.add_argument("--plots", type=Path, help="Directorio para gráficos PNG")
    args = parser.parse_args()
    frame = load_measurements(args.input)
    report = {
        "entrada": str(args.input),
        "sha256_entrada": hashlib.sha256(args.input.read_bytes()).hexdigest(),
        "versiones": {"numpy": np.__version__, "pandas": pd.__version__, "scipy": scipy.__version__},
        "definiciones": {
            "latencia": "RTT de aplicación medido por LANXIS; solo solicitudes exitosas",
            "varianza": "Muestral, denominador n−1",
            "lag": "Latencia > 50 ms",
            "critica": "Solicitud fallida o latencia > 100 ms",
            "warmup": "Excluido si la exportación incluye la columna warmup",
        },
        "global": summarize(frame),
        "escenarios": {
            str(name): summarize(group)
            for name, group in frame.groupby("id_escenario", sort=True)
        },
        "diseno_original": original_design_probabilities(frame),
    }
    comparison = compare_dart_summary(args.input, report["global"])
    if comparison is not None:
        report["dart_vs_python"] = comparison
    if args.plots:
        report["graficas"] = make_plots(frame, args.plots)
    rendered = json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered + "\n", encoding="utf-8")
    else:
        print(rendered)
    if comparison is not None and not comparison["coinciden_todos"]:
        raise SystemExit("El resumen Dart no coincide con NumPy/SciPy")


if __name__ == "__main__":
    main()
