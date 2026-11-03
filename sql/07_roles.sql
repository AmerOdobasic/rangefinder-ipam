-- 07_roles.sql 
-- Owner: Muhib
USE rangefinder;

-- What needs to be done here: CREATE ROLE for the 3 roles, then GRANT commands:
--  Network Administrator : needs full CRUD on all tables
--  Systems Engineer      : SELECT on all, INSERT/UPDATE on Device, EXECUTE on procedures, no DELETE on Subnet
--  Read-Only Auditor     : SELECT on the views only
-- Plus demo users mapped to each role (make sure to fake passwords only).
