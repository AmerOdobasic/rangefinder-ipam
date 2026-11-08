USE rangefinder;

-- Subnet delete guard:
DELIMITER //
CREATE TRIGGER trg_subnet_delete_guard
BEFORE DELETE ON Subnet
FOR EACH ROW
BEGIN
    DECLARE ip_match_count INT;
    -- We need to count assigned IPs belonging to the subnet being deleted
    SELECT COUNT(*) 
      INTO ip_match_count 
      FROM IP_Address 
      WHERE subnet_id = OLD.subnet_id AND status = 'assigned';

    -- We need to stop the deletion if any assigned IPs exist...
    IF ip_match_count > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cannot delete subnet! Its assigned IP addresses still exist...';
    END IF;
END//
DELIMITER ;

DELIMITER //
-- Deleting a device releases the IP:
CREATE TRIGGER trg_device_delete_release_ips
BEFORE DELETE ON Device
FOR EACH ROW
BEGIN
    UPDATE IP_Address
       SET status = 'available', device_id = NULL
    WHERE device_id = OLD.device_id;
END//

DELIMITER ;

-- Duplicate ID guard:
DELIMITER //
CREATE TRIGGER trg_ip_insert_check
BEFORE INSERT ON IP_Address
FOR EACH ROW
BEGIN
    -- All assigned IPs must reference a device that is valid:
    IF NEW.status = 'assigned' AND NEW.device_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cant insert IP since status is assigned but device_id is NULL!';
    END IF;

    -- The available or reserved IPs must NOT reference a device
    IF NEW.status IN ('available', 'reserved') AND NEW.device_id IS NOT NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cannot insert IP since status is available/reserved but device_id is set!';
    END IF;
END//
DELIMITER ;

DELIMITER //
CREATE TRIGGER trg_ip_update_check
BEFORE UPDATE ON IP_Address
FOR EACH ROW
BEGIN
    -- We need to prevent duplicate assignment (this happens by reassigning directly to another device)
    -- If its already assigned, that means the device is changing, and it is NOT being released to NULL
    IF OLD.status = 'assigned' AND NOT (OLD.device_id <=> NEW.device_id) AND NEW.device_id IS NOT NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cant reassign the IP since the address is already assigned to another device. Please release it first!';
    END IF;

    -- We also need to check that the assigned status has a device_id
    IF NEW.status = 'assigned' AND NEW.device_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cant update IP because the status is assigned but device_id is NULL...';
    END IF;

    -- Lastly, see if the available or reserved status doesnt have a device_id
    IF NEW.status IN ('available', 'reserved') AND NEW.device_id IS NOT NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cant update IP since status is available/reserved but device_id is set.';
    END IF;
END//
DELIMITER ;

-- Protect against subnet overlapping: 
DELIMITER //
CREATE TRIGGER trg_subnet_overlap_insert
BEFORE INSERT ON Subnet
FOR EACH ROW
BEGIN
    DECLARE v_new_net VARCHAR(15);
    DECLARE v_new_prefix INT;
    DECLARE v_new_start BIGINT UNSIGNED;
    DECLARE v_new_end BIGINT UNSIGNED;
    DECLARE v_block_size BIGINT UNSIGNED;
    DECLARE v_overlap_count INT;

    -- Get the IP and prefix directly from the NEW.cidr_block
    SET v_new_net = SUBSTRING_INDEX(NEW.cidr_block, '/', 1);
    SET v_new_prefix = CAST(SUBSTRING_INDEX(NEW.cidr_block, '/', -1) AS UNSIGNED);

    -- Find the integer range for the subnets that incoming:
    SET v_new_start = INET_ATON(v_new_net);
    -- Make sure to validate the IP address syntax
    IF v_new_start IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Wrong IPv4 address format in the CIDR block...';
    END IF;

    -- Find the block size,
    SET v_block_size = POW(2, 32 - v_new_prefix);

    -- Then reject host bits (since it must be a clean network boundary)
    IF (v_new_start % v_block_size) <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'The CIDR is invalid. All host bits are set (make sure its a valid network address!).';
    END IF;

    -- Compute end boundary
    SET v_new_end = v_new_start + v_block_size - 1;

    -- Now we need to see for any overlapping subnets...
    SELECT COUNT(*)
    INTO v_overlap_count
    FROM Subnet
    WHERE INET_ATON(network_address) <= v_new_end AND v_new_start <= (INET_ATON(network_address) + POW(2, 32 - prefix_length) - 1);

    IF v_overlap_count > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Subnet CIDR overlaps with an existing subnet range!';
    END IF;
END//
DELIMITER ;

DELIMITER //
CREATE TRIGGER trg_subnet_overlap_update
BEFORE UPDATE ON Subnet
FOR EACH ROW
BEGIN
    DECLARE v_new_net VARCHAR(15);
    DECLARE v_new_prefix INT;
    DECLARE v_new_start BIGINT UNSIGNED;
    DECLARE v_new_end BIGINT UNSIGNED;
    DECLARE v_block_size BIGINT UNSIGNED;
    DECLARE v_overlap_count INT;

    -- Get both the IP and prefix directly from NEW.cidr_block
    SET v_new_net = SUBSTRING_INDEX(NEW.cidr_block, '/', 1);
    SET v_new_prefix = CAST(SUBSTRING_INDEX(NEW.cidr_block, '/', -1) AS UNSIGNED);

    -- Get the integer range for the updated subnet
    SET v_new_start = INET_ATON(v_new_net);
    -- Make sure that the IP address syntax is correct
    IF v_new_start IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Wrong IPv4 address format in the CIDR block...';
    END IF;

    -- Find the right block size...
    SET v_block_size = POW(2, 32 - v_new_prefix);

    -- Then reject any host bits like before:
    IF (v_new_start % v_block_size) <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'The CIDR is invalid. All host bits are set (make sure its a valid network address!)';
    END IF;

    -- Compute the end boundary
    SET v_new_end = v_new_start + v_block_size - 1;

    -- Check for overlapping subnets while excluding the row currently being updated:
    SELECT COUNT(*)
    INTO v_overlap_count
    FROM Subnet
    WHERE subnet_id <> OLD.subnet_id AND INET_ATON(network_address) <= v_new_end AND v_new_start <= (INET_ATON(network_address) + POW(2, 32 - prefix_length) - 1);

    IF v_overlap_count > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Subnet CIDR overlaps with an existing subnet range!';
    END IF;
END//
DELIMITER ;

-- Device has moved, so release devices IP:
DELIMITER //
CREATE TRIGGER trg_device_move_release_ips
AFTER UPDATE ON Device
FOR EACH ROW
BEGIN
    DECLARE v_old_location_id INT;
    DECLARE v_new_location_id INT;

    -- Only go forward from here if the rack actually changed and neither rack is NULL
    IF NOT (OLD.rack_id <=> NEW.rack_id) AND OLD.rack_id IS NOT NULL AND NEW.rack_id IS NOT NULL THEN

        -- Check the location of the old rack
        SELECT location_id 
            INTO v_old_location_id 
            FROM Rack 
            WHERE rack_id = OLD.rack_id;

        -- Then the new one...
        SELECT location_id 
            INTO v_new_location_id 
            FROM Rack 
            WHERE rack_id = NEW.rack_id;

        -- Now if the physical locations differ, release all IPs assigned to this device
        IF v_old_location_id <> v_new_location_id THEN
            UPDATE IP_Address
                SET status = 'available', device_id = NULL
            WHERE device_id = NEW.device_id;
        END IF;

    END IF;
END//
DELIMITER ;