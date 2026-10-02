import json, os, platform, socket, time
from datetime import datetime, timezone

import numpy as np
import pandas as pd
import lightgbm as lgb
from sklearn.model_selection import train_test_split
from sklearn.metrics import (roc_auc_score, accuracy_score, f1_score,
                             precision_score, recall_score)

SEED = 42
DATA = "creditcard.csv"

# 1. Load data
t0 = time.perf_counter()
df = pd.read_csv(DATA)
data_load_seconds = time.perf_counter() - t0

X = df.drop(columns=["Class"])
y = df["Class"]

# 2. Split: 80% train_full / 20% test, then train_full -> 75% train / 25% val
#    => train 60% / val 20% / test 20%, all stratified to keep fraud ratio
X_train_full, X_test, y_train_full, y_test = train_test_split(
    X, y, test_size=0.20, stratify=y, random_state=SEED)
X_train, X_val, y_train, y_val = train_test_split(
    X_train_full, y_train_full, test_size=0.25, stratify=y_train_full,
    random_state=SEED)

# 3. Training (early stopping on validation, test is NOT used here)
# min_child_weight=1: with only 0.17% fraud, the default (1e-3) lets a leaf with a
# handful of fraud rows get a huge Newton-step value, so training diverges after
# the first tree (best_iteration=1). Requiring more hessian per leaf keeps it stable.
model = lgb.LGBMClassifier(
    n_estimators=1000, learning_rate=0.05, num_leaves=31, min_child_weight=1,
    metric="auc", random_state=SEED, n_jobs=-1, verbose=-1)
t0 = time.perf_counter()
model.fit(X_train, y_train,
          eval_set=[(X_val, y_val)], eval_metric="auc",
          callbacks=[lgb.early_stopping(50, verbose=False)])
training_seconds = time.perf_counter() - t0
best_iteration = int(model.best_iteration_ or model.n_estimators)

# 4. Evaluate on test: AUC uses probabilities, other metrics use labels (threshold 0.5)
proba = model.predict_proba(X_test)[:, 1]
pred = (proba >= 0.5).astype(int)
metrics = {
    "auc_roc": float(roc_auc_score(y_test, proba)),
    "accuracy": float(accuracy_score(y_test, pred)),
    "f1": float(f1_score(y_test, pred)),
    "precision": float(precision_score(y_test, pred, zero_division=0)),
    "recall": float(recall_score(y_test, pred)),
}

# 5a. Latency for 1 row: warm-up, then measure many runs
one_row = X_test.iloc[[0]]
for _ in range(10):
    model.predict_proba(one_row)
LAT_RUNS = 200
lat = []
for _ in range(LAT_RUNS):
    t0 = time.perf_counter()
    model.predict_proba(one_row)
    lat.append((time.perf_counter() - t0) * 1000)

# 5b. Throughput for a batch of 1000 rows
batch = X_test.iloc[:1000]
model.predict_proba(batch)  # warm-up
TP_RUNS = 20
tp_times = []
for _ in range(TP_RUNS):
    t0 = time.perf_counter()
    model.predict_proba(batch)
    tp_times.append(time.perf_counter() - t0)
batch_seconds = float(np.median(tp_times))

result = {
    "timestamp_utc": datetime.now(timezone.utc).isoformat(),
    "host": socket.gethostname(),
    "cpu_count": os.cpu_count(),
    "python": platform.python_version(),
    "lightgbm": lgb.__version__,
    "dataset_shape": list(df.shape),
    "split": {"train": len(X_train), "val": len(X_val), "test": len(X_test),
              "method": "stratified 60/20/20"},
    "seed": SEED,
    "params": {"n_estimators": 1000, "learning_rate": 0.05, "num_leaves": 31,
               "min_child_weight": 1, "early_stopping_rounds": 50},
    "data_load_seconds": round(data_load_seconds, 4),
    "training_seconds": round(training_seconds, 4),
    "best_iteration": best_iteration,
    **{k: round(v, 6) for k, v in metrics.items()},
    "threshold": 0.5,
    "latency_1_row_ms": round(float(np.median(lat)), 4),
    "latency_1_row_ms_mean": round(float(np.mean(lat)), 4),
    "latency_1_row_ms_p95": round(float(np.percentile(lat, 95)), 4),
    "latency_runs": LAT_RUNS,
    "throughput_1000_rows_seconds": round(batch_seconds, 6),
    "throughput_1000_rows_per_second": round(1000 / batch_seconds, 1),
    "throughput_runs": TP_RUNS,
}

with open("benchmark_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("=== LightGBM Credit Card Fraud Benchmark ===")
for k, v in result.items():
    print(f"{k:34s}: {v}")
print("\nSaved -> benchmark_result.json")
