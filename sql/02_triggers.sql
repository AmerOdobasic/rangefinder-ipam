-- 02_triggers.sql
-- Owner: Amer
USE rangefinder;

-- Things that need to be done (from Step 2 use cases):
--  1. trg_subnet_no_overlap      BEFORE INSERT/UPDATE ON Subnet
--       Parse NEW.cidr_block directly (these are generated columns that are not ready in BEFORE triggers).
--       Overlap if start1 <= end2 AND start2 <= end1. On UPDATE, exclude the row itself.
--       Needs to be raised with SIGNAL SQLSTATE '45000'.
--  2. trg_subnet_delete_guard    BEFORE DELETE ON Subnet
--       Block if any IP in the subnet has status 'assigned'.
--  3. trg_ip_no_duplicate        BEFORE INSERT/UPDATE ON IP_Address
--       Clear error message; UNIQUE(ip_address) stays as the backup.
--  4. trg_device_release_on_delete  BEFORE DELETE ON Device
--       Set that device's IPs to 'available' and clear device_id.
--  5. trg_device_release_on_move    AFTER UPDATE ON Device (optional, see Discord)
--       If rack_id changes to a rack in a different location, release the device's IPs.
