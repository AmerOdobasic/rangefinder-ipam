import re

import mysql.connector
from flask import Blueprint, render_template, request, redirect, url_for, flash, abort
from ..db import query_all, query_one, execute
from ..auth import login_required, role_required
from ..errors import friendly_error

bp = Blueprint("devices", __name__, url_prefix="/devices")
ADMIN = "Network Administrator"
ENGINEER = "Systems Engineer"

# Same pattern ips.py uses for the IP-request form, so MAC formatting is
# enforced consistently everywhere a device/MAC is entered.
MAC_RE = re.compile(r"^([0-9A-F]{2}:){5}[0-9A-F]{2}$")


def get_racks():
    return query_all(
        "SELECT r.rack_id, r.rack_label, l.building, l.room "
        "FROM Rack r JOIN Location l ON r.location_id = l.location_id "
        "ORDER BY l.building, l.room, r.rack_label"
    )


def rack_space_left(rack_id, exclude_device_id=None):
    """Return (total_units, used_units) for a rack, excluding one device's
    current usage (used when editing that same device)."""
    rack = query_one("SELECT total_units FROM Rack WHERE rack_id = %s", (rack_id,))
    if rack is None:
        return None, None
    sql = (
        "SELECT COALESCE(SUM(rack_units), 0) AS used "
        "FROM Device WHERE rack_id = %s"
    )
    params = [rack_id]
    if exclude_device_id is not None:
        sql += " AND device_id != %s"
        params.append(exclude_device_id)
    used = query_one(sql, tuple(params))["used"]
    return rack["total_units"], used


def valid_device_form():
    hostname = request.form.get("hostname", "").strip()
    mac_address = request.form.get("mac_address", "").strip().upper()
    device_type = request.form.get("device_type", "").strip()
    rack_id_text = request.form.get("rack_id", "").strip()
    rack_units_text = request.form.get("rack_units", "").strip()
    if not hostname or not mac_address or not device_type:
        return None
    if not MAC_RE.match(mac_address):
        return None
    try:
        rack_id = int(rack_id_text) if rack_id_text else None
        rack_units = int(rack_units_text) if rack_units_text else None
    except ValueError:
        return None
    if rack_units is not None and rack_units <= 0:
        return None
    if rack_id is not None and rack_units is None:
        return None
    return hostname, mac_address, device_type, rack_units, rack_id


@bp.route("/")
@login_required
def list_devices():
    rows = query_all(
        "SELECT d.device_id, d.hostname, d.mac_address, d.device_type, d.rack_units, "
        "d.rack_id, r.rack_label, l.building, l.room "
        "FROM Device d LEFT JOIN Rack r ON d.rack_id = r.rack_id "
        "LEFT JOIN Location l ON r.location_id = l.location_id "
        "ORDER BY d.hostname"
    )
    return render_template("devices/list.html", devices=rows)


@bp.route("/new", methods=["GET", "POST"])
@role_required(ADMIN, ENGINEER)
def create_device():
    racks = get_racks()
    device = None
    if request.method == "POST":
        device = request.form
        values = valid_device_form()
        if values is None:
            flash("Hostname, MAC address, and device type are required. "
                  "MAC must look like AA:BB:CC:DD:EE:01, and rack units must be a positive number.", "error")
        else:
            _, _, _, rack_units, rack_id = values
            capacity_error = None
            if rack_id is not None:
                total_units, used_units = rack_space_left(rack_id)
                if total_units is not None and used_units + rack_units > total_units:
                    capacity_error = (
                        f"That rack only has {total_units - used_units}U free "
                        f"(of {total_units}U total); this device needs {rack_units}U."
                    )
            if capacity_error:
                flash(capacity_error, "error")
            else:
                try:
                    execute(
                        "INSERT INTO Device (hostname, mac_address, device_type, rack_units, rack_id) "
                        "VALUES (%s, %s, %s, %s, %s)", values,
                    )
                    flash("Device created.", "success")
                    return redirect(url_for("devices.list_devices"))
                except mysql.connector.Error as err:
                    flash(friendly_error(err), "error")
    return render_template("devices/form.html", device=device, racks=racks)


@bp.route("/<int:device_id>/edit", methods=["GET", "POST"])
@role_required(ADMIN, ENGINEER)
def edit_device(device_id):
    device = query_one(
        "SELECT device_id, hostname, mac_address, device_type, rack_units, rack_id "
        "FROM Device WHERE device_id = %s", (device_id,),
    )
    if device is None:
        abort(404)
    racks = get_racks()
    if request.method == "POST":
        values = valid_device_form()
        if values is None:
            flash("Hostname, MAC address, and device type are required. "
                  "MAC must look like AA:BB:CC:DD:EE:01, and rack units must be a positive number.", "error")
            device = {**request.form, "device_id": device_id}
        else:
            _, _, _, rack_units, rack_id = values
            capacity_error = None
            if rack_id is not None:
                total_units, used_units = rack_space_left(rack_id, exclude_device_id=device_id)
                if total_units is not None and used_units + rack_units > total_units:
                    capacity_error = (
                        f"That rack only has {total_units - used_units}U free "
                        f"(of {total_units}U total); this device needs {rack_units}U."
                    )
            if capacity_error:
                flash(capacity_error, "error")
                device = {**request.form, "device_id": device_id}
            else:
                try:
                    execute(
                        "UPDATE Device SET hostname = %s, mac_address = %s, device_type = %s, "
                        "rack_units = %s, rack_id = %s WHERE device_id = %s",
                        (*values, device_id),
                    )
                    flash("Device updated.", "success")
                    return redirect(url_for("devices.list_devices"))
                except mysql.connector.Error as err:
                    flash(friendly_error(err), "error")
                    device = {**request.form, "device_id": device_id}
    return render_template("devices/form.html", device=device, racks=racks)


@bp.route("/<int:device_id>/delete", methods=["POST"])
@role_required(ADMIN)
def delete_device(device_id):
    try:
        execute("DELETE FROM Device WHERE device_id = %s", (device_id,))
        flash("Device deleted. Its assigned IP addresses have been released.", "success")
    except mysql.connector.Error as err:
        flash(friendly_error(err), "error")
    return redirect(url_for("devices.list_devices"))