-- This is the Step 4 schema skeleton
-- Was made from the Step 3 relational schema. Run SELECT VERSION(); first.

DROP DATABASE IF EXISTS rangefinder;
CREATE DATABASE rangefinder;
USE rangefinder;

CREATE TABLE Location (
    location_id  INT AUTO_INCREMENT PRIMARY KEY,
    building     VARCHAR(100) NOT NULL,
    room         VARCHAR(100) NOT NULL,
    description  VARCHAR(255) NULL,
    CONSTRAINT uq_location UNIQUE (building, room)
) ENGINE=InnoDB;

CREATE TABLE Rack (
    rack_id      INT AUTO_INCREMENT PRIMARY KEY,
    location_id  INT NOT NULL,
    rack_label   VARCHAR(50) NOT NULL,
    total_units  INT NOT NULL DEFAULT 42,
    CONSTRAINT uq_rack UNIQUE (location_id, rack_label),
    CONSTRAINT chk_rack_units CHECK (total_units > 0),
    CONSTRAINT fk_rack_location FOREIGN KEY (location_id)
        REFERENCES Location (location_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE VLAN (
    vlan_id      INT PRIMARY KEY,
    vlan_name    VARCHAR(100) NOT NULL,
    description  VARCHAR(255) NULL,
    CONSTRAINT uq_vlan_name UNIQUE (vlan_name),
    CONSTRAINT chk_vlan_range CHECK (vlan_id BETWEEN 1 AND 4094)
) ENGINE=InnoDB;

CREATE TABLE Subnet (
    subnet_id        INT AUTO_INCREMENT PRIMARY KEY,
    cidr_block       VARCHAR(18) NOT NULL,
    -- From the TA Feedback we got: these two are derivable from cidr_block. We'll keep them as STORED generated columns so they can never disagree with it 
    -- (they are still real, indexable columns for the overlap trigger)
    network_address  VARCHAR(15) GENERATED ALWAYS AS (SUBSTRING_INDEX(cidr_block, '/', 1)) STORED,
    prefix_length    INT GENERATED ALWAYS AS (CAST(SUBSTRING_INDEX(cidr_block, '/', -1) AS UNSIGNED)) STORED,
    vlan_id          INT NOT NULL,
    location_id      INT NOT NULL,
    CONSTRAINT uq_subnet_cidr UNIQUE (cidr_block),
    CONSTRAINT chk_prefix CHECK (prefix_length BETWEEN 1 AND 32),
    CONSTRAINT fk_subnet_vlan FOREIGN KEY (vlan_id)
        REFERENCES VLAN (vlan_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_subnet_location FOREIGN KEY (location_id)
        REFERENCES Location (location_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE Device (
    device_id    INT AUTO_INCREMENT PRIMARY KEY,
    hostname     VARCHAR(255) NOT NULL,
    mac_address  VARCHAR(17) NOT NULL,
    device_type  VARCHAR(50) NOT NULL,
    rack_units   INT NULL,
    rack_id      INT NULL,
    CONSTRAINT uq_device_mac UNIQUE (mac_address),
    CONSTRAINT fk_device_rack FOREIGN KEY (rack_id)
        REFERENCES Rack (rack_id)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IP_Address (
    ip_id       INT AUTO_INCREMENT PRIMARY KEY,
    subnet_id   INT NOT NULL,
    ip_address  VARCHAR(15) NOT NULL,
    status      VARCHAR(20) NOT NULL DEFAULT 'available',
    device_id   INT NULL,
    CONSTRAINT uq_ip UNIQUE (ip_address),
    CONSTRAINT chk_ip_status CHECK (status IN ('available','assigned','reserved')),
    CONSTRAINT fk_ip_subnet FOREIGN KEY (subnet_id)
        REFERENCES Subnet (subnet_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_ip_device FOREIGN KEY (device_id)
        REFERENCES Device (device_id)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE User_Account (
    user_id        INT AUTO_INCREMENT PRIMARY KEY,
    username       VARCHAR(50) NOT NULL,
    password_hash  VARCHAR(255) NOT NULL,
    role           VARCHAR(50) NOT NULL,
    CONSTRAINT uq_username UNIQUE (username),
    CONSTRAINT chk_role CHECK (role IN ('Network Administrator','Systems Engineer','Read-Only Auditor'))
) ENGINE=InnoDB;

-- Some helpful indexes for the "next available IP" and resource consumption queries
CREATE INDEX idx_ip_subnet_status ON IP_Address (subnet_id, status);
CREATE INDEX idx_ip_device ON IP_Address (device_id);
