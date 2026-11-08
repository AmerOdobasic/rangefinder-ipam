-- 04_views.sql  
-- Owner: Marc
USE rangefinder;

-- 1. v_subnet_utilization
-- One row per subnet: total IPs, how many are assigned, how many are
-- available, and the percent still available
CREATE VIEW v_subnet_utilization AS
SELECT 
    s.subnet_id,
    s.cidr_block,
    COUNT(i.ip_id) AS total_ips,
    -- CASE gives 1 for each matching row and 0 for the rest, so SUM adds up
    -- how many rows match. The ELSE 0 also keeps empty subnets at 0, not NULL
    SUM(CASE WHEN i.status = 'assigned' THEN 1 ELSE 0 END) AS assigned_ips,
    SUM(CASE WHEN i.status = 'available' THEN 1 ELSE 0 END) AS available_ips,
    -- available / total * 100, rounded to 2 decimals
    ROUND((SUM(CASE WHEN i.status = 'available' THEN 1 ELSE 0 END) / COUNT(i.ip_id)) * 100, 2) AS percent_available
FROM Subnet s
LEFT JOIN IP_Address i ON s.subnet_id = i.subnet_id
GROUP BY s.subnet_id, s.cidr_block;


-- 2. v_vlan_utilization
-- Same numbers as view 1, but moved one level up: one row per VLAN, adding up all the subnets that belong to it
CREATE VIEW v_vlan_utilization AS
SELECT 
    v.vlan_id,
    v.vlan_name,
    COUNT(i.ip_id) AS total_ips,
    SUM(CASE WHEN i.status = 'assigned' THEN 1 ELSE 0 END) AS assigned_ips,
    SUM(CASE WHEN i.status = 'available' THEN 1 ELSE 0 END) AS available_ips,
    ROUND((SUM(CASE WHEN i.status = 'available' THEN 1 ELSE 0 END) / COUNT(i.ip_id)) * 100, 2) AS percent_available
FROM VLAN v
LEFT JOIN Subnet s ON v.vlan_id = s.vlan_id
LEFT JOIN IP_Address i ON s.subnet_id = i.subnet_id
GROUP BY v.vlan_id, v.vlan_name;


-- 3. v_rack_space
-- One row per rack: total units, units used by its devices, and units still free
CREATE VIEW v_rack_space AS
SELECT 
    r.rack_id,
    r.rack_label,
    r.total_units,
    -- COALESCE(value, 0) is used to return the first value that is not NULL.
    -- A rack with no devices has nothing to add, so SUM returns NULL and
    -- COALESCE turns it into 0
    COALESCE(SUM(d.rack_units), 0) AS used_units,
    (r.total_units - COALESCE(SUM(d.rack_units), 0)) AS free_units
FROM Rack r
LEFT JOIN Device d ON r.rack_id = d.rack_id
GROUP BY r.rack_id, r.rack_label, r.total_units;


-- 4. v_location_rack_space
-- Rack space rolled up per location / server room. It adds up v_rack_space
-- (one row per rack) so each rack's total_units is only counted once
CREATE VIEW v_location_rack_space AS
SELECT
    l.location_id,
    l.building,
    l.room,
    -- COALESCE again: a room with no racks has nothing to add, so SUM is NULL
    COALESCE(SUM(rs.total_units), 0) AS total_location_units,
    COALESCE(SUM(rs.used_units), 0)  AS used_location_units,
    COALESCE(SUM(rs.free_units), 0)  AS free_location_units
FROM Location l
-- Rack is needed here to link each location to its racks (v_rack_space does not have a location_id column)
LEFT JOIN Rack r          ON r.location_id = l.location_id
LEFT JOIN v_rack_space rs ON rs.rack_id = r.rack_id
GROUP BY l.location_id, l.building, l.room;