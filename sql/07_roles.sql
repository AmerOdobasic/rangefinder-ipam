
-- 07_roles.sql
-- Owner: Muhib

USE rangefinder;

-- Create the three database roles
CREATE ROLE IF NOT EXISTS
    'network_administrator',
    'systems_engineer',
    'read_only_auditor';

-- Network Administrator: full CRUD access
GRANT SELECT, INSERT, UPDATE, DELETE
ON rangefinder.*
TO 'network_administrator';

-- Systems Engineer: SELECT on all tables
GRANT SELECT
ON rangefinder.*
TO 'systems_engineer';

-- Systems Engineer: INSERT and UPDATE on Device
GRANT INSERT, UPDATE
ON rangefinder.Device
TO 'systems_engineer';

-- Systems Engineer: execute stored procedures
GRANT EXECUTE
ON PROCEDURE rangefinder.sp_generate_ips
TO 'systems_engineer';
