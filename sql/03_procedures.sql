-- 03_procedures.sql  
-- Owner: Marc
USE rangefinder;

-- Things that need to be done (from Step 2 use cases):
--  1. sp_generate_ips(subnet_id)        create one IP_Address row per address in the subnet
--       (network + broadcast inserted as 'reserved'; /24 -> 254 usable of 256). This needs to be called after a subnet is created
--  2. sp_request_static_ip(subnet_id, hostname, mac, device_type [, rack_id, rack_units])
--       The first scenario creates the Device row if needed, then picks the next available IP
--       (ORDER BY INET_ATON(ip_address)) inside a transaction with SELECT ... FOR UPDATE,
--       marks it 'assigned', links device_id, returns the IP.
--  3. sp_release_device_ips(device_id)  device shut down / moved. So the IPs is back to 'available', and device_id NULL.
