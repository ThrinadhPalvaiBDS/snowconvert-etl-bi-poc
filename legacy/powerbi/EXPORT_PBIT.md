# Preparing Power BI reports for SnowConvert AI

1. Download each report (.pbix) from the Power BI Service or source control.
2. Open in Power BI Desktop → File → Export → **Power BI template (.pbit)**.
3. Save all `.pbit` files to `snowconvert/input/powerbi/`.
4. Record for every report: workspace, semantic model ID, report ID, owner, refresh schedule,
   RLS roles, gateway binding — fill `powerbi/cutover_config.yaml` from this inventory.
5. Keep the original `.pbix` files untouched: they are the rollback artifact.
