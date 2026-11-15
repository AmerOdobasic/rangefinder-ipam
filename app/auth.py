from functools import wraps
from flask import session, redirect, url_for, flash, abort

def login_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if "role" not in session:
            flash("Please log in first...", "warning")
            return redirect(url_for("main.login"))
        return view(*args, **kwargs)
    return wrapped


def role_required(*allowed_roles):
    def decorator(view):
        @wraps(view)
        def wrapped(*args, **kwargs):
            if "role" not in session:
                flash("Please log in first...", "warning")
                return redirect(url_for("main.login"))
            if session["role"] not in allowed_roles:
                abort(403)
            return view(*args, **kwargs)
        return wrapped
    return decorator