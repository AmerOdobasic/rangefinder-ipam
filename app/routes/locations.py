import mysql.connector
from flask import Blueprint, render_template, request, redirect, url_for, flash, abort
from ..db import query_all, query_one, execute
from ..auth import login_required, role_required
from ..errors import friendly_error

bp = Blueprint("locations", __name__, url_prefix="/locations")
ADMIN = "Network Administrator"


def missing_required():
    # This is True only if the building or room is blank once spaces are trimmed
    return not request.form["building"].strip() or not request.form["room"].strip()

@bp.route("/")
@login_required
def list_locations():
    rows = query_all(
        "SELECT location_id, building, room, description "
        "FROM Location ORDER BY building, room"
    )
    return render_template("locations/list.html", locations=rows)


@bp.route("/new", methods=["GET", "POST"])
@role_required(ADMIN)
def create_location():
    location = None
    if request.method == "POST":
        location = request.form
        if missing_required():
            flash("Building and room are required...", "error")
            return render_template("locations/form.html", location=location)
        try:
            execute(
                "INSERT INTO Location (building, room, description) VALUES (%s, %s, %s)",
                (request.form["building"].strip(), request.form["room"].strip(),
                 request.form["description"].strip()),
            )
            flash("Location created.", "success")
            return redirect(url_for("locations.list_locations"))
        except mysql.connector.Error as err:
            flash(friendly_error(err), "error")
    return render_template("locations/form.html", location=location)


@bp.route("/<int:location_id>/edit", methods=["GET", "POST"])
@role_required(ADMIN)
def edit_location(location_id):
    location = query_one(
        "SELECT location_id, building, room, description FROM Location WHERE location_id = %s",
        (location_id,),
    )
    if location is None:
        abort(404)
    if request.method == "POST":
        if missing_required():
            flash("Building and room are required.", "error")
            return render_template("locations/form.html", location={**request.form, "location_id": location_id})
        try:
            execute(
                "UPDATE Location SET building = %s, room = %s, description = %s "
                "WHERE location_id = %s",
                (request.form["building"].strip(), request.form["room"].strip(), request.form["description"].strip(), location_id),
            )
            flash("Location updated.", "success")
            return redirect(url_for("locations.list_locations"))
        except mysql.connector.Error as err:
            flash(friendly_error(err), "error")
            location = {**request.form, "location_id": location_id}
    return render_template("locations/form.html", location=location)


@bp.route("/<int:location_id>/delete", methods=["POST"])
@role_required(ADMIN)
def delete_location(location_id):
    try:
        execute("DELETE FROM Location WHERE location_id = %s", (location_id,))
        flash("Location deleted.", "success")
    except mysql.connector.Error as err:
        flash(friendly_error(err), "error")
    return redirect(url_for("locations.list_locations"))