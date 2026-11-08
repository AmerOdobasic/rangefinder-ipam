-- 06_queries.sql  
-- Owners: Amer and Marc
-- This includes the demo and verification file (excluded from build_all.sql)
USE rangefinder;

/*
  Notes if you are running this script:
  - Dont run this top-to-bottom with 'source'. A lot of the test tests will intentionally trigger errors 
  like the prefix bounds, duplicates, overlap guards so MySQL will stop at the first failure
  - Run tests block-by-block, or run the whole file with --force:
  mysql -u <user> -p --force rangefinder < 06_queries.sql or SOURCE sql/06_queries.sql; if running in the MySQL terminal
  - If a run stops midway, the trailing DELETE cleanups won't run. If the test data 
  gets stuck behind, just rerun build_all.sql to reset the database
*/

-- This section covers some analytical queries

-- Query 1: Subnets above 80% IP address utilization
SELECT 
    s.subnet_id, s.cidr_block,
    COUNT(ip.ip_id) AS total_ips,
    SUM(CASE WHEN ip.status = 'assigned' THEN 1 ELSE 0 END) AS assigned_ips,
    ROUND((SUM(CASE WHEN ip.status = 'assigned' THEN 1 ELSE 0 END) / COUNT(ip.ip_id)) * 100, 2) AS utilization_pct
FROM Subnet s
JOIN IP_Address ip ON s.subnet_id = ip.subnet_id
GROUP BY s.subnet_id, s.cidr_block
HAVING utilization_pct > 80.00
ORDER BY utilization_pct DESC;

-- Query 2: Devices without an assigned IP address
SELECT 
    d.device_id, d.hostname, d.mac_address, d.device_type
FROM Device d
LEFT JOIN IP_Address ip ON d.device_id = ip.device_id
WHERE ip.ip_id IS NULL
ORDER BY d.device_id ASC;

-- Query 3: Racks with the least amount of free space remaining
SELECT 
    r.rack_id, r.rack_label, l.building, l.room, r.total_units,
    COALESCE(SUM(d.rack_units), 0) AS used_units,
    (r.total_units - COALESCE(SUM(d.rack_units), 0)) AS free_units
FROM Rack r
JOIN Location l ON r.location_id = l.location_id
LEFT JOIN Device d ON r.rack_id = d.rack_id
GROUP BY r.rack_id, r.rack_label, l.building, l.room, r.total_units
ORDER BY free_units ASC, r.rack_id ASC;

-- Query 4: the total assigned IP addresses per VLAN
SELECT 
    v.vlan_id, v.vlan_name,
    COUNT(ip.ip_id) AS assigned_ip_count
FROM VLAN v
JOIN Subnet s ON v.vlan_id = s.vlan_id
JOIN IP_Address ip ON s.subnet_id = ip.subnet_id
WHERE ip.status = 'assigned'
GROUP BY v.vlan_id, v.vlan_name
ORDER BY assigned_ip_count DESC;

-- Query 5: Total devices located in each physical location
SELECT 
    l.location_id, l.building, l.room,
    COUNT(d.device_id) AS device_count
FROM Location l
LEFT JOIN Rack r ON l.location_id = r.location_id
LEFT JOIN Device d ON r.rack_id = d.rack_id
GROUP BY l.location_id, l.building, l.room
ORDER BY device_count DESC, l.location_id ASC;

-- Query 6: Next available IP address per subnet (the lowest numeric IP is marked 'available')
SELECT 
    s.subnet_id, s.cidr_block,
    INET_NTOA(MIN(INET_ATON(ip.ip_address))) AS next_available_ip
FROM Subnet s
JOIN IP_Address ip ON s.subnet_id = ip.subnet_id
WHERE ip.status = 'available'
GROUP BY s.subnet_id, s.cidr_block
ORDER BY s.subnet_id ASC;

-- This section is about stored procedure lists (sp_generate_ips)
-- Note that sp_generate_ips issues an internal START TRANSACTION and COMMIT.
-- This means that transactions cannot be rolled back externally, so explicit DELETEs need to be used

-- First set up the shared parent fixtures for procedure tests
INSERT INTO Location (location_id, building, room) VALUES (970, 'Proc Test Hall', 'Room 970');
INSERT INTO VLAN (vlan_id, vlan_name) VALUES (970, 'Proc Test VLAN 970');


-- Test P1 looks at the standard /24 subnet generation
-- We expect the total_ips_created = 256, usable_ips = 254; 2 reserved, 254 available
INSERT INTO Subnet (subnet_id, cidr_block, vlan_id, location_id) VALUES (971, '10.98.0.0/24', 970, 970);
CALL sp_generate_ips(971);
SELECT status, COUNT(*) AS count FROM IP_Address WHERE subnet_id = 971 GROUP BY status;
DELETE FROM Subnet WHERE subnet_id = 971;


-- Test P2 is about Massive prefix rejection (for /8)
-- We expect ERROR 1644 (45000): sp_generate_ips: prefix length must be between /16 and /30.
-- and 0 IP rows to be created
INSERT INTO Subnet (subnet_id, cidr_block, vlan_id, location_id) VALUES (972, '11.0.0.0/8', 970, 970);
CALL sp_generate_ips(972);
SELECT COUNT(*) AS count_should_be_zero FROM IP_Address WHERE subnet_id = 972;
DELETE FROM Subnet WHERE subnet_id = 972;


-- Test P3 is for special point-to-point /31 and host /32 prefix to be rejected
-- Expected: ERROR 1644 (45000): sp_generate_ips: prefix length must be between /16 and /30.
INSERT INTO Subnet (subnet_id, cidr_block, vlan_id, location_id) VALUES 
  (973, '10.98.1.0/31', 970, 970),
  (974, '10.98.1.2/32', 970, 970);
CALL sp_generate_ips(973);
CALL sp_generate_ips(974);
SELECT COUNT(*) AS count_should_be_zero FROM IP_Address WHERE subnet_id IN (973, 974);
DELETE FROM Subnet WHERE subnet_id IN (973, 974);


-- Test P4 looks at the Upper boundary limit (for /30)
-- Expected: total_ips_created = 4, usable_ips = 2; .0 reserved, .1 to .2 to be available, and .3 to be reserved
INSERT INTO Subnet (subnet_id, cidr_block, vlan_id, location_id) VALUES (975, '10.98.3.0/30', 970, 970);
CALL sp_generate_ips(975);
SELECT ip_address, status FROM IP_Address WHERE subnet_id = 975 ORDER BY INET_ATON(ip_address) ASC;
DELETE FROM Subnet WHERE subnet_id = 975;


-- Test P5 looks at the Lower boundary limit (so /16 allowed is allowed while /15 is rejected)
-- Expected for /15 is that ERROR 1644 (45000): sp_generate_ips: prefix length must be between /16 and /30.
-- Expected for /16 is that total_ips_created = 65536, usable_ips = 65534; available = 65534, reserved = 2
INSERT INTO Subnet (subnet_id, cidr_block, vlan_id, location_id) VALUES 
  (976, '10.14.0.0/15', 970, 970),
  (977, '10.16.0.0/16', 970, 970);
CALL sp_generate_ips(976);
CALL sp_generate_ips(977);
SELECT status, COUNT(*) AS count FROM IP_Address WHERE subnet_id = 977 GROUP BY status;
DELETE FROM Subnet WHERE subnet_id IN (976, 977);


-- Test P6 is for the Duplicate generation guard
-- Expected 1st call: Success (8 total IP's and 6 usable)
-- Expected 2nd call: ERROR 1644 (45000): sp_generate_ips: IP addresses were already generated for this subnet.
-- For some verification, the total count remains exactly 8 (there isnt any orphan or duplicated rows left behind)
INSERT INTO Subnet (subnet_id, cidr_block, vlan_id, location_id) VALUES (978, '10.98.2.0/29', 970, 970);
CALL sp_generate_ips(978);
CALL sp_generate_ips(978);
SELECT COUNT(*) AS intact_row_count FROM IP_Address WHERE subnet_id = 978;
DELETE FROM Subnet WHERE subnet_id = 978;


-- Test P7 is the nonexistent subnet ID lookup
-- Expected: ERROR 1644 (45000): sp_generate_ips: subnet_id does not exist.
CALL sp_generate_ips(999999);


-- Get rid of the shared procedure parent fixtures
DELETE FROM VLAN WHERE vlan_id = 970;
DELETE FROM Location WHERE location_id = 970;

-- This section is about the trigger tests

-- Test T1A is the Subnet delete guard (trg_subnet_delete_guard) with assigned IPs
START TRANSACTION;
INSERT INTO Location (location_id, building, room) VALUES (901, 'Test Hall', 'Room 101');
INSERT INTO VLAN (vlan_id, vlan_name) VALUES (901, 'Test VLAN 901');
INSERT INTO Device (device_id, hostname, mac_address, device_type) 
VALUES (901, 'test-host.local', '00:11:22:33:44:01', 'Server');
INSERT INTO Subnet (subnet_id, cidr_block, vlan_id, location_id) 
VALUES (901, '192.168.100.0/24', 901, 901);
INSERT INTO IP_Address (subnet_id, ip_address, status, device_id) 
VALUES (901, '192.168.100.10', 'assigned', 901);

-- We want ERROR 1644 (45000): Cannot delete subnet! Its assigned IP addresses still exist...
DELETE FROM Subnet WHERE subnet_id = 901;
ROLLBACK;


-- Test T1B is that the subnet delete guard is allowed when no assigned IPs exist...
START TRANSACTION;
INSERT INTO Location (location_id, building, room) VALUES (901, 'Test Hall', 'Room 101');
INSERT INTO VLAN (vlan_id, vlan_name) VALUES (901, 'Test VLAN 901');
INSERT INTO Subnet (subnet_id, cidr_block, vlan_id, location_id) VALUES (901, '192.168.100.0/24', 901, 901);
INSERT INTO IP_Address (subnet_id, ip_address, status, device_id) VALUES (901, '192.168.100.10', 'available', NULL);

-- Expected: Subnet and associated available IP will delete cleanly
DELETE FROM Subnet WHERE subnet_id = 901;
SELECT COUNT(*) AS remaining_subnets FROM Subnet WHERE subnet_id = 901;
SELECT COUNT(*) AS remaining_ips FROM IP_Address WHERE subnet_id = 901;
ROLLBACK;

START TRANSACTION;
-- Parent fixture tests:
INSERT INTO Location (location_id, building, room) VALUES (920, 'Test Hall', 'Room 920');
INSERT INTO VLAN (vlan_id, vlan_name) VALUES (920, 'VLAN 920'), (921, 'VLAN 921');

-- The base fixture subnets
INSERT INTO Subnet (subnet_id, cidr_block, vlan_id, location_id) VALUES
  (920, '10.50.0.0/16', 920, 920),
  (921, '172.16.1.0/24', 920, 920);

-- For test 2A, what happens if the Subnet is entirely inside an existing subnet 
-- Here we have 10.50.1.0/24 being inside 10.50.0.0/16
-- We expect an ERROR 1644: Subnet CIDR overlaps with an existing subnet range!
INSERT INTO Subnet (subnet_id, cidr_block, vlan_id, location_id) 
VALUES (922, '10.50.1.0/24', 920, 920);

-- Test 2B now is if we have a subnet enclosing an existing subnet
-- 172.16.0.0/16 encompasses 172.16.1.0/24
-- Expect an ERROR 1644: Subnet CIDR overlaps with an existing subnet range!
INSERT INTO Subnet (subnet_id, cidr_block, vlan_id, location_id) 
VALUES (923, '172.16.0.0/16', 920, 920);

-- Test 2C is if we have adjacent subnets (will pass)?
-- 172.16.2.0/24 begins right after 172.16.1.255...
INSERT INTO Subnet (subnet_id, cidr_block, vlan_id, location_id) 
VALUES (924, '172.16.2.0/24', 920, 920);

-- Test 2D is if the the host bits are set 
-- 10.60.0.5 cant be a /24 network address because host bit .5 (its non-zero)
-- We expect an ERROR 1644: The CIDR is invalid. All host bits are set...
INSERT INTO Subnet (subnet_id, cidr_block, vlan_id, location_id) 
VALUES (925, '10.60.0.5/24', 920, 920);

-- Test 2E: A badly typed IP format 
-- 999.1.1.1 is not a valid IPv4 address; INET_ATON will return NULL here
-- Expect to get an ERROR 1644: Wrong IPv4 address format in the CIDR block...
INSERT INTO Subnet (subnet_id, cidr_block, vlan_id, location_id) 
VALUES (926, '999.1.1.1/24', 920, 920);

-- Test 2F; Update to the same CIDR or non-CIDR column (this should pass)
-- We have to make sure here not to trigger a false-positive self-overlap collision...
UPDATE Subnet SET vlan_id = 921 WHERE subnet_id = 924;

-- 2G test will cover if an update will expand into an existing subnet 
-- If we expand 924 from 172.16.2.0/24 to 172.16.0.0/22, it will collide with 172.16.1.0/24
-- Expect: ERROR 1644: Subnet CIDR overlaps with an existing subnet range!
UPDATE Subnet SET cidr_block = '172.16.0.0/22' WHERE subnet_id = 924;

ROLLBACK;

-- Test 3: We need to be sure that deleting a device releases its assigned IPs

START TRANSACTION;
INSERT INTO Location (location_id, building, room) VALUES (930, 'Test Hall', 'Room 930');
INSERT INTO VLAN (vlan_id, vlan_name) VALUES (930, 'VLAN 930');
INSERT INTO Device (device_id, hostname, mac_address, device_type) 
VALUES (930, 'server-del.local', '00:11:22:33:44:30', 'Server');
INSERT INTO Subnet (subnet_id, cidr_block, vlan_id, location_id) 
VALUES (930, '10.70.0.0/24', 930, 930);

-- We need to assign TWO IP addresses to the same device:
INSERT INTO IP_Address (subnet_id, ip_address, status, device_id) VALUES 
  (930, '10.70.0.10', 'assigned', 930),
  (930, '10.70.0.11', 'assigned', 930);

-- Delete the device
DELETE FROM Device WHERE device_id = 930;

-- Lets confirm that both rows must now have status = 'available' and device_id IS NULL
SELECT ip_address, status, device_id 
FROM IP_Address 
WHERE ip_address IN ('10.70.0.10', '10.70.0.11');

ROLLBACK;

-- Test 4 - We need to prevent the direct reassignment of an assigned IP (the trg_ip_update_check trigger)

START TRANSACTION;
INSERT INTO Location (location_id, building, room) VALUES (940, 'Test Hall', 'Room 940');
INSERT INTO VLAN (vlan_id, vlan_name) VALUES (940, 'VLAN 940');
INSERT INTO Device (device_id, hostname, mac_address, device_type) VALUES
  (940, 'server-a.local', '00:11:22:33:44:40', 'Server'),
  (941, 'server-b.local', '00:11:22:33:44:41', 'Server');
INSERT INTO Subnet (subnet_id, cidr_block, vlan_id, location_id) 
VALUES (940, '10.80.0.0/24', 940, 940);

INSERT INTO IP_Address (subnet_id, ip_address, status, device_id) 
VALUES (940, '10.80.0.5', 'assigned', 940);

-- For the first test, 4A, lets direct the reassignment from Device 940 to 941 
-- We expect here an ERROR 1644: Cant reassign the IP since the address is already assigned to another device. Please release it first!
UPDATE IP_Address SET device_id = 941 WHERE ip_address = '10.80.0.5';

-- Test 4B is done in 2 steps: Release first, then assign (this will pass)
UPDATE IP_Address SET status = 'available', device_id = NULL WHERE ip_address = '10.80.0.5';
UPDATE IP_Address SET status = 'assigned', device_id = 941 WHERE ip_address = '10.80.0.5';

-- Verification...
SELECT ip_address, status, device_id FROM IP_Address WHERE ip_address = '10.80.0.5';

ROLLBACK;

-- For test 5, we show that moving a device across locations releases its IPs (the trg_device_move_release_ips trigger)
START TRANSACTION;
-- First setup two distinct locations
INSERT INTO Location (location_id, building, room) VALUES 
  (950, 'Building A', 'Server Room 1'),
  (951, 'Building B', 'Server Room 2');

INSERT INTO VLAN (vlan_id, vlan_name) VALUES (950, 'VLAN 950');

-- For our racks, 950 & 951 are in Location 950 and Rack 952 is in Location 951
INSERT INTO Rack (rack_id, location_id, rack_label) VALUES
  (950, 950, 'Rack-A1'), 
  (951, 950, 'Rack-A2'), 
  (952, 951, 'Rack-B1');

INSERT INTO Device (device_id, hostname, mac_address, device_type, rack_id)
VALUES (950, 'relocating-host.local', '00:11:22:33:44:50', 'Server', 950);

INSERT INTO Subnet (subnet_id, cidr_block, vlan_id, location_id) 
VALUES (950, '10.90.0.0/24', 950, 950);

INSERT INTO IP_Address (subnet_id, ip_address, status, device_id) 
VALUES (950, '10.90.0.5', 'assigned', 950);

-- For the first test, lets move within the SAME location (so from Rack 950 to Rack 951)
-- Expected is that the IP remains 'assigned' to Device 950
UPDATE Device SET rack_id = 951 WHERE device_id = 950;
SELECT ip_address, status, device_id FROM IP_Address WHERE ip_address = '10.90.0.5';

-- The second test is to un-rack device (going from Rack 951 to NULL)
-- Expect that the IP remains 'assigned' (unracking for maintenance does not remove its IP)
UPDATE Device SET rack_id = NULL WHERE device_id = 950;
SELECT ip_address, status, device_id FROM IP_Address WHERE ip_address = '10.90.0.5';

-- Re-attach to Rack 950 to test cross location move
UPDATE Device SET rack_id = 950 WHERE device_id = 950;

-- Third test is to move across DIFFERENT locations (Rack 950 in Location 950 to Rack 952 in Location 951)
-- We expect that the IP status changes to 'available' and the device_id becomes NULL
UPDATE Device SET rack_id = 952 WHERE device_id = 950;
SELECT ip_address, status, device_id FROM IP_Address WHERE ip_address = '10.90.0.5';

ROLLBACK;

-- TestT6: Looking at duplicate IP and invalid status/device combos..
START TRANSACTION;
INSERT INTO Location (location_id, building, room) VALUES (960, 'Test Hall', 'Room 960');
INSERT INTO VLAN (vlan_id, vlan_name) VALUES (960, 'VLAN 960');
INSERT INTO Device (device_id, hostname, mac_address, device_type) 
VALUES (960, 'combo-host.local', '00:11:22:33:44:60', 'Server');
INSERT INTO Subnet (subnet_id, cidr_block, vlan_id, location_id) 
VALUES (960, '10.99.0.0/24', 960, 960);

-- For test 6A, Assigned that has a NULL device_id 
-- Expect an ERROR 1644: Cant insert IP since status is assigned but device_id is NULL!
INSERT INTO IP_Address (subnet_id, ip_address, status, device_id) 
VALUES (960, '10.99.0.1', 'assigned', NULL);

-- Test 6B checks Available with device_id thats not null..
-- Expect: ERROR 1644: Cannot insert IP since status is available/reserved but device_id is set!
INSERT INTO IP_Address (subnet_id, ip_address, status, device_id) 
VALUES (960, '10.99.0.2', 'available', 960);

-- Test 6C, Reserved with non-NULL device_id 
-- Expect an ERROR 1644: Cannot insert IP since status is available/reserved but device_id is set!
INSERT INTO IP_Address (subnet_id, ip_address, status, device_id) 
VALUES (960, '10.99.0.3', 'reserved', 960);

-- Test 6D, a valid baseline insertion
INSERT INTO IP_Address (subnet_id, ip_address, status, device_id) 
VALUES (960, '10.99.0.4', 'available', NULL);

-- Test 6E, Update the IP to an invalid combo 
-- Expect an ERROR 1644: Cant update IP since status is available/reserved but device_id is set.
UPDATE IP_Address SET device_id = 960 WHERE ip_address = '10.99.0.4';

-- Last test, 6F, will duplicate the IP Address across the database (This will fail on unique key constraint not trigger)
-- Expect an ERROR 1062 (23000): Duplicate entry '10.99.0.4' for key 'ip_address.uq_ip'
INSERT INTO IP_Address (subnet_id, ip_address, status, device_id) 
VALUES (960, '10.99.0.4', 'available', NULL);

ROLLBACK;