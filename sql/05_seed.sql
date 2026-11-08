-- 05_seed.sql 
-- Owners: Amer and Marc
USE rangefinder;

-- What to do: 2-3 locations, a few racks, 3-4 VLANs, a /24 and a /28 subnet (call sp_generate_ips),
-- about 20 devices, a few hundred IP rows, 3 User_Account rows (fake hashes only btw).
-- Keep trigger test cases (so duplicate IP, overlapping subnet, delete subnet with assigned IP,
-- delete device) in 06_queries.sql, not written here tho, so the build never fails on purpose...

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
