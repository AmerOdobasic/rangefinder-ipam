def friendly_error(err):
    code = err.errno
    if code == 1644:  # from our triggers and procedures 
        return err.msg
    if code in (1044, 1142, 1143, 1370):   # the permission is denied in this case
        return "Not allowed for the role you have"
    if code == 1451:
        return "Cannot delete this record because other records still depend on it!"
    if code == 1452:
        return "That references a record that does not exist."
    if code == 1062:
        if "uq_device_mac" in err.msg:
            return "A device with that MAC address already exists."
        if "uq_location" in err.msg:
            return "That building and room combination already exists."
        if "uq_vlan_name" in err.msg:
            return "A VLAN with that name already exists."
        if "uq_subnet_cidr" in err.msg:
            return "That subnet already exists."
        return "That value already exists and must be unique."
    if code == 3819:
        return "A value breaks a rule (check the numbers and ranges)."
    if code == 1411:
        return "A value has an invalid format."
    return f"Database error: {err.msg}"