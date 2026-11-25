# Advanced Cloud AI Infrastructure — Work Report

**Date:** 2026-11-25
**Scope:** TD1, TD2, and Sessions 2–6 of the Terraform repo. Local fixes first, then the cloud
measurements and the release incident.
**Repositories:** `td1-scoring-albertschool`, `td2-fraud-api-albertschool`,
`ai-cloud-infra-terraform-student`.

---

## 1. Summary

| # | Task | Result |
| --- | --- | --- |
| 1 | TD1 step 2: client index | Golden scores unchanged; enrich flat in H; 10.1× at H = 500k |
| 2 | TD1 notebook: 6 s steps, re-run, restitution | Re-executed with the frozen shipped image and the corrected image; final ladder 50→300 req/s |
| 3 | TD2: imports and CI | 19 tests pass; commit `95e77e9` tracks `.github/workflows/deploy.yml` |
| 4 | Session 4 SQL | `customer_daily`, `terminal_daily`, `check.sql`; `check.sql` returns 0 / 0; customer 5 / 100.79 |
| 5 | Session 4 Terraform | `features.tf`, `vectors.tf`, four feature-source env vars |
| 6 | Session 2 | 50 `/predict` calls: client p50 25.9 / p99 137.8 ms; server p50 18.2 / p99 158.1 ms; startup 7.7–8.7 s |
| 7 | Session 3 | `/pubsub` deployed; 2 522 messages in 1 h; 100 test messages at 20 msg/s; dead-letter `42ab0a…` after 5 attempts |
| 8 | Session 4 sources | parquet 0.78/1.5 ms; BigQuery 244.7/414.2 ms; Firestore 17.7/128.7 ms; BQ and Firestore scores identical |
| 9 | Session 6 Terraform | `release.tf` alert on p95 latency; `scorer.tf` imported read-only; `plan.txt` 1 import / 0 change |
| 10 | Session 6 incident | `next-1125145911` (`FEATURE_READER=direct`) p95 648.1 ms vs candidate 2.3 ms, 3 client timeouts; rolled back; alert corrected |
| 11 | Session 6 report | `mesures.md`, `post-mortem.md`, `checklist.md` filled; shadow a posteriori, degraded allow/block, restore drill, retraining policy |
| 12 | Reports | Session 2, 3, 4 reports filled with measured values |
| 13 | Session 7 | Not started — new GPU/LLM lab |

---

## 2. Environment and constraints

- macOS, project `advanced-cloud-ai`, region `europe-west1`, team `team-really-cool`.
- `gcloud` authenticated as `maribi@albertschool.com`; ADC configured for BigQuery/Firestore.
- Docker Desktop started for the TD1 image and notebook.
- Port `8765` is held by an unrelated `python -m http.server`; TD1 uses `8766`, as the README suggests.
- The project `.venv` has stale console-script shebangs from an older folder path; `uv run python ...`
  works, `uv run jupyter` does not. The notebook was run with `python -m nbconvert`.
- The live `team-really-cool-fraud-api` was on the v1 image with no `/pubsub`; `tx_history` was empty.
  Both were fixed during this work (see §6 and §7).

---

## 3. TD1 — client index

### 3.1 Change

`features.py`:

```python
def client_index(history: pd.DataFrame) -> dict:
    key = (id(history), len(history))
    index = _INDEX_CACHE.get(key)
    if index is None:
        index = history.groupby("client_id", sort=False).indices
        _INDEX_CACHE[key] = index
    return index


def client_rows(history: pd.DataFrame, index: dict, cid: int) -> pd.DataFrame:
    positions = index.get(cid)
    if positions is None:
        return history.iloc[:0]
    return history.iloc[positions]
```

**Why:** `groupby(...).indices` returns integer positions, so `iloc[positions]` reads only the
client's rows instead of scanning all H rows for every aggregate. The cache is keyed by
`(id(history), len(history))` because the service loads one history at startup; the index is built
once and shared by every request in the worker. An unknown client returns `history.iloc[:0]`, so the
existing `NaN` behaviour of `client_aggregates` is preserved. The change is local: schema, row order
and score computation are untouched.

### 3.2 Verification

```bash
uv run bench.py --check-golden
```

```text
F=16: ids/ordre identiques, max|Δscore|=0.00e+00 -> OK
F=64: ids/ordre identiques, max|Δscore|=0.00e+00 -> OK
F=256: ids/ordre identiques, max|Δscore|=0.00e+00 -> OK
```

`ruff check features.py` passes.

### 3.3 Measurement

Notebook measurement, 100 transactions, index warm:

| H | Before | After | Gain |
| --- | --- | --- | --- |
| 50 000 | 1.466 ms/tx | 0.766 ms/tx | 1.9× |
| 150 000 | 3.834 ms/tx | 1.107 ms/tx | 3.5× |
| 500 000 | 10.336 ms/tx | 1.027 ms/tx | 10.1× |

A cold-cache run gives 1.5 ms/tx at 500k; the difference is the one-time index build (27 ms, 3.8 MB).
The important result is that enrich is now **flat in H**. At 50k the index is almost pure overhead —
about one row per client — which is expected.

---

## 4. TD1 — notebook re-run

### 4.1 What changed

- `URL` 8765 → 8766 (port conflict).
- `PALIERS` → `[(50,6),(100,6),(150,6),(200,6),(250,6),(300,6)]`.
- The final restitution cell was written with the measured conclusions.

The 6 s steps come from a probe: the corrected 1-worker/1-CPU replica meets the SLA up to 150 req/s
and breaks at 200 req/s. The ladder crosses the real plateau; 300 requests at 50 req/s and 1 800 at
300 req/s per step are enough to judge each level.

### 4.2 Preserving the "before" image

The notebook's first cell builds `td1-scoring` and tags it `livre`. With the fix already in the
working tree, that would have made the "shipped" baseline the corrected code. The original image
(ID `b721eb61d2b9`, 9 November) was still present as a dangling image, so it was re-tagged
`td1-scoring:livre`; the notebook now tags the corrected build `td1-scoring:corrected`, and `LIVRE`
still points to the original. Steps 0/1/3 therefore measure the shipped code, steps 2/4 the fix.

### 4.3 Final outputs

- Step 0: p50 15.89 ms, p95 20.80 ms; `enrich` 13.33 ms, `matrix` 0.57 ms, `predict` 0.19 ms.
- Step 1: 1.466 / 3.834 / 10.336 ms per transaction at 50k / 150k / 500k; ratio 7.1 vs predicted 10.
- Step 2: golden 0 diff; corrected 0.766 / 1.107 / 1.027 ms; gains 1.9× / 3.5× / 10.1×.
- Step 3: shipped 2 workers/2 CPU: 100 % success but p95 274.13 ms → SLA false.
- Step 4: corrected 1 worker/1 CPU:

| Debit (req/s) | p95 (ms) | SLA |
| --- | --- | --- |
| 50 | 18.4 | oui |
| 100 | 20.2 | oui |
| 150 | 47.5 | oui |
| 200 | 1 262.1 | non |
| 250 | 1 197.6 | non |
| 300 | 1 492.7 | non |

Capacité utile avec 30 % de marge : **105 req/s** → **3 réplicas** pour 300 req/s.

The notebook is assembled from the original baseline run (steps 0/1/3, image `livre`) and the
corrected run (steps 2/4). This is deliberate: the lab is interactive, and mixing the corrected code
into step 1 would have hidden the very defect the TD asks you to find. The restitution cell says so
implicitly; the file `notebooks/td1_experiences.ipynb` contains the final outputs.

---

## 5. TD2 — imports and CI

`app.py` had duplicate imports of FastAPI, Request, Response, Field and ValidationError, and
`base64`/`json` after the local imports. They were merged; no behaviour change.

```bash
uv run pytest -q          # 19 passed
git add app.py .github
git commit -m "chore: clean imports and track deploy workflow"   # 95e77e9
```

`.github/workflows/deploy.yml` is now tracked. It authenticates through Workload Identity Federation
as `team-really-cool-cd`, builds and pushes the commit-tagged image, then deploys a revision.

---

## 6. Session 2 — Cloud Run report

The service was measured on `ref-fraud-api:td4`, source `parquet`, revision
`team-really-cool-fraud-api-00006-qqf`: 50 authenticated `/predict` calls at 10/s.

| Mesure | Valeur |
| --- | --- |
| p50 / p99 client | 25.9 ms / 137.8 ms |
| p50 / p99 server | 18.2 ms / 158.1 ms (Cloud Monitoring, 10-min window) |
| `features_ms` p50 | 0.60 ms |
| `predict` p50 | 0.68 ms |
| handler p50 | 1.31 ms |
| Cold start | p50 7.7 s, p99 8.7 s |
| Instances at peak | 3 (max 3) |
| Reference score | 0.00010231 |

The live service had lost its 3-instance cap during the `gcloud` deploys (Cloud Run defaulted to
100); it was restored with `--max-instances 3`, confirmed by the annotation
`autoscaling.knative.dev/maxScale=3`. The report is `docs/rapport-seance-2.md`.

---

## 7. Session 3 — Pub/Sub

The service was still the v1 image with no `/pubsub` (404). The `td3` image already existed in
Artifact Registry, so it was deployed without a build:

```bash
gcloud run deploy team-really-cool-fraud-api \
  --image europe-west1-docker.pkg.dev/advanced-cloud-ai/cloud-ai/team-really-cool-fraud-api:td3 \
  --region europe-west1
```

`/pubsub` then returned **204** for a valid envelope and **422** for `TX_AMOUNT = -1`, with a
`rejected` log line. Results:

| Mesure | Valeur |
| --- | --- |
| Messages traités (1 h) | 2 522 |
| Test direct | 100 messages à 20 msg/s, tous 204 |
| p50 / p99 client `/pubsub` | 28.2 ms / 36.4 ms |
| Handler p50 | 1.3 ms |
| Backlog max / âge max | 1 749 messages / 3 662 s, pendant la période 404 |
| Instances au pic | 3 (max 3) |
| Dead-letter | `42ab0aa3c116f7ecd4538a5f727e879a5aeef181`, 18/11 22:15:39, 5 tentatives |
| Rejet de test | `local-neg`, 422, 1 tentative |

The backlog and age come from the 18–19 November 404 period: Pub/Sub accumulated messages while the
service had no `/pubsub`, then retried them. The dead-letter queue contains 10 messages, proof that
the failure path works. The `ff-replay` ramp was over, so the 20 msg/s test replaced it; the report
says so. `docs/seance-3/compte-rendu.md` is filled.

---

## 8. Session 4 — history and aggregates

`tx_history` was empty: the BigQuery subscription existed, but the teacher's replay had passed before
it was created. The local `data/replay.parquet` (301 003 rows, 1–3 October) was loaded into a
temporary table and the five business columns were inserted:

```bash
bq load --source_format=PARQUET --autodetect --location=europe-west1 \
  --replace team_really_cool.tx_replay_raw data/replay.parquet
bq query ... 'INSERT INTO team_really_cool.tx_history (TX_ID, TX_TS, CUSTOMER_ID, TERMINAL_ID, TX_AMOUNT)
              SELECT tx_id, tx_ts, customer_id, terminal_id, tx_amount FROM team_really_cool.tx_replay_raw'
```

This is a documented workaround: the table has no `message_id`/`publish_time`/`attributes`, and
`messages` is 0. Results:

| Mesure | Valeur |
| --- | --- |
| Lignes / `TX_ID` distincts | 301 003 / 301 003 |
| Doublons | 0 |
| Octets, filtre 1 jour (`2026-10-03`) | 5.0 MB |
| Octets, sans filtre | 12.6 MB |
| `check.sql` client / terminal | 0 / 0 |
| Client `7989449428740969`, 2026-10-01 | `n` = 5, `amount_sum` = 100.79 |

The one-day filter prunes partitions (5.0 vs 12.6 MB). The `2026-10-01` filter does not prune because
all loaded rows are after that date. `customer_daily` has 903 359 rows and 49 477 clients;
`terminal_daily` has 119 640. The SQL is in `infra/sql/` with a short README.

---

## 9. Session 4 — three feature sources

`features.tf` IAM was applied (dataset viewer, BigQuery job user, Firestore user), then the `td4`
image was deployed with each `FEATURE_SOURCE`. 400 messages for parquet, 100 for BigQuery, 100 for
Firestore, at 10–20 msg/s.

| Source | p50 `features_ms` | p99 `features_ms` | Reference score |
| --- | --- | --- | --- |
| parquet | 0.78 ms | 1.5 ms | 0.00010231 |
| bigquery | 244.74 ms | 414.23 ms | 0.000192687 |
| firestore | 17.74 ms | 128.66 ms | 0.000192687 |

The parquet score differs because its counters stop on 30 September; BigQuery and Firestore read
October and agree exactly. Firestore was populated with `publish_features.py`: 49 477 customers and
4 985 terminals. The report recommends Firestore for live scoring (≈14× faster than BigQuery) and
parquet as a fast but stale fallback. `docs/seance-4/compte-rendu.md` is filled.

The KYC/Qdrant part D was also run on 49 394 documents. `m = 4` tops out at 0.933 recall even with
`ef = 256`, so the cheapest setting meeting recall@10 ≥ 0.95 is **`m = 16`, `ef = 4`**: recall
0.992, p50 0.45 ms, p95 0.61 ms. The three clients who reused the bulletin of `0018478647296750`
are `3263319564977208`, `2947552228922773` and `0553287702820053`.

---

## 10. Session 6 — Terraform and import

- `infra/scorer/main.tf`: separate folder, local state, import block only, no apply/destroy.
- `infra/scorer/scorer.tf`: generated with `terraform plan -generate-config-out`, plus
  `lifecycle { prevent_destroy = true }`.
- `docs/seance-6/plan.txt`: `1 to import, 0 to add, 0 to change, 0 to destroy`, creator/last_modifier
  masked.
- The plan confirms the handout's warning: `template.revision` is
  `team-really-cool-scorer-next-1125145911` (latest created), while 100 % of traffic is on
  `team-really-cool-scorer-candidate-1119194145`. The first two lines of `plan.txt` record it.
- `infra/release.tf`: shadow subscription `count = shadow_tag == "" ? 0 : 1`; alert policy applied
  and enabled.

The alert was initially written for `td6_failed` (5 failures/min). The incident proved that wrong:
`next` returned 204 with a valid score and zero errors, only slower. The policy now watches
`run.googleapis.com/request_latencies`, p95, 50 ms, 60 s, grouped by revision. It is applied
(`team-really-cool-scorer-release`, enabled).

---

## 11. Session 6 — the incident

The teacher's command created `team-really-cool-scorer-next-1125145911` with
`FEATURE_READER=direct` (candidate uses `snapshot`). It was tagged `next`, given 10 % of traffic, and
exercised with 100 `/pubsub` calls at 10/s.

| Revision | n | p50 | p95 | Errors | Degraded |
| --- | --- | --- | --- | --- | --- |
| `candidate` | 68 | 1.8 ms | 2.3 ms | 0 % | 0 % |
| `next-1125145911` | 9 | 426.1 ms | 648.1 ms | 0 % (3 client timeouts) | 0 % |

- First `next` log: 14:01:00, `latency_ms` 681.99, `features_ms` 635.29.
- Detection: ~14:01:30 via `measure.py`; p95 648.1 ms vs 2.3 ms.
- Rollback: ~14:01:40, `candidate=100`; `next` tag removed.
- Last `next` log: 14:01:13; after rollback, candidate p95 2.3 ms.
- The 3 timeouts happened before the service logged anything (cold start of `next`); `measure.py`
  sees 0 % application errors, which is exactly why the `td6_failed` alert was wrong.

Cause: `FEATURE_READER=direct` queries BigQuery per transaction (635 ms of features) instead of
reading the precomputed snapshot (1.79 ms). The service is correct but slow; an error-based alert
would never see it. The post-mortem is `docs/seance-6/post-mortem.md`; the measures and the answers
are in `docs/seance-6/mesures.md`.

The readiness checklist is filled with the truth: **Validated** no (validation done, shadow not run),
**Reversible** yes, **Observed** yes, **Degradable** no, **Restorable** partial (Terraform import and
`plan.txt` done; data/model restore drill not run), **Owned** no (no retraining policy/owner).

---

## 12. Verification summary

| Check | Result |
| --- | --- |
| TD1 `bench.py --check-golden` | 3/3 widths identical, max Δ 0 |
| TD1 `ruff check features.py` | clean |
| TD2 `pytest -q` | 19 passed |
| Terraform `fmt` / `validate` | clean / success |
| Terraform plan (main slice) | 14 add, 1 change, 1 destroy (job + features + vectors + alert; old invoker) |
| `infra/scorer` plan | 1 import, 0 add/change/destroy |
| Session 4 `check.sql` | 0 / 0 |
| Session 4 reference customer | 5 / 100.79 |
| Session 6 rollback | candidate 100 %, p95 3.0 ms, no `next` logs |

---

## 13. Files changed or created

**TD1**
- `features.py` — index + rows; comment width.
- `notebooks/td1_experiences.ipynb` — URL 8766, 6 s steps, corrected image tag, final restitution.
- Commit `07b99d2`.

**TD2**
- `app.py` — merged imports.
- `.github/workflows/deploy.yml` — tracked.
- Commit `95e77e9`.

**Terraform**
- `infra/main.tf` — four feature-source env vars.
- `infra/features.tf`, `infra/vectors.tf` — new.
- `infra/release.tf` — shadow + latency alert.
- `infra/scorer/main.tf`, `infra/scorer/scorer.tf`, `infra/scorer/README.md` — read-only import.
- `infra/sql/customer_daily.sql`, `terminal_daily.sql`, `check.sql`, `README.md` — new.
- `docs/rapport-seance-2.md` — filled.
- `docs/seance-3/compte-rendu.md` — filled.
- `docs/seance-4/compte-rendu.md` — filled.
- `docs/seance-6/mesures.md`, `post-mortem.md`, `checklist.md` — filled.
- `docs/seance-6/plan.txt` — generated and masked.

**Root**
- `README.md` — this report.
- `COURSE-GUIDE.md`, `ACTION-PLAN.md` — course map and plan.

---

## 14. What remains

1. **Review the Terraform plan** before any apply. The Terraform changes are committed as
   `09acf12` (plus the docs notes `7890318` and `0e97a26`). The destroy is the old `ymeurou` invoker
   if `tfvars` lists only `maribi`; add both if it is a teammate.
2. **Session 6 shadow** is a technical shadow only: 20 messages on the `candidate` tag, 20 × 204,
   p50 1.7 / p95 1.9 ms. The pre-promotion champion/challenger comparison was not done, so the
   checklist line is **partiel**, not yes.
3. **Session 4D (KYC/Qdrant)** is done and the Qdrant service is already deleted; the KYC tables
   and the three clients are in `docs/seance-4/compte-rendu.md`.
4. **Degraded mode and retraining policy** are done: `allow` 100 % degraded / 0 % alerts, `block`
   100 % degraded / 100 % alerts, choice `allow`; policy in `docs/seance-6/retraining-policy.md`.
5. **Restore drill** is done: model artifact restored, feature tables time-travel restored
   (903 359 / 119 640 rows), decision log restored and cleaned up.
6. **Session 7** is new work: read `docs/seance-7.md` and follow the GPU/LLM lab. It is not a gap in
   the Session 2–6 hand-in.

## 15. Caveats

- The Session 4 history was loaded directly from `replay.parquet`, not through Pub/Sub; the
  `message_id`/`publish_time` columns are therefore empty. This is documented in the report.
- The Session 2 metrics were measured on the `td4`/parquet revision on 24 November, not on the
  original Session 2 date. The values are real and the protocol is the same.
- The Session 6 incident times are bracketed by logs; the exact split time (~14:00:50) is
  reconstructed from the first `next` log at 14:01:00.
- The `next` test used the same transaction 100 times, so `tx distinctes` is 1 and the alert rate is
  not representative; the p95 and errors are valid.
- The Terraform plan was run with `-refresh=false`; a refreshed plan may show drift on the live
  service, especially the image (ignored by `lifecycle`) and the invoker list.
