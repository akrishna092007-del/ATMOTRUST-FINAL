"""Create public local demo accounts matching the credentials shown on the login page."""
import os
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))
from app.data import PreparedSource
from app.operations import Operations

DEMO_PASSWORDS = {
    "authority": "vH3z-6bUCpM2045E_9QmeQ3b",
    "employee": "TmarU5EnllNDsqe-lzujz7XL",
}


def main():
    path = Path(os.getenv("ATMOTRUST_DATABASE_PATH", str(ROOT / "backend/atmotrust.sqlite3")))
    if not path.is_absolute():
        path = ROOT / path
    path.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(path)
    ops = Operations(db, PreparedSource().stations)
    for username, name, role in (("authority", "Authority Operator", "authority"), ("employee", "Maintenance Employee", "employee")):
        if any(user["username"] == username for user in ops.users()):
            print(f"{username}: already exists; no password changed")
            continue
        password = DEMO_PASSWORDS[role]
        user = ops.create_user(username, name, role, password)
        if role == "employee":
            for station in ops.stations():
                ops.assign(user["id"], station["station_id"])
        print(f"{role} login: {username} / {password}")
    print("Demo credentials are public and displayed on the login page.")


if __name__ == "__main__":
    main()
