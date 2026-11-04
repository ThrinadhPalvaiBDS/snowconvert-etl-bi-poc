# POC success criteria

| # | Criterion | Target | Evidence |
|---|---|---|---|
| 1 | SSIS objects auto-converted by SnowConvert AI | ≥ 80% of components, all EWIs triaged | SnowConvert assessment + `ewi_backlog.csv` |
| 2 | Data parity, row counts | 100% match (excluding signed-off behaviour changes) | `reconciliation_report.md` |
| 3 | Data parity, measures | Δ ≤ 0.01 on every total and slice | `reconciliation_report.md` |
| 4 | Report parity | 100% of DAX parity queries PASS | `dax_parity_test.py` output |
| 5 | Report rebuild effort | 0 visuals/measures changed | Power BI diff of report layout |
| 6 | Pipeline runtime | ≤ legacy SSIS runtime (baseline it first) | `V_PIPELINE_SLA` |
| 7 | Reliability | 5 consecutive green daily runs | `AUDIT.PIPELINE_RUN` |
| 8 | Cost | Credits/run within agreed budget | `V_WAREHOUSE_COST` |
| 9 | Engineering quality | 100% of marts tested & documented; CI on every PR | dbt docs, GitHub Actions |
| 10 | Governance | PII masked, least-privilege roles, BI on dedicated warehouse | `05_governance.sql`, `06_powerbi_access.sql` |
