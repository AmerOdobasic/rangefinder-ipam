import re
import mysql.connector
from flask import Blueprint, render_template, request, redirect, url_for, flash, abort
from ..db import query_all, query_one, execute, call_proc
from ..auth import login_required, role_required
from ..errors import friendly_error

bp = Blueprint("subnets", __name__, url_prefix="/subnets")
ADMIN = "Network Administrator"
ENGINEER = "Systems Engineer"

CIDR_RE = re.compile(r"^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})/(\d{1,2})$")


def opt_int(name):
    """Form field -> int, or None when blank. Raises ValueError on junk."""
    value = request.form.get(name, "").strip()
    return int(value) if value else None


def lookups():
    vlans = query_all("SELECT vlan_id, vlan_name FROM VLAN ORDER BY vlan_id")
    locations = query_all("SELECT location_id, building, room FROM Location ORDER BY building, room")
    return vlans, locations


def validate_cidr(cidr):
    """Returns an error message, or None when the CIDR is fine."""
    m = CIDR_RE.match(cidr)
    if not m or any(int(x) > 255 for x in m.groups()[:4]):
        return "Enter a valid CIDR block such as 10.3.0.0/24."
    if not 16 <= int(m.group(5)) <= 30:
        return "Prefix length must be between /16 and /30."
    return None


def render_form(subnet, form=None):
    vlans, locations = lookups()
    return render_template("subnets/form.html", subnet=subnet, form=form or {},
                           vlans=vlans, locations=locations)


@bp.route("/")
@login_required
def list_subnets():
    rows = query_all(
        "SELECT s.subnet_id, s.cidr_block, s.vlan_id, v.vlan_name, "
        "       l.building, l.room, "
        "       u.total_ips, u.assigned_ips, u.available_ips, u.percent_available "
        "FROM Subnet s "
        "LEFT JOIN VLAN v ON v.vlan_id = s.vlan_id "
        "LEFT JOIN Location l ON l.location_id = s.location_id "
        "LEFT JOIN v_subnet_utilization u ON u.subnet_id = s.subnet_id "
        "ORDER BY INET_ATON(s.network_address)"
    )
    return render_template("subnets/list.html", subnets=rows)


@bp.route("/new", methods=["GET", "POST"])
@role_required(ADMIN)
def create_subnet():
    if request.method == "POST":
        cidr = request.form.get("cidr_block", "").strip()
        problem = validate_cidr(cidr) if cidr else "CIDR block is required."
        try:
            vlan_id, location_id = opt_int("vlan_id"), opt_int("location_id")
        except ValueError:
            problem = problem or "VLAN and location must be picked from the lists."
        if problem:
            flash(problem, "error")
            return render_form(None, request.form)
        try:
            subnet_id = execute(
                "INSERT INTO Subnet (cidr_block, vlan_id, location_id) VALUES (%s, %s, %s)",
                (cidr, vlan_id, location_id),
            )
        except mysql.connector.Error as err:   # overlap trigger, bad CIDR, FK...
            flash(friendly_error(err), "error")
            return render_form(None, request.form)
        try:
            info = call_proc("sp_generate_ips", (subnet_id,))
        except mysql.connector.Error as err:
            # Do not leave a subnet behind that has no IP rows
            try:
                execute("DELETE FROM Subnet WHERE subnet_id = %s", (subnet_id,))
            except mysql.connector.Error:
                pass
            flash(friendly_error(err), "error")
            return render_form(None, request.form)
        flash(f"Subnet {cidr} created with {info[0]['total_ips_created']} IP rows "
              f"({info[0]['usable_ips']} usable).", "success")
        return redirect(url_for("ips.list_ips", subnet_id=subnet_id))
    return render_form(None)


@bp.route("/<int:subnet_id>/edit", methods=["GET", "POST"])
@role_required(ADMIN)
def edit_subnet(subnet_id):
    subnet = query_one("SELECT subnet_id, cidr_block, vlan_id, location_id FROM Subnet "
                       "WHERE subnet_id = %s", (subnet_id,))
    if subnet is None:
        abort(404)
    if request.method == "POST":
        # The CIDR itself is not editable: its IP rows were generated from it.
        try:
            vlan_id, location_id = opt_int("vlan_id"), opt_int("location_id")
        except ValueError:
            flash("VLAN and location must be picked from the lists.", "error")
            return render_form(subnet, request.form)
        try:
            execute("UPDATE Subnet SET vlan_id = %s, location_id = %s WHERE subnet_id = %s",
                    (vlan_id, location_id, subnet_id))
            flash("Subnet updated.", "success")
            return redirect(url_for("subnets.list_subnets"))
        except mysql.connector.Error as err:
            flash(friendly_error(err), "error")
            return render_form(subnet, request.form)
    return render_form(subnet)


@bp.route("/<int:subnet_id>/delete", methods=["POST"])
@role_required(ADMIN)
def delete_subnet(subnet_id):
    try:
        execute("DELETE FROM Subnet WHERE subnet_id = %s", (subnet_id,))
        flash("Subnet deleted.", "success")
    except mysql.connector.Error as err:
        flash(friendly_error(err), "error")
    return redirect(url_for("subnets.list_subnets"))