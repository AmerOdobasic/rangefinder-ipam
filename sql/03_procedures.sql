-- 03_procedures.sql  
-- Owner: Marc
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

    -- Roll back everything if anything fails part-way through
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    -- Look up the subnet (network_address / prefix_length are generated columns)
    SELECT network_address, prefix_length
      INTO v_network, v_prefix
      FROM Subnet
     WHERE subnet_id = p_subnet_id;

    IF v_network IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'sp_generate_ips: subnet_id does not exist.';
    END IF;

    -- Safety limits: /31 and /32 have no usable host range, and anything bigger
    -- than a /16 would insert 65k+ rows through a loop
    IF v_prefix > 30 OR v_prefix < 16 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'sp_generate_ips: prefix length must be between /16 and /30.';
    END IF;

    -- makes sure it does not generate twice for the same subnet
    SELECT COUNT(*) INTO v_existing
      FROM IP_Address
     WHERE subnet_id = p_subnet_id;

    IF v_existing > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'sp_generate_ips: IP addresses were already generated for this subnet.';
    END IF;

    SET v_start = INET_ATON(v_network);
    SET v_size  = POW(2, 32 - v_prefix);
    SET v_end   = v_start + v_size - 1;
    SET v_cur   = v_start;

    START TRANSACTION;

    WHILE v_cur <= v_end DO
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

    -- Reports what was created
    SELECT p_subnet_id AS subnet_id,
           v_size      AS total_ips_created,
           v_size - 2  AS usable_ips;
END//
DELIMITER ;