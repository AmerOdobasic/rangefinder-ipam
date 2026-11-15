import os
import importlib
import pkgutil
from flask import Flask, session, render_template
from .db import close_db
from . import routes


def create_app():
    app = Flask(__name__)
    app.secret_key = os.getenv("SECRET_KEY")
    if not app.secret_key:
        raise RuntimeError("The SECRET_KEY is missing. Please copy .env.example to .env and set it...")

    app.teardown_appcontext(close_db)

    # Auto-register every blueprint found in app/routes/
    for mod in pkgutil.iter_modules(routes.__path__):
        module = importlib.import_module(f"{routes.__name__}.{mod.name}")
        if hasattr(module, "bp"):
            app.register_blueprint(module.bp)

    @app.context_processor
    def inject_roles():
        role = session.get("role")
        return {
            "role": role,
            "is_admin": role == "Network Administrator",
            "is_engineer": role == "Systems Engineer",
            "is_auditor": role == "Read-Only Auditor",
        }

    @app.errorhandler(403)
    def forbidden(e):
        return render_template("403.html"), 403

    return app