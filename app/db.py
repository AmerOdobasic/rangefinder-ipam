import os
import mysql.connector
from flask import g, session
from dotenv import load_dotenv

load_dotenv()

ROLE_TO_PREFIX = {
    "Network Administrator": "ADMIN",
    "Systems Engineer": "ENGINEER",
    "Read-Only Auditor": "AUDITOR",
}

def connect_as(role):
    prefix = ROLE_TO_PREFIX[role]
    return mysql.connector.connect(
        host=os.getenv("DB_HOST", "localhost"),
        database=os.getenv("DB_NAME", "rangefinder"),
        user=os.getenv(f"DB_{prefix}_USER"),
        password=os.getenv(f"DB_{prefix}_PASSWORD"),
    )

def get_db():
    if "db" not in g:
        role = session.get("role", "Read-Only Auditor")
        g.db = connect_as(role)
    return g.db

def close_db(e=None):
    db = g.pop("db", None)
    if db is not None:
        db.close()

def query_all(sql, params=()):
    cur = get_db().cursor(dictionary=True)
    try:
        cur.execute(sql, params)
        return cur.fetchall()
    finally:
        cur.close()


def query_one(sql, params=()):
    rows = query_all(sql, params)
    return rows[0] if rows else None


def execute(sql, params=()):
    db = get_db()
    cur = db.cursor()
    try:
        cur.execute(sql, params)
        db.commit()
        return cur.lastrowid
    except Exception:
        db.rollback()
        raise
    finally:
        cur.close()


def call_proc(name, args=()):
    cur = get_db().cursor()
    try:
        cur.callproc(name, args)
        results = []
        for result in cur.stored_results():
            cols = result.column_names
            results.extend(dict(zip(cols, row)) for row in result.fetchall())
        return results
    finally:
        cur.close()