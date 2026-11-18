import mysql.connector
from flask import Blueprint, render_template, request, redirect, url_for, flash, abort
from ..db import query_all, query_one, execute
from ..auth import login_required, role_required
from ..errors import friendly_error

bp = Blueprint("vlans", __name__, url_prefix="/vlans")
ADMIN = "Network Administrator"


def valid_vlan_form():
    try:
        vlan_id = int(request.form.get("vlan_id", ""))
    except ValueError:
        return None
    name = request.form.get("vlan_name", "").strip()
    if not 1 <= vlan_id <= 4094 or not name:
        return None
    return vlan_id, name, request.form.get("description", "").strip()


@bp.route("/")
@login_required
def list_vlans():
    rows = query_all("SELECT vlan_id, vlan_name, description FROM VLAN ORDER BY vlan_id")
    return render_template("vlans/list.html", vlans=rows)


@bp.route("/new", methods=["GET", "POST"])
@role_required(ADMIN)
def create_vlan():
    vlan = None
    if request.method == "POST":
        vlan = request.form
        values = valid_vlan_form()
        if values is None:
            flash("Enter a VLAN ID from 1 to 4094 and a VLAN name.", "error")
        else:
            try:
                execute(
                    "INSERT INTO VLAN (vlan_id, vlan_name, description) VALUES (%s, %s, %s)",
                    values,
                )
                flash("VLAN created.", "success")
                return redirect(url_for("vlans.list_vlans"))
            except mysql.connector.Error as err:
                flash(friendly_error(err), "error")
    return render_template("vlans/form.html", vlan=vlan)


@bp.route("/<int:vlan_id>/edit", methods=["GET", "POST"])
@role_required(ADMIN)
def edit_vlan(vlan_id):
    vlan = query_one(
        "SELECT vlan_id, vlan_name, description FROM VLAN WHERE vlan_id = %s", (vlan_id,)
    )
    if vlan is None:
        abort(404)
    if request.method == "POST":
        values = valid_vlan_form()
        if values is None:
            flash("Enter a VLAN ID from 1 to 4094 and a VLAN name.", "error")
            vlan = {**request.form, "original_vlan_id": vlan_id}
        else:
            try:
                execute(
                    "UPDATE VLAN SET vlan_id = %s, vlan_name = %s, description = %s WHERE vlan_id = %s",
                    (*values, vlan_id),
                )
                flash("VLAN updated.", "success")
                return redirect(url_for("vlans.list_vlans"))
            except mysql.connector.Error as err:
                flash(friendly_error(err), "error")
                vlan = {**request.form, "original_vlan_id": vlan_id}
    return render_template("vlans/form.html", vlan=vlan)


@bp.route("/<int:vlan_id>/delete", methods=["POST"])
@role_required(ADMIN)
def delete_vlan(vlan_id):
    try:
        execute("DELETE FROM VLAN WHERE vlan_id = %s", (vlan_id,))
        flash("VLAN deleted.", "success")
    except mysql.connector.Error as err:
        flash(friendly_error(err), "error")
    return redirect(url_for("vlans.list_vlans"))
