{# Standard lineage columns on every mart row (replaces SSIS LoadDate derived column) #}
{% macro audit_columns() -%}
    current_timestamp()::timestamp_ltz as _dbt_loaded_at,
    '{{ invocation_id }}'               as _dbt_invocation_id
{%- endmacro %}
