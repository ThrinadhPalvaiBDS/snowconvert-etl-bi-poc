# Cutover runbook

## T-10 days: parallel run
- SSIS keeps loading SQL Server DW; Snowflake Task DAG runs daily on the same source.
- Daily: `make reconcile` and `make dax-parity`; track results in the readout sheet.
- Exit criteria: 5 consecutive green days (see `success_criteria.md`).

## T-2 days: readiness
- [ ] All P1/P2 EWIs closed or accepted (`ewi_backlog.csv`)
- [ ] Behaviour changes signed off by data owner (`ssis_to_dbt_mapping.md`)
- [ ] Power BI RLS roles verified with 2 test users per role on repointed models
- [ ] Refresh schedules recorded; WH_BI sized from `V_POWERBI_QUERY_PERF`
- [ ] Rollback artifacts present: original `.pbix` files + legacy dataset IDs

## T-0: cutover window
1. Disable SQL Agent job for `Load_SalesDW` (keep SQL Server DW read-only, do not drop).
2. Run final delta: `make ingest` then `EXECUTE TASK T_ROOT_SALES_DW;` and wait for `SUCCEEDED` in `AUDIT.PIPELINE_RUN`.
3. `make reconcile` — must be PASS/REVIEW only.
4. `make pbi-cutover` (publishes into production workspace with `CreateOrOverwrite`).
5. `make dax-parity -- --cutover-log <log>` — must be all PASS.
6. Re-apply refresh schedules and endorse the new semantic models; notify users.

## Rollback (≤ 30 min)
1. Re-import original `.pbix` files into the workspace (`CreateOrOverwrite`) — they still point at SQL Server.
2. Re-enable the SQL Agent job; run it once to catch up.
3. Suspend `T_ROOT_SALES_DW`. Snowflake objects are left in place for root-cause analysis.

## Hypercare (2 weeks)
- Monitor `V_PIPELINE_SLA`, `V_WAREHOUSE_COST`, `V_POWERBI_QUERY_PERF` daily.
- After sign-off: decommission SSIS package and SQL Server DW per retention policy.
