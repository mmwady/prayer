"""Compare physical-device runs without uploading fixtures or predictions."""
import argparse
import json
import math
import statistics
from pathlib import Path


def timing(cases, key):
    values = sorted(float(c[key]) for c in cases)
    return {"mean_ms": statistics.mean(values), "median_ms": statistics.median(values),
            "p90_ms": values[math.ceil(len(values) * .9) - 1]}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    baseline = json.loads(args.baseline.read_text(encoding="utf-8-sig"))
    candidate = json.loads(args.candidate.read_text(encoding="utf-8-sig"))
    expected = {c["name"]: c for c in baseline["cases"]}
    actual = {c["name"]: c for c in candidate["cases"]}
    assert expected.keys() == actual.keys() and len(actual) >= 100
    assert baseline["model_version"] == candidate["model_version"]
    exact_predictions = exact_features = exact_previews = actions = recoveries = 0
    max_feature_error = max_probability_error = 0.0
    probability_means_valid = True
    for name, old in expected.items():
        new = actual[name]
        a, b = old["prediction"], new["prediction"]
        exact_predictions += a == b
        exact_features += old.get("features") == new.get("features")
        exact_previews += old.get("preview_sha256") == new.get("preview_sha256")
        actions += a.get("predicted_action") == b.get("predicted_action")
        recoveries += a["recovery_method"] == b["recovery_method"]
        models = b["individual_models"]
        assert len(models) == 3 and [m["seed"] for m in models] == ["2026", "3407", "8111"]
        if old.get("features") is not None and new.get("features") is not None:
            assert len(new["features"]) == 166 and new["features"][-1] == 1
            max_feature_error = max(max_feature_error, *(abs(x-y) for x,y in zip(old["features"], new["features"])))
        if b["pose_detected"]:
            probabilities = b["probabilities"]
            assert len(probabilities) == 8 and abs(sum(probabilities.values())-1) < 1e-5
            assert b["confidence"] == max(probabilities.values())
            assert probabilities[b["predicted_action"]] == b["confidence"]
            for action, probability in probabilities.items():
                mean = sum(m["probabilities"][action] for m in models)/3
                probability_means_valid &= abs(mean-probability) <= 1e-6
                if a["pose_detected"]:
                    max_probability_error = max(max_probability_error, abs(probability-a["probabilities"][action]))
            for model in models:
                assert model["confidence"] == max(model["probabilities"].values())
                assert model["probabilities"][model["predicted_action"]] == model["confidence"]
    old_time, new_time = timing(baseline["cases"], "total_ms"), timing(candidate["cases"], "total_ms")
    result = {"device": candidate["device"], "baseline": baseline["label"], "candidate": candidate["label"],
              "count": len(actual), "matching_actions": actions, "matching_recovery": recoveries,
              "exact_predictions": exact_predictions, "exact_features": exact_features,
              "exact_preview_hashes": exact_previews, "max_feature_error": max_feature_error,
              "max_probability_error": max_probability_error, "three_model_means_valid": probability_means_valid,
              "baseline_total": old_time, "candidate_prediction_path": new_time,
              "mean_prediction_path_reduction_percent": 100*(1-new_time["mean_ms"]/old_time["mean_ms"]),
              "candidate_preview": timing(candidate["cases"], "preview_ms"),
              "candidate_with_every_preview": timing([
                  {"total_ms": c["total_ms"] + c["preview_ms"]}
                  for c in candidate["cases"]], "total_ms"),
              "strict_quality_preserved": exact_predictions == exact_features == exact_previews == len(actual),
              "note": "Candidate deferred preview timing is separate; rendering retained evidence still costs time. Single-device sequential runs are affected by temperature and load."}
    args.output.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))
    assert probability_means_valid


if __name__ == "__main__":
    main()
