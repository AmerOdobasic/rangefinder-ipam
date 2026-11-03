-- This rebuilds the entire RangeFinder database. Run from the repo root:
--   mysql -u root -p < build_all.sql
-- 06_queries.sql is for demos and is not included on purpose

SOURCE sql/01_schema.sql;
SOURCE sql/02_triggers.sql;
SOURCE sql/03_procedures.sql;
SOURCE sql/04_views.sql;
SOURCE sql/05_seed.sql;
SOURCE sql/07_roles.sql;
