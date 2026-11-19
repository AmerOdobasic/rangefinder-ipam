import mysql.connector
from flask import Blueprint, render_template, flash
from ..db import query_all
from ..auth import login_required
from ..errors import friendly_error

bp = Blueprint("dashboard", __name__, url_prefix="/dashboard")


@bp.route("/")
@login_required
def show_dashboard():
    try:
        data = dict(
            subnets=query_all("SELECT * FROM v_subnet_utilization ORDER BY subnet_id"),
            vlans=query_all("SELECT * FROM v_vlan_utilization ORDER BY vlan_id"),
            racks=query_all("SELECT * FROM v_rack_space ORDER BY rack_label"),
            locations=query_all("SELECT * FROM v_location_rack_space ORDER BY building, room"),
        )
    except mysql.connector.Error as err:
        flash(friendly_error(err), "error")
        data = dict(subnets=[], vlans=[], racks=[], locations=[])
    return render_template("dashboard/dashboard.html", **data)