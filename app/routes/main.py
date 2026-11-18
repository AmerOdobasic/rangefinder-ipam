from flask import Blueprint, render_template, request, session, redirect, url_for, flash, current_app, abort
from werkzeug.security import check_password_hash
from ..db import query_one

bp = Blueprint("main", __name__)

DEV_ROLES = {
    "admin": "Network Administrator",
    "engineer": "Systems Engineer",
    "auditor": "Read-Only Auditor",
}


@bp.route("/")
def index():
    if "role" not in session:
        return redirect(url_for("main.login"))
    return render_template("index.html")


@bp.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = request.form["username"].strip()
        password = request.form["password"]
        user = query_one(
            "SELECT username, password_hash, role FROM User_Account WHERE username = %s",
            (username,),
        )
        if user and check_password_hash(user["password_hash"], password):
            session.clear()
            session["username"] = user["username"]
            session["role"] = user["role"]
            return redirect(url_for("main.index"))
        flash("Invalid username and/or password...", "error")
    return render_template("login.html")


@bp.route("/logout")
def logout():
    session.clear()
    flash("Logged out.", "success")
    return redirect(url_for("main.login"))

# TODO: makes sure that this is removed before submisson since this allows anyone to log in as any role by just clicking the URL
@bp.route("/dev-login/<key>")
def dev_login(key):
    if not current_app.debug or key not in DEV_ROLES:
        abort(404)
    session["role"] = DEV_ROLES[key]
    session["username"] = f"dev-{key}"
    return redirect(url_for("main.index"))