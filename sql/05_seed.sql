USE rangefinder;

-- Locations portion
-- Here calgary has zero racks and devices to show Query 5's LEFT JOIN
INSERT INTO Location (building, room, description) 
VALUES ('Windsor Data Center', 'Suite 100', '401 Sunset Ave, Windsor ON');
SET @loc_windsor = LAST_INSERT_ID();

INSERT INTO Location (building, room, description) 
VALUES ('Toronto Bank Site', 'Interconnection Hub', '100 King St W, Toronto ON');
SET @loc_toronto = LAST_INSERT_ID();

INSERT INTO Location (building, room, description) 
VALUES ('Calgary Branch Office', 'Server Closet B', '200 8 Ave SW, Calgary AB');
SET @loc_calgary = LAST_INSERT_ID();


-- The VLANs:
-- Using explicit IDs since vlan_id is not AUTO_INCREMENT
INSERT INTO VLAN (vlan_id, vlan_name, description) VALUES (10, 'Servers', 'Main production servers');
SET @vlan_servers = 10;

INSERT INTO VLAN (vlan_id, vlan_name, description) VALUES (20, 'Management', 'Network for IT to fix the equipment');
SET @vlan_mgmt = 20;

INSERT INTO VLAN (vlan_id, vlan_name, description) VALUES (30, 'Guest WiFi', 'Wireless access for users');
SET @vlan_guest = 30;

INSERT INTO VLAN (vlan_id, vlan_name, description) VALUES (40, 'IoT', 'Isolated facility devices');
SET @vlan_iot = 40;


-- Subnets & IP Generation 
-- /24 on VLAN 10 (for Windsor). This makes 254 usable IPs
INSERT INTO Subnet (cidr_block, vlan_id, location_id) 
VALUES ('10.1.10.0/24', @vlan_servers, @loc_windsor);
SET @sn_servers = LAST_INSERT_ID();
CALL sp_generate_ips(@sn_servers);

-- 13 of 14 usable IPs get assigned in this subnet... (Query 1)
-- /28 on VLAN 10 (Windsor) gives 14 usable IPs
INSERT INTO Subnet (cidr_block, vlan_id, location_id) 
VALUES ('10.1.11.0/28', @vlan_servers, @loc_windsor);
SET @sn_dmz = LAST_INSERT_ID();
CALL sp_generate_ips(@sn_dmz);

-- /24 on VLAN 20 (Toronto) gives 254 usable IPs
INSERT INTO Subnet (cidr_block, vlan_id, location_id) 
VALUES ('10.2.20.0/24', @vlan_mgmt, @loc_toronto);
SET @sn_mgmt = LAST_INSERT_ID();
CALL sp_generate_ips(@sn_mgmt);

-- Racks portion
-- Calgary gets no racks on purpose. W-R02 is nearly full (38 of 42 units) and T-R02 is empty
INSERT INTO Rack (location_id, rack_label, total_units) VALUES
    (@loc_windsor, 'W-R01', 42),
    (@loc_windsor, 'W-R02', 42),
    (@loc_toronto, 'T-R01', 42),
    (@loc_toronto, 'T-R02', 42);

SET @rack_w1 = (SELECT rack_id FROM Rack WHERE location_id = @loc_windsor AND rack_label = 'W-R01');
SET @rack_w2 = (SELECT rack_id FROM Rack WHERE location_id = @loc_windsor AND rack_label = 'W-R02');
SET @rack_t1 = (SELECT rack_id FROM Rack WHERE location_id = @loc_toronto AND rack_label = 'T-R01');


-- Devices portion (20 devices, all racked)
-- The devices go in first and their IPs are assigned after, in the next section
-- pp-toronto01, pdu-toronto01 and ups01 never get an IP (passive gear), so Query 2 has rows to show
INSERT INTO Device (hostname, mac_address, device_type, rack_units, rack_id) VALUES
    -- Rack W-R01 (18 of 42 units): firewall, load balancer and the web/database servers
    ('fw01',          '00:1A:2B:3C:5D:01', 'Firewall',      1,  @rack_w1),
    ('lb01',          '00:1A:2B:3C:5D:02', 'Load Balancer', 1,  @rack_w1),
    ('proxy01',       '00:1A:2B:3C:5D:03', 'Server',        1,  @rack_w1),
    ('web01',         '00:1A:2B:3C:5D:04', 'Server',        2,  @rack_w1),
    ('web02',         '00:1A:2B:3C:5D:05', 'Server',        2,  @rack_w1),
    ('mail01',        '00:1A:2B:3C:5D:06', 'Server',        2,  @rack_w1),
    ('dns01',         '00:1A:2B:3C:5D:07', 'Server',        1,  @rack_w1),
    ('db01',          '00:1A:2B:3C:5D:13', 'Server',        4,  @rack_w1),
    ('db02',          '00:1A:2B:3C:5D:14', 'Server',        4,  @rack_w1),
    -- Rack W-R02 (38 of 42 units): blade chassis and a SAN, nearly full
    ('blade01',       '00:1A:2B:3C:5D:08', 'Blade Chassis', 10, @rack_w2),
    ('blade02',       '00:1A:2B:3C:5D:09', 'Blade Chassis', 10, @rack_w2),
    ('blade03',       '00:1A:2B:3C:5D:0A', 'Blade Chassis', 10, @rack_w2),
    ('san01',         '00:1A:2B:3C:5D:0B', 'Storage',       8,  @rack_w2),
    -- Rack T-R01 (15 of 42 units): network gear, backup and the three devices with no IP
    ('sw-core01',     '00:1A:2B:3C:5D:10', 'Switch',        1,  @rack_t1),
    ('sw-core02',     '00:1A:2B:3C:5D:11', 'Switch',        1,  @rack_t1),
    ('rtr01',         '00:1A:2B:3C:5D:12', 'Router',        2,  @rack_t1),
    ('backup01',      '00:1A:2B:3C:5D:15', 'Storage',       4,  @rack_t1),
    ('pp-toronto01',  '00:1A:2B:3C:5D:20', 'Patch Panel',   1,  @rack_t1),
    ('pdu-toronto01', '00:1A:2B:3C:5D:21', 'PDU',           2,  @rack_t1),
    ('ups01',         '00:1A:2B:3C:5D:22', 'UPS',           4,  @rack_t1);
-- T-R02 stays empty on purpose (no devices)


-- IP assignments portion
-- Each UPDATE matches a list of (ip, hostname) pairs to the existing IP rows and the devices.
-- Setting status and device_id together is what trg_ip_update_check expects.
-- Some devices get more than one IP (second interface or virtual IP), that is fine

-- 10.1.11.0/28 (DMZ): 13 of the 14 usable IPs (.1 to .13) are assigned, .14 stays free (Query 1)
UPDATE IP_Address ip
JOIN (
    SELECT '10.1.11.1'  AS ip_addr, 'fw01'    AS host UNION ALL
    SELECT '10.1.11.2',  'lb01'    UNION ALL
    SELECT '10.1.11.3',  'proxy01' UNION ALL
    SELECT '10.1.11.4',  'web01'   UNION ALL
    SELECT '10.1.11.5',  'web02'   UNION ALL
    SELECT '10.1.11.6',  'mail01'  UNION ALL
    SELECT '10.1.11.7',  'dns01'   UNION ALL
    SELECT '10.1.11.8',  'blade01' UNION ALL
    SELECT '10.1.11.9',  'blade02' UNION ALL
    SELECT '10.1.11.10', 'blade03' UNION ALL
    SELECT '10.1.11.11', 'san01'   UNION ALL
    SELECT '10.1.11.12', 'lb01'    UNION ALL   -- virtual IP for the load balancer
    SELECT '10.1.11.13', 'fw01'                -- second firewall interface
) m ON m.ip_addr = ip.ip_address
JOIN Device d ON d.hostname = m.host
SET ip.status = 'assigned', ip.device_id = d.device_id
WHERE ip.subnet_id = @sn_dmz;

-- 10.1.10.0/24 (Servers, Windsor): 20 IPs assigned (.1 to .20), so the next free one is .21
UPDATE IP_Address ip
JOIN (
    SELECT '10.1.10.1'  AS ip_addr, 'web01'    AS host UNION ALL
    SELECT '10.1.10.2',  'web02'    UNION ALL
    SELECT '10.1.10.3',  'mail01'   UNION ALL
    SELECT '10.1.10.4',  'dns01'    UNION ALL
    SELECT '10.1.10.5',  'proxy01'  UNION ALL
    SELECT '10.1.10.6',  'lb01'     UNION ALL
    SELECT '10.1.10.7',  'blade01'  UNION ALL
    SELECT '10.1.10.8',  'blade02'  UNION ALL
    SELECT '10.1.10.9',  'blade03'  UNION ALL
    SELECT '10.1.10.10', 'san01'    UNION ALL
    SELECT '10.1.10.11', 'db01'     UNION ALL
    SELECT '10.1.10.12', 'db02'     UNION ALL
    SELECT '10.1.10.13', 'backup01' UNION ALL
    SELECT '10.1.10.14', 'fw01'     UNION ALL
    SELECT '10.1.10.15', 'db01'     UNION ALL   -- second addresses for devices with two interfaces
    SELECT '10.1.10.16', 'db02'     UNION ALL
    SELECT '10.1.10.17', 'blade01'  UNION ALL
    SELECT '10.1.10.18', 'blade02'  UNION ALL
    SELECT '10.1.10.19', 'blade03'  UNION ALL
    SELECT '10.1.10.20', 'san01'
) m ON m.ip_addr = ip.ip_address
JOIN Device d ON d.hostname = m.host
SET ip.status = 'assigned', ip.device_id = d.device_id
WHERE ip.subnet_id = @sn_servers;

-- 10.2.20.0/24 (Management, Toronto): network gear plus the management addresses of a few servers
UPDATE IP_Address ip
JOIN (
    SELECT '10.2.20.1' AS ip_addr, 'sw-core01' AS host UNION ALL
    SELECT '10.2.20.2', 'sw-core02' UNION ALL
    SELECT '10.2.20.3', 'rtr01'     UNION ALL
    SELECT '10.2.20.4', 'backup01'  UNION ALL
    SELECT '10.2.20.5', 'db01'      UNION ALL
    SELECT '10.2.20.6', 'db02'
) m ON m.ip_addr = ip.ip_address
JOIN Device d ON d.hostname = m.host
SET ip.status = 'assigned', ip.device_id = d.device_id
WHERE ip.subnet_id = @sn_mgmt;


-- Users portion (3 users, the hashes are fake on purpose and not real passwords)
INSERT INTO User_Account (username, password_hash, role) VALUES
    ('netadmin', 'FAKE_HASH_netadmin_not_a_real_hash', 'Network Administrator'),
    ('syseng',   'FAKE_HASH_syseng_not_a_real_hash',   'Systems Engineer'),
    ('auditor',  'FAKE_HASH_auditor_not_a_real_hash',  'Read-Only Auditor');