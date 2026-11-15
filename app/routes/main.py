from flask import Blueprint, render_template, session, redirect, url_for, flash, current_app, abort

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


@bp.route("/login")
def login():
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