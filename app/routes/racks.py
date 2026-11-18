import mysql.connector
from flask import Blueprint, render_template, request, redirect, url_for, flash, abort
from ..db import query_all, query_one, execute
from ..auth import login_required, role_required
from ..errors import friendly_error

bp = Blueprint("racks", __name__, url_prefix="/racks")
ADMIN = "Network Administrator"


def get_locations():
    return query_all("SELECT location_id, building, room FROM Location ORDER BY building, room")


def valid_rack_form():
    try:
        location_id = int(request.form.get("location_id", ""))
        total_units = int(request.form.get("total_units", "42"))
    except ValueError:
        return None
    if not request.form.get("rack_label", "").strip() or total_units <= 0:
        return None
    return location_id, request.form["rack_label"].strip(), total_units


@bp.route("/")
@login_required
def list_racks():
    rows = query_all(
        "SELECT r.rack_id, r.rack_label, r.total_units, r.location_id, "
        "l.building, l.room "
        "FROM Rack r JOIN Location l ON r.location_id = l.location_id "
        "ORDER BY l.building, l.room, r.rack_label"
    )
    return render_template("racks/list.html", racks=rows)


@bp.route("/new", methods=["GET", "POST"])
@role_required(ADMIN)
def create_rack():
    locations = get_locations()
    rack = None
    if request.method == "POST":
        rack = request.form
        values = valid_rack_form()
        if values is None:
            flash("Choose a location, enter a rack label, and use a positive number of units.", "error")
        else:
            try:
                execute(
                    "INSERT INTO Rack (location_id, rack_label, total_units) VALUES (%s, %s, %s)",
                    values,
                )
                flash("Rack created.", "success")
                return redirect(url_for("racks.list_racks"))
            except mysql.connector.Error as err:
                flash(friendly_error(err), "error")
    return render_template("racks/form.html", rack=rack, locations=locations)


@bp.route("/<int:rack_id>/edit", methods=["GET", "POST"])
@role_required(ADMIN)
def edit_rack(rack_id):
    rack = query_one(
        "SELECT rack_id, location_id, rack_label, total_units FROM Rack WHERE rack_id = %s",
        (rack_id,),
    )
    if rack is None:
        abort(404)
    locations = get_locations()
    if request.method == "POST":
        values = valid_rack_form()
        if values is None:
            flash("Choose a location, enter a rack label, and use a positive number of units.", "error")
            rack = {**request.form, "rack_id": rack_id}
        else:
            try:
                execute(
                    "UPDATE Rack SET location_id = %s, rack_label = %s, total_units = %s WHERE rack_id = %s",
                    (*values, rack_id),
                )
                flash("Rack updated.", "success")
                return redirect(url_for("racks.list_racks"))
            except mysql.connector.Error as err:
                flash(friendly_error(err), "error")
                rack = {**request.form, "rack_id": rack_id}
    return render_template("racks/form.html", rack=rack, locations=locations)


@bp.route("/<int:rack_id>/delete", methods=["POST"])
@role_required(ADMIN)
def delete_rack(rack_id):
    try:
        execute("DELETE FROM Rack WHERE rack_id = %s", (rack_id,))
        flash("Rack deleted. Devices assigned to it are now unassigned.", "success")
    except mysql.connector.Error as err:
        flash(friendly_error(err), "error")
    return redirect(url_for("racks.list_racks"))
