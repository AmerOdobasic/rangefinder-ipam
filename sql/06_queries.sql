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

EXPLAIN SELECT 
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

EXPLAIN SELECT 
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

EXPLAIN SELECT 
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

EXPLAIN SELECT 
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

EXPLAIN SELECT 
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

EXPLAIN SELECT 
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
-- 999.1.1.1 is not a valid IPv4 address
-- Expect to get an ERROR 1411 (HY000): Incorrect string value: 'v_new_net@0' for function inet_aton
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

-- 6F, will duplicate the IP Address across the database (This will fail on unique key constraint not trigger)
-- Expect an ERROR 1062 (23000): Duplicate entry '10.99.0.4' for key 'ip_address.uq_ip'
INSERT INTO IP_Address (subnet_id, ip_address, status, device_id) 
VALUES (960, '10.99.0.4', 'available', NULL);

-- The last test 6G will UPDATE the IP to assigned with NULL device id. (the trg_ip_update_check trigger handles this)
-- Expected to see ERROR 1644 (45000): Cant update IP because the status is assigned but device_id is NULL...
UPDATE IP_Address
SET status = 'assigned', device_id = NULL
WHERE ip_address = '10.99.0.4';

ROLLBACK;


-- First set up the shared parent fixtures for these tests (ids in the 990s)
-- Subnet 991 is a /29 (usable .1 to .6), 992 is a /28 (usable .1 to .14) and 993 is a /30 (usable .1 and .2 only)
INSERT INTO Location (location_id, building, room) VALUES (990, 'Proc Test Hall 2', 'Room 990');
INSERT INTO VLAN (vlan_id, vlan_name) VALUES (990, 'Proc Test VLAN 990');
INSERT INTO Rack (rack_id, location_id, rack_label, total_units) VALUES (990, 990, 'Proc-R01', 42);
INSERT INTO Subnet (subnet_id, cidr_block, vlan_id, location_id) VALUES
    (991, '10.97.0.0/29', 990, 990),
    (992, '10.97.1.0/28', 990, 990),
    (993, '10.97.2.0/30', 990, 990);
CALL sp_generate_ips(991);
CALL sp_generate_ips(992);
CALL sp_generate_ips(993);


-- Test R1 looks at a new device getting created and receiving the lowest free IP
-- We expect assigned_ip = 10.97.0.1 and a new device_id
CALL sp_request_static_ip(991, 'proc-dev1', '02:00:00:00:99:01', 'Server', 990, 2);
-- Verification: there should be one new Device row (rack_id = 990 and rack_units = 2)
SELECT device_id, hostname, device_type, rack_units, rack_id FROM Device WHERE mac_address = '02:00:00:00:99:01';


-- Test R2 is the next device that will be getting the next IP
-- We expect assigned_ip = 10.97.0.2
CALL sp_request_static_ip(991, 'proc-dev2', '02:00:00:00:99:02', 'Server', 990, 4);


-- Test R3 looks at the next IP being picked numerically instead of as text
-- As text 10.97.1.10 would sort before 10.97.1.2, so a text sort would give .10 for the second device
-- We expect the first call to give 10.97.1.1 and the second call to give 10.97.1.2
CALL sp_request_static_ip(992, 'proc-dev11', '02:00:00:00:99:11', 'Server', NULL, NULL);
CALL sp_request_static_ip(992, 'proc-dev12', '02:00:00:00:99:12', 'Server', NULL, NULL);


-- Test R4 is a full subnet being rejected (subnet 993 only has 2 usable IPs)
-- We expect the 1st and 2nd call to give 10.97.2.1 and 10.97.2.2
-- We want ERROR 1644 (45000): sp_request_static_ip: no available IP addresses left in this subnet. for the 3rd call
CALL sp_request_static_ip(993, 'proc-dev21', '02:00:00:00:99:21', 'Server', NULL, NULL);
CALL sp_request_static_ip(993, 'proc-dev22', '02:00:00:00:99:22', 'Server', NULL, NULL);
CALL sp_request_static_ip(993, 'proc-dev23', '02:00:00:00:99:23', 'Server', NULL, NULL);
-- Verification: orphan_devices should be 0 (the rollback also removed the new Device row)
SELECT COUNT(*) AS orphan_devices FROM Device WHERE mac_address = '02:00:00:00:99:23';


-- Test R5A is a duplicate MAC address being inserted directly into Device
-- We want ERROR 1062 (23000): Duplicate entry '02:00:00:00:99:01' for key 'device.uq_device_mac' (the unique key rejects it)
INSERT INTO Device (hostname, mac_address, device_type) VALUES ('proc-dev1-copy', '02:00:00:00:99:01', 'Server');
-- Verification: device_rows should still be 1
SELECT COUNT(*) AS device_rows FROM Device WHERE mac_address = '02:00:00:00:99:01';


-- Test R5B is the same MAC address going through the procedure instead
-- The procedure does not reject a known MAC, it reuses the existing device and gives it another IP
-- We expect assigned_ip = 10.97.0.3 and the same device_id as proc-dev1 (no error and no second Device row)
CALL sp_request_static_ip(991, 'proc-dev1-again', '02:00:00:00:99:01', 'Server', 990, 2);
-- Verification: one row, the hostname is still proc-dev1 (not renamed) and ips = 10.97.0.1,10.97.0.3
SELECT d.device_id, d.hostname,
       GROUP_CONCAT(ip.ip_address ORDER BY INET_ATON(ip.ip_address)) AS ips
FROM Device d
JOIN IP_Address ip ON ip.device_id = d.device_id
WHERE d.mac_address = '02:00:00:00:99:01'
GROUP BY d.device_id, d.hostname;


-- Test R6 is the nonexistent subnet ID lookup
-- We want ERROR 1644 (45000): sp_request_static_ip: subnet_id does not exist.
CALL sp_request_static_ip(999999, 'proc-ghost', '02:00:00:00:99:31', 'Server', NULL, NULL);
-- Verification: orphan_devices should be 0
SELECT COUNT(*) AS orphan_devices FROM Device WHERE mac_address = '02:00:00:00:99:31';


-- Test R7 looks at a bad rack_id failing without assigning anything
--  We want ERROR 1452 (23000): Cannot add or update a child row: a foreign key constraint fails
-- (`rangefinder`.`device`, CONSTRAINT `fk_device_rack` FOREIGN KEY (`rack_id`) REFERENCES `rack` (`rack_id`) ON DELETE SET NULL ON UPDATE CASCADE)
CALL sp_request_static_ip(991, 'proc-badrack', '02:00:00:00:99:32', 'Server', 999999, 2);
-- Verification: orphan_devices should be 0 and assigned_in_991 should stay 3 (proc-dev1 has .1 and .3, proc-dev2 has .2)
SELECT COUNT(*) AS orphan_devices FROM Device WHERE mac_address = '02:00:00:00:99:32';
SELECT COUNT(*) AS assigned_in_991 FROM IP_Address WHERE subnet_id = 991 AND status = 'assigned';


-- Test L1 is the release giving back all of a device's IPs while keeping the device
-- We expect ips_released = 2
SET @proc_dev1 = (SELECT device_id FROM Device WHERE mac_address = '02:00:00:00:99:01');
CALL sp_release_device_ips(@proc_dev1);
-- Verification: 10.97.0.1 and 10.97.0.3 should now be 'available' with device_id NULL
-- and 10.97.0.2 should still be 'assigned' to proc-dev2
SELECT ip_address, status, device_id FROM IP_Address
WHERE subnet_id = 991 AND ip_address IN ('10.97.0.1', '10.97.0.2', '10.97.0.3')
ORDER BY INET_ATON(ip_address);
-- The device itself should still exist (device_still_exists = 1)
SELECT COUNT(*) AS device_still_exists FROM Device WHERE device_id = @proc_dev1;


-- Test L2 is the lowest freed address being handed out again
-- Expected: assigned_ip = 10.97.0.1
CALL sp_request_static_ip(991, 'proc-dev4', '02:00:00:00:99:04', 'Server', 990, 1);


-- Test L3 is releasing a device that has no IPs (this should not be an error)
-- Expected: ips_released = 0
INSERT INTO Device (hostname, mac_address, device_type) VALUES ('proc-noip', '02:00:00:00:99:05', 'Patch Panel');
SET @proc_noip = (SELECT device_id FROM Device WHERE mac_address = '02:00:00:00:99:05');
CALL sp_release_device_ips(@proc_noip);


-- Test L4 is the nonexistent device ID lookup
-- Expected: ERROR 1644 (45000): sp_release_device_ips: device_id does not exist.
CALL sp_release_device_ips(999999);


-- Get rid of the stored procedure fixtures. The devices go first (the delete trigger frees their IPs,
-- so the subnet delete guard lets the subnets go), then the subnets, rack, VLAN and location
DELETE FROM Device WHERE mac_address LIKE '02:00:00:00:99:%';
DELETE FROM Subnet WHERE subnet_id IN (991, 992, 993);
DELETE FROM Rack WHERE rack_id = 990;
DELETE FROM VLAN WHERE vlan_id = 990;
DELETE FROM Location WHERE location_id = 990;


-- View demo 1: v_subnet_utilization (total, assigned and available IPs per subnet)
-- Expected with the seed data:
-- 10.1.10.0/24: 256 total, 20 assigned, 234 available, 91.41 percent available
-- 10.1.11.0/28: 16 total, 13 assigned, 1 available, 6.25 percent available (the busy one)
-- 10.2.20.0/24: 256 total, 6 assigned, 248 available, 96.88 percent available
SELECT * FROM v_subnet_utilization;


-- View demo 2: v_vlan_utilization (the same totals rolled up per VLAN)
-- Expected with the seed data:
-- VLAN 10 Servers: 272 total (the /24 and the /28), 33 assigned, 235 available, 86.40 percent
-- VLAN 20 Management: 256 total, 6 assigned, 248 available, 96.88 percent
-- VLAN 30 Guest WiFi and VLAN 40 IoT: 0 everywhere and a NULL percent (no subnets yet)
SELECT * FROM v_vlan_utilization;


-- View demo 3: v_rack_space (total, used and free units per rack)
-- Expected with the seed data:
-- W-R01: 18 used, 24 free
-- W-R02: 38 used, 4 free (nearly full)
-- T-R01: 15 used, 27 free
-- T-R02: 0 used, 42 free (empty)
SELECT * FROM v_rack_space;


-- View demo 4: v_location_rack_space (rack space rolled up per location)
-- Expected with the seed data:
-- Windsor Data Center: 84 total, 56 used, 28 free
-- Toronto Bank Site: 84 total, 15 used, 69 free
-- Calgary Branch Office: 0 in every column (it has no racks, but it still shows up)
SELECT * FROM v_location_rack_space;