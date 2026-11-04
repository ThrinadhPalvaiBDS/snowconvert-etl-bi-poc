# Running SnowConvert AI for this POC

## 1. Input layout (give SnowConvert the *full* migration context)
```
snowconvert/input/
├── sql/        # SQL Server DDL: legacy/sqlserver/*.sql (+ procs, views, functions)
├── ssis/       # .dtsx packages (or extracted .ispac)
└── powerbi/    # .pbit templates exported from Power BI Desktop
```
Including the DW DDL together with the `.pbit` files lets the repointing step identify views and
match column casing to the migrated objects.

## 2. Project setup in the SnowConvert AI app
1. New project → Source platform **SQL Server**.
2. Point the code input at `snowconvert/input/sql`.
3. In the "Where is your SSIS/Power BI project(s)?" section add `snowconvert/input/ssis` and
   `snowconvert/input/powerbi`.
4. Run **Assessment** first; export the reports to `snowconvert/output/assessment/`.
5. Run **Conversion**; output goes to `snowconvert/output/conversion/`.

## 3. What you get back
| Output | Used for |
|---|---|
| Converted DDL / procs | Reference for `snowflake/01_raw_landing.sql` and the compat view contracts |
| One dbt project per SSIS Data Flow Task | Seed for `dbt/` refactoring (do not ship as-is — see below) |
| Orchestration SQL (TASKs / procedures with `EXECUTE DBT PROJECT`) | Seed for `snowflake/04_orchestration_tasks.sql` |
| `repointing_output/*.pbit` | Repointed reports for Phase 6 |
| `power_bi_sql_queries/` | Extracted + migrated embedded SQL — review each one |
| Issues / EWI / FDM reports | Triage backlog (`ewi_triage.py`) |

## 4. Replatform, don't lift
SnowConvert produces one dbt project per Data Flow Task, mirroring the SSIS component graph.
For an enterprise target we consolidate these into a single layered project:
* Merge per-dataflow projects into `dbt/` and reorganize models by layer (staging/intermediate/marts).
* Replace SSIS-style truncate-and-reload with `incremental` + `merge` and `snapshot` (SCD2).
* Replace Event Handlers (not converted) with the Task DAG finalizer + alerts.
* Reimplement For Loop iteration logic and non-file ForEach enumerators manually (EWI SSC-EWI-SSIS0004).
* Replace `<STAGE_PLACEHOLDER>` for File-enumerator loops with real stages (EWI SSC-EWI-SSIS0014).
* Failure/Completion precedence constraints need manual handling — only Success is fully converted.

## 5. EWI triage
```bash
python snowconvert/ewi_triage.py snowconvert/output/conversion --out snowconvert/output/ewi_backlog.csv
```
