# SnowConvert AI POC — SSIS → dbt Replatforming & Power BI Cutover

Enterprise-grade proof of concept that demonstrates two things end to end:

1. **ETL modernization** — legacy SSIS packages are *replatformed* (not lifted) into a layered
   dbt project that runs natively in Snowflake (dbt Projects on Snowflake), orchestrated by a
   Snowflake Task DAG that replaces SSIS control flow.
2. **BI cutover** — existing Power BI reports are *repointed* to Snowflake with SnowConvert AI's
   Power BI repointing (.pbit), published, rebound and validated with **no report rebuild**.

The key design decision that makes "no rebuild" work: dbt builds a clean modern model
(`STAGING → INTERMEDIATE → MARTS`), then a thin **compatibility layer** (`DBO` schema) exposes
views with the exact legacy table and column names the reports already use.

---

## No ACCOUNTADMIN?
If the admin granted a delegated `POC_ADMIN` role, use `poc_admin_mode/README_POC_ADMIN.md` (full layout).
See `restricted_mode/README_RESTRICTED.md`: the whole POC runs inside one existing schema with
your current roles, plus a short, tiered `ADMIN_REQUEST.sql` for what only an admin can grant.

## Repository layout

| Path | Purpose |
|---|---|
| `legacy/` | Sample legacy estate: SQL Server OLTP + DW DDL, SSIS package, Power BI M query |
| `snowconvert/` | SnowConvert AI input layout, run guide, EWI triage tooling |
| `snowflake/` | Account bootstrap, RBAC, landing, dbt project deployment, Task DAG, governance, observability, Power BI access |
| `ingestion/` | Watermark-based SQL Server → Snowflake RAW extractor (POC; Openflow/CDC for prod) |
| `dbt/` | Replatformed transformation logic (staging, intermediate, marts, snapshots, compat views, tests) |
| `powerbi/` | Power BI Service cutover automation (publish, parameters, credentials, refresh) + DAX parity tests |
| `validation/` | Data reconciliation SQL Server vs Snowflake |
| `.github/workflows/` | CI (slim dbt build on PR) and CD (deploy dbt project to Snowflake) |
| `docs/` | SSIS→dbt mapping, cutover runbook, success criteria |

---

## POC phases and steps

### Phase 0 — Scope & success criteria (Week 0)
1. Pick 1 representative SSIS solution (here: `Load_SalesDW.dtsx`) and 2–3 Power BI reports on top of it.
2. Agree measurable exit criteria — see `docs/success_criteria.md` (row/aggregate parity, DAX parity,
   SLA, cost per run, % auto-converted).

### Phase 1 — Snowflake foundation (Day 1–2)
3. Run `snowflake/00_account_bootstrap.sql` (roles, warehouses, databases, resource monitors).
4. Run `snowflake/01_raw_landing.sql` (RAW schema, file formats, stage, landing tables, audit columns).
5. Run `snowflake/05_governance.sql` and `snowflake/07_observability.sql` (`08_alerts.sql` runs after the first dbt build).

### Phase 2 — Assessment & conversion with SnowConvert AI (Day 2–4)
6. Lay out the inputs as in `snowconvert/README.md`: SQL Server DDL **plus** the `.dtsx` packages
   **plus** the `.pbit` reports in one project, so SnowConvert has the full migration context.
7. Run the assessment, review the readiness/EWI reports, then run conversion.
8. Triage EWIs/FDMs with `python snowconvert/ewi_triage.py <output_dir>`.

### Phase 3 — Replatform SSIS into dbt (Day 4–8)
9. Use the SnowConvert-generated dbt project as the starting point, then refactor into the
   layered project in `dbt/` (mapping in `docs/ssis_to_dbt_mapping.md`):
   * OLE DB Source → `sources.yml` + `stg_*`
   * Derived Column / Data Conversion → typed expressions in `stg_*`
   * Lookup → joins in `int_*`
   * Conditional Split → `int_order_lines_rejected` + filtered happy path
   * SCD Wizard → dbt `snapshot` (SCD2)
   * OLE DB Destination (fast load) → `incremental` model with `merge`
   * Control flow / Execute SQL / Send Mail → Snowflake Task DAG (`04_orchestration_tasks.sql`)
10. Add tests (`_stg_models.yml`, `_marts.yml`, `dbt/tests/`).
11. Build the `compat` layer so legacy object names resolve in Snowflake.

### Phase 4 — Data movement & orchestration (Day 6–9)
12. Load history and deltas with `ingestion/extract_sqlserver_to_snowflake.py`.
13. Deploy the dbt project to Snowflake: `snowflake/03_dbt_project_deploy.sql` (or the CD workflow).
14. Create and resume the Task DAG: `snowflake/04_orchestration_tasks.sql`.

### Phase 5 — Validation (Day 8–10)
15. `python validation/reconcile.py --config validation/reconciliation_config.yaml` — row counts,
    aggregates and key-level hash diff, SQL Server DW vs Snowflake compat views.

### Phase 6 — Power BI cutover (Day 9–12)
16. Open each repointed `.pbit` from SnowConvert's `repointing_output/`, supply Snowflake parameters,
    refresh, save as `.pbix`.
17. Run `snowflake/06_powerbi_access.sql` (BI role, service user, network policy).
18. `python powerbi/pbi_cutover.py --config powerbi/cutover_config.yaml` — publish, take over, set
    parameters, set credentials, refresh.
19. `python powerbi/dax_parity_test.py --config powerbi/cutover_config.yaml` — same DAX against
    legacy and repointed datasets, compare results.

### Phase 7 — Hypercare & readout (Day 12–15)
20. Follow `docs/cutover_runbook.md` (parallel run, go/no-go, rollback).
21. Present results against `docs/success_criteria.md`.

---

## Quick start

```bash
cp .env.example .env        # fill in values
make setup                  # python deps + dbt deps
make snowflake-bootstrap    # runs snowflake/*.sql via snow CLI
make ingest                 # land RAW data
make dbt-build              # build + test locally against DEV
make reconcile              # data parity
make pbi-cutover            # Power BI publish + rebind
make dax-parity             # report-level parity
```

## Prerequisites
* Snowflake account (Enterprise edition or higher for masking/row access policies) with ACCOUNTADMIN for bootstrap
* SnowConvert AI desktop app (free download from Snowflake)
* Python 3.10+, `snow` CLI, dbt-core ≥ 1.9 with dbt-snowflake
* SQL Server ODBC Driver 18
* Power BI Pro/PPU/Fabric workspace + Entra ID app registration (service principal allowed in tenant settings)
