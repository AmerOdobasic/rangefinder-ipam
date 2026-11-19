import re
import mysql.connector
from flask import Blueprint, render_template, request, redirect, url_for, flash
from ..db import query_all, query_one, call_proc
from ..auth import login_required, role_required
from ..errors import friendly_error

bp = Blueprint("ips", __name__, url_prefix="/ips")
ADMIN = "Network Administrator"
ENGINEER = "Systems Engineer"

MAC_RE = re.compile(r"^([0-9A-F]{2}:){5}[0-9A-F]{2}$")
STATUSES = ("available", "assigned", "reserved")


@bp.route("/")
@login_required
def list_ips():
    subnets = query_all("SELECT subnet_id, cidr_block FROM Subnet ORDER BY INET_ATON(network_address)")
    subnet_id = request.args.get("subnet_id", type=int) or (subnets[0]["subnet_id"] if subnets else None)
    status = request.args.get("status", "")
    ips, summary = [], None
    if subnet_id is not None:
        summary = query_one("SELECT * FROM v_subnet_utilization WHERE subnet_id = %s", (subnet_id,))
        sql = ("SELECT i.ip_address, i.status, d.hostname, d.mac_address "
               "FROM IP_Address i LEFT JOIN Device d ON d.device_id = i.device_id "
               "WHERE i.subnet_id = %s")
        params = [subnet_id]
        if status in STATUSES:
            sql += " AND i.status = %s"
            params.append(status)
        sql += " ORDER BY INET_ATON(i.ip_address)"
        ips = query_all(sql, tuple(params))
    return render_template("ips/list.html", subnets=subnets, subnet_id=subnet_id, status=status,
                           summary=summary, ips=ips, statuses=STATUSES)


@bp.route("/request", methods=["GET", "POST"])
@role_required(ADMIN, ENGINEER)
def request_ip():
    subnets = query_all("SELECT subnet_id, cidr_block FROM Subnet ORDER BY INET_ATON(network_address)")
    racks = query_all("SELECT rack_id, rack_label FROM Rack ORDER BY rack_label")
    form = request.form if request.method == "POST" else {"subnet_id": request.args.get("subnet_id", "")}
    if request.method == "POST":
        hostname = request.form.get("hostname", "").strip()
        mac = request.form.get("mac", "").strip().upper()
        device_type = request.form.get("device_type", "").strip() or None
        problem = None
        try:
            subnet_id = int(request.form.get("subnet_id", ""))
            rack_id = int(request.form["rack_id"]) if request.form.get("rack_id", "").strip() else None
            rack_units = int(request.form["rack_units"]) if request.form.get("rack_units", "").strip() else None
        except ValueError:
            problem = "Subnet, rack and rack units must be picked or typed as numbers."
        if not problem and (not hostname or not mac):
            problem = "Hostname and MAC address are required."
        elif not problem and not MAC_RE.match(mac):
            problem = "MAC address must look like AA:BB:CC:DD:EE:01."
        elif not problem and not device_type:
            problem = "Device type is required."
        elif not problem and rack_id is not None and (rack_units is None or rack_units < 1):
            problem = "Rack units (1 or more) are required when a rack is chosen."
        if problem:
            flash(problem, "error")
        else:
            if rack_id is None:
                rack_units = None      # not rack-mounted
            try:
                result = call_proc("sp_request_static_ip",
                                   (subnet_id, hostname, mac, device_type, rack_id, rack_units))
                flash(f"Assigned {result[0]['assigned_ip']} to {hostname} "
                      f"(device #{result[0]['device_id']}).", "success")
                return redirect(url_for("ips.list_ips", subnet_id=subnet_id))
            except mysql.connector.Error as err:
                flash(friendly_error(err), "error")
    return render_template("ips/request.html", subnets=subnets, racks=racks, form=form)


@bp.route("/release", methods=["GET", "POST"])
@role_required(ADMIN, ENGINEER)
def release_ips():
    if request.method == "POST":
        try:
            device_id = int(request.form.get("device_id", ""))
        except ValueError:
            flash("Pick a device from the list.", "error")
        else:
            try:
                result = call_proc("sp_release_device_ips", (device_id,))
                flash(f"Released {result[0]['ips_released']} IP address(es) from device #{device_id}.", "success")
                return redirect(url_for("ips.release_ips"))
            except mysql.connector.Error as err:
                flash(friendly_error(err), "error")
    devices = query_all(
        "SELECT d.device_id, d.hostname, COUNT(i.ip_id) AS ip_count "
        "FROM Device d LEFT JOIN IP_Address i ON i.device_id = d.device_id "
        "GROUP BY d.device_id, d.hostname ORDER BY d.hostname"
    )
    return render_template("ips/release.html", devices=devices)