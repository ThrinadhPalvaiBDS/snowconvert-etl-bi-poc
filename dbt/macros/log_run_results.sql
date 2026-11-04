{% macro log_run_results(results) %}
  {%- if execute and results | length > 0 -%}
    {%- if target.name == 'cortex' -%}
      {%- set audit_rel = target.database ~ '.' ~ target.schema ~ '.POC_DBT_RUN_RESULTS' -%}
    {%- elif target.name == 'prod' -%}
      {%- set audit_rel = 'SALES_DW_PROD.AUDIT.DBT_RUN_RESULTS' -%}
    {%- else -%}
      {%- set audit_rel = target.database ~ '.AUDIT.DBT_RUN_RESULTS' -%}
      {% do run_query('create schema if not exists ' ~ target.database ~ '.AUDIT') %}
    {%- endif -%}
    {%- if target.name != 'prod' -%}
      {% do run_query('create table if not exists ' ~ audit_rel ~ ' (invocation_id varchar, node_id varchar, resource_type varchar, status varchar, execution_time_s float, rows_affected number, message varchar, run_at timestamp_ltz)') %}
    {%- endif -%}
    {%- set rows = [] -%}
    {%- for r in results -%}
      {%- set rows_affected = r.adapter_response.get('rows_affected', 'null') if r.adapter_response else 'null' -%}
      {%- set msg = (r.message or '') | replace("'", "''") | truncate(1000) -%}
      {%- do rows.append("('" ~ invocation_id ~ "','" ~ r.node.unique_id ~ "','" ~ r.node.resource_type ~ "','"
            ~ r.status ~ "'," ~ (r.execution_time or 0) ~ "," ~ (rows_affected if rows_affected is not none else 'null')
            ~ ",'" ~ msg ~ "',current_timestamp())") -%}
    {%- endfor -%}
    insert into {{ audit_rel }} values {{ rows | join(',') }}
  {%- else -%}
    select 1
  {%- endif -%}
{% endmacro %}
