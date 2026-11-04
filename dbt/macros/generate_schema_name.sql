{#- prod: exact schema names (STAGING, MARTS, DBO ...) so Power BI sees stable names.
    dev/ci: prefix with the target schema to isolate each developer / PR.
    cortex (restricted mode): no CREATE SCHEMA privilege, so every model lands in the
    target schema (CORTEX_AI.DATA); model names already carry layer prefixes
    (stg_, int_, snap_, dim_, fct_) and compat views use legacy names. -#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if target.name == 'cortex' or custom_schema_name is none -%}
        {{ target.schema }}
    {%- elif target.name == 'prod' -%}
        {{ custom_schema_name | trim | upper }}
    {%- else -%}
        {{ target.schema | upper }}_{{ custom_schema_name | trim | upper }}
    {%- endif -%}
{%- endmacro %}
