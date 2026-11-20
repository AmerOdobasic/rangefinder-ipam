# RangeFinder (IPAM System)

COMP4150 – Advanced & Practical Database Systems   
Team: Amer, Marc, Muhib

## Requirements

- MySQL 8.4 LTS (make sure your local setup is up to date). Do this to check:
  ```sql
  SELECT VERSION();
  ```
- You can use MySQL Workbench, the CLI client, or whatever database tool you want.

## What all the files are:

Everything is broken down inside `sql/` so we don't step on each others toes:

- `sql/01_schema.sql` – has tables, primary/foreign keys, constraints, and indexes
- `sql/02_triggers.sql` – checks for rules
- `sql/03_procedures.sql` – Stored procedures
- `sql/04_views.sql` – reporting views
- `sql/05_seed.sql` – Mock records and test data
- `sql/06_queries.sql` – Demo and test queries. **Not part of the build.** Some tests are meant to give errors, so run it block by block, or with `mysql --force`. These tests commit internally and clean up with DELETE statements
- `sql/07_roles.sql` – Users, role groups, and GRANT statements
- `build_all.sql` – Runner script that builds everything cleanly

## How to Build the DB

Whenever you pull changes or want to test your script from a clean slate, run this from the project root:

```bash
mysql -u root -p -e "source build_all.sql"
```

This works in bash and PowerShell. (`mysql -u root -p < build_all.sql` only works in bash, not PowerShell.) You can also open the mysql terminal and run `source build_all.sql`.

The script drops and recreates `rangefinder` from scratch every time, so feel free to run it whenever you need to start fresh...

The seed uses session variables (like `@loc_windsor`), so run `05_seed.sql` only through `build_all.sql`, never on its own.

## Who's doing what:

- `01_schema.sql` – Shared (say on discord when you have made changes!)
- `02_triggers.sql` – Amer
- `03_procedures.sql` & `04_views.sql` – Marc
- `05_seed.sql` & `06_queries.sql` – Amer + Marc
- `07_roles.sql` – Muhib

## Ground Rules

- Stick to the files you own. If you need something changed in someone else's file, let them know on Discord
- `git pull` before you start and before you push. Remember to commit small, with a clear message for them to let everyone else know what you've done
- Any time `01_schema.sql` gets changed, keep a quick note of what changed so we can drop it straight into the Step 4 "Changes from Previous Submission" section.
- Make sure that `.env` contains nothing thats actually sensitive

## Running the GUI (Step 5)

1. Rebuild the database (this wipes any data created in the GUI):

   `mysql -u root -p -e "source build_all.sql"`
2. Copy `.env.example` to `.env`. Set `SECRET_KEY` using:

   `python -c "import secrets; print(secrets.token_hex(32))"`
   and set the `DB_*_PASSWORD` values from `sql/07_roles.sql`.
3. Create and activate a virtual environment, then install dependencies:
   `python -m venv venv`, activate it, then `pip install -r requirements.txt`
4. Start the app: `flask --app app run`, then open http://127.0.0.1:5000
5. Demo logins: see Section 6 of the Step 5 document (netadmin, syseng, auditor).