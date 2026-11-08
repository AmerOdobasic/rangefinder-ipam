USE rangefinder;

DROP PROCEDURE IF EXISTS sp_generate_ips;
DELIMITER //
CREATE PROCEDURE sp_generate_ips(IN p_subnet_id INT)
BEGIN
    DECLARE v_network   VARCHAR(15);       
    DECLARE v_prefix    INT;               
    DECLARE v_start     BIGINT UNSIGNED;    
    DECLARE v_size      BIGINT UNSIGNED;    
    DECLARE v_end       BIGINT UNSIGNED;    
    DECLARE v_cur       BIGINT UNSIGNED;   
    DECLARE v_existing  INT;                

    -- If anything fails part-way through, it undos all the inserts and pass the
    -- original error on to the caller (so we never keep a half-filled subnet)
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    -- network_address and prefix_length are generated columns on Subnet,
    -- so they always agree with cidr_block
    SELECT network_address, prefix_length
    INTO v_network, v_prefix
    FROM Subnet
     WHERE subnet_id = p_subnet_id;

    -- No row found means the variables are still NULL
    IF v_network IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'sp_generate_ips: subnet_id does not exist.';
    END IF;

    -- Safety limits: /31 and /32 have no usable host range, and anything
    -- bigger than a /16 would mean 65k+ rows inserted one by one in a loop
    IF v_prefix > 30 OR v_prefix < 16 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'sp_generate_ips: prefix length must be between /16 and /30.';
    END IF;

    -- Makes sure to not generate twice for the same subnet
    SELECT COUNT(*) INTO v_existing
    FROM IP_Address
    WHERE subnet_id = p_subnet_id;

    IF v_existing > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'sp_generate_ips: IP addresses were already generated for this subnet.';
    END IF;

    -- Turn the dotted address into a number so we can just count up.
    SET v_start = INET_ATON(v_network);
    SET v_size  = POW(2, 32 - v_prefix);
    SET v_end   = v_start + v_size - 1;
    SET v_cur   = v_start;

    -- One transaction for the whole loop: all or nothing, and only one
    -- commit instead of 256
    START TRANSACTION;

    WHILE v_cur <= v_end DO
        -- INET_NTOA turns the number back into dotted form.
        -- First and last address are reserved, everything else is available.
        -- device_id stays NULL (the trg_ip_insert_check trigger requires this)
        INSERT INTO IP_Address (subnet_id, ip_address, status, device_id)
        VALUES (
            p_subnet_id,
            INET_NTOA(v_cur),
            IF(v_cur = v_start OR v_cur = v_end, 'reserved', 'available'),
            NULL
        );
        SET v_cur = v_cur + 1;
    END WHILE;

    COMMIT;

    -- Shows what was created
    SELECT p_subnet_id AS subnet_id,
           v_size      AS total_ips_created,
           v_size - 2  AS usable_ips;
END//
DELIMITER ;

DROP PROCEDURE IF EXISTS sp_request_static_ip;
DELIMITER //
CREATE PROCEDURE sp_request_static_ip(
    IN p_subnet_id   INT,
    IN p_hostname    VARCHAR(255),
    IN p_mac         VARCHAR(17),
    IN p_device_type VARCHAR(50),
    IN p_rack_id     INT,
    IN p_rack_units  INT
)
BEGIN
    -- Start as NULL so we can tell later whether the SELECTs found a row
    DECLARE v_device_id INT DEFAULT NULL;
    DECLARE v_ip_id     INT DEFAULT NULL;
    DECLARE v_ip        VARCHAR(15) DEFAULT NULL;
    DECLARE v_subnet_ok INT;

    -- Any error: undo everything (including a newly inserted device) and pass the error on to the caller
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    -- Checks the subnet exists before opening the transaction
    SELECT COUNT(*) INTO v_subnet_ok
      FROM Subnet
     WHERE subnet_id = p_subnet_id;

    IF v_subnet_ok = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'sp_request_static_ip: subnet_id does not exist.';
    END IF;

    START TRANSACTION;

    -- a) mac_address is unique, so it identifies the device.
    -- If the device already exists we reuse it instead of inserting a duplicate
    SELECT device_id INTO v_device_id
    FROM Device
    WHERE mac_address = p_mac
    FOR UPDATE;

    IF v_device_id IS NULL THEN
        INSERT INTO Device (hostname, mac_address, device_type, rack_units, rack_id)
        VALUES (p_hostname, p_mac, p_device_type, p_rack_units, p_rack_id);
        SET v_device_id = LAST_INSERT_ID();
    END IF;

    -- b) lowest available address first. INET_ATON makes the sort
    -- numeric (as text, 10.0.0.10 would come before 10.0.0.2).
    -- FOR UPDATE locks the chosen row until COMMIT, so if two people request
    -- an IP at the same time the second one waits and then gets the next one
    SELECT ip_id, ip_address
    INTO v_ip_id, v_ip
    FROM IP_Address
    WHERE subnet_id = p_subnet_id AND status = 'available'
    ORDER BY INET_ATON(ip_address)
    LIMIT 1
    FOR UPDATE;

    -- Nothing came back, so the subnet is full (this rolls back the new device)
    IF v_ip_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'sp_request_static_ip: no available IP addresses left in this subnet.';
    END IF;

    -- c) status and device_id are set together, which is what the
    -- trg_ip_update_check trigger expects (assigned must have a device)
    UPDATE IP_Address
       SET status = 'assigned',
           device_id = v_device_id
    WHERE ip_id = v_ip_id;

    COMMIT;

    -- Returns the result to the caller
    SELECT v_ip        AS assigned_ip,
           v_device_id AS device_id,
           p_hostname  AS hostname,
           p_subnet_id AS subnet_id;
END//
DELIMITER ;

DROP PROCEDURE IF EXISTS sp_release_device_ips;
DELIMITER //
CREATE PROCEDURE sp_release_device_ips(IN p_device_id INT)
BEGIN
    DECLARE v_device_ok INT;
    DECLARE v_released  INT;    -- how many IPs were freed

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    -- Makes sure the device exists so a typo gives an error instead of
    -- silently releasing 0 IPs
    SELECT COUNT(*) INTO v_device_ok
    FROM Device
    WHERE device_id = p_device_id;

    IF v_device_ok = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'sp_release_device_ips: device_id does not exist.';
    END IF;

    START TRANSACTION;

    -- Status and device_id change together (trg_ip_update_check allows
    -- assigned -> available only when device_id becomes NULL)
    UPDATE IP_Address
       SET status = 'available',
           device_id = NULL
    WHERE device_id = p_device_id;

    -- ROW_COUNT() must be read right after the UPDATE
    SET v_released = ROW_COUNT();

    COMMIT;

    SELECT p_device_id AS device_id,
           v_released  AS ips_released;
END//
DELIMITER ;