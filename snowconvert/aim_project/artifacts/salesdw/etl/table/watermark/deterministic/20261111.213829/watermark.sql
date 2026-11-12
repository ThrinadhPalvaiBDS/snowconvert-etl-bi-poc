USE DATABASE <%salesdw%>;

CREATE TABLE IF NOT EXISTS etl.Watermark (
    TableName NVARCHAR(50) NOT NULL PRIMARY KEY,
    LoadDate TIMESTAMP_NTZ(3) NOT NULL
)
COMMENT = '{ "origin": "sf_sc", "name": "snowconvert", "version": {  "major": 2,  "minor": 54,  "patch": "0-Pr" }, "attributes": {  "component": "transact",  "convertedOn": "11-11-2026",  "domain": "no-domain-provided",  "migrationid": "XsuhASpUt3+avDxmnPT2Mw==" }}'
;