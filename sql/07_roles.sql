
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


-- Create demo users with fake passwords
CREATE USER IF NOT EXISTS 'demo_admin'@'localhost'
IDENTIFIED BY 'FakeAdmin123!';

CREATE USER IF NOT EXISTS 'demo_engineer'@'localhost'
IDENTIFIED BY 'FakeEngineer123!';

CREATE USER IF NOT EXISTS 'demo_auditor'@'localhost'
IDENTIFIED BY 'FakeAuditor123!';

-- Assign roles to demo users
GRANT 'network_administrator'
TO 'demo_admin'@'localhost';

GRANT 'systems_engineer'
TO 'demo_engineer'@'localhost';

GRANT 'read_only_auditor'
TO 'demo_auditor'@'localhost';

-- Set default roles
SET DEFAULT ROLE 'network_administrator'
TO 'demo_admin'@'localhost';

SET DEFAULT ROLE 'systems_engineer'
TO 'demo_engineer'@'localhost';

SET DEFAULT ROLE 'read_only_auditor'
TO 'demo_auditor'@'localhost';
