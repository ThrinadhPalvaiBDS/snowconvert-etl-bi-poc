{% macro drop_ci_schemas(prefix) %}
  {% set q %}
    select schema_name from {{ target.database }}.information_schema.schemata
    where schema_name ilike '{{ prefix }}%'
  {% endset %}
  {% for row in run_query(q) %}
    {% do run_query('drop schema if exists ' ~ target.database ~ '.' ~ row[0] ~ ' cascade') %}
    {% do log('dropped ' ~ row[0], info=True) %}
  {% endfor %}
{% endmacro %}
