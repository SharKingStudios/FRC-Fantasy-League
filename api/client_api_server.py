#!/usr/bin/env python3
import os
import csv
import json
import random
import time
from flask import Flask, request, send_file, send_from_directory, jsonify, Response, redirect
from waitress import serve
from werkzeug.utils import secure_filename

app = Flask(__name__)

# ------------------------------------------------------------------------------
# Configuration / Setup
# ------------------------------------------------------------------------------
CARDS_FOLDER = "./robotCards"
IMAGES_FOLDER = "./images/robotImages"
USERS_CSV = "users.csv"
JOBS_CSV = "jobs.csv"
TEAMS_CSV = "teams.csv"

# Ensure folders exist
os.makedirs(CARDS_FOLDER, exist_ok=True)
os.makedirs(IMAGES_FOLDER, exist_ok=True)

# Ensure users.csv has a proper header if it doesn't exist
if not os.path.isfile(USERS_CSV):
    with open(USERS_CSV, "w", newline="") as f:
        f.write("username,password_hash,session_token,cards_owned,money\n")

# Ensure jobs.csv has a proper header if it doesn't exist
if not os.path.isfile(JOBS_CSV):
    with open(JOBS_CSV, "w", newline="") as f:
        f.write("job_id,job_type,status,job_data\n")

# ------------------------------------------------------------------------------
# CSV Utilities
# ------------------------------------------------------------------------------
def read_csv(filename):
    """ Reads a CSV into a list[dict], inferring headers from the first row. """
    if not os.path.isfile(filename):
        return [], []
    with open(filename, "r", newline="", encoding="utf-8") as f:
        lines = list(csv.reader(f))
        if len(lines) < 1:
            return [], []
        headers = lines[0]
        rows = []
        for line in lines[1:]:
            row_dict = {}
            for idx, h in enumerate(headers):
                row_dict[h] = line[idx] if idx < len(line) else ""
            rows.append(row_dict)
        return rows, headers

def write_csv(filename, rows, headers):
    """ Writes list[dict] to CSV, ensuring the exact same headers. """
    with open(filename, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(headers)
        for row in rows:
            line = []
            for h in headers:
                line.append(row.get(h, ""))
            writer.writerow(line)

# ------------------------------------------------------------------------------
# Jobs CSV + create_job
# ------------------------------------------------------------------------------
def read_jobs_csv():
    return read_csv(JOBS_CSV)

def write_jobs_csv(rows, headers):
    write_csv(JOBS_CSV, rows, headers)

def create_job(job_type, job_data_dict=None, retry_count=0):
    """ Utility: create a new job row in jobs.csv. """
    if job_data_dict is None:
        job_data_dict = {}

    team_number = job_data_dict.get("team_number", "N/A")
    print(f"Creating new job: {job_type} for team number: {team_number}")

    rows, headers = read_jobs_csv()

    # Ensure columns exist
    needed = ["job_id", "job_type", "status", "job_data", "created_at", "done_at", "retry_count"]
    for col in needed:
        if col not in headers:
            headers.append(col)

    # Generate unique job_id
    used_ids = {r["job_id"] for r in rows}
    job_id = ""
    while True:
        job_id = str(random.randint(100000, 999999))
        if job_id not in used_ids:
            break

    new_job = {
        "job_id": job_id,
        "job_type": job_type,
        "status": "queued",
        "job_data": json.dumps(job_data_dict),
        "created_at": str(int(time.time())),
        "done_at": "",
        "retry_count": str(retry_count),
    }
    rows.append(new_job)
    write_jobs_csv(rows, headers)

    print(f"Job created with ID: {job_id} for team number: {team_number}")
    return job_id


# ------------------------------------------------------------------------------
# Teams CSV Helpers
# ------------------------------------------------------------------------------
def get_ranked_teams():
    rows, headers = read_csv(TEAMS_CSV)
    if len(rows) == 0:
        return []
    # Sort by rank ascending
    def sort_key(r):
        try:
            return int(r.get("rank", 999999))
        except:
            return 999999
    rows.sort(key=sort_key)
    return rows

# ------------------------------------------------------------------------------
# Users CSV Helpers
# ------------------------------------------------------------------------------
def read_users_csv():
    return read_csv(USERS_CSV)

def write_users_csv(rows, headers):
    write_csv(USERS_CSV, rows, headers)

def simple_hash(s):
    """Trivial hash function (not secure!)"""
    return str(sum(s.encode("utf-8")) % 65535)

def find_user_by_token(token):
    """Return (user_dict, all_rows, headers) if found, else (None, all_rows, headers)."""
    all_rows, all_headers = read_users_csv()
    for r in all_rows:
        if r["session_token"] == token:
            return (r, all_rows, all_headers)
    return (None, all_rows, all_headers)


# ------------------------------------------------------------------------------
# ROUTES
# ------------------------------------------------------------------------------
@app.route("/api/teams", methods=["GET"])
def api_teams():
    """Return the list of teams in sorted order (by rank)."""
    teams = get_ranked_teams()
    return jsonify(teams)

@app.route("/api/teams/<int:team_number>", methods=["POST"])
def api_teams_update(team_number):
    """Create job => updateOneCard for a specific team."""
    job_id = create_job("updateOneCard", {"team_number": str(team_number)})
    if job_id:
        return Response("Team data saved.\n", status=200)
    return Response("Failed to fetch team data.\n", status=400)

@app.route("/api/teams.csv", methods=["GET"])
def api_teams_csv():
    """Serve teams.csv directly."""
    if not os.path.isfile(TEAMS_CSV):
        return Response("Not Found.\n", status=404)
    return send_file(TEAMS_CSV, mimetype="text/csv")

# Serve Robot Card Images => GET /api/robotCards/<filename.png>
@app.route("/api/robotCards/<path:filename>", methods=["GET"])
def robot_cards(filename):
    file_path = os.path.join(CARDS_FOLDER, filename)
    if not os.path.isfile(file_path):
        return Response("Not Found\n", status=404)
    return send_from_directory(CARDS_FOLDER, filename)

# ------------------------------------------------------------------------------
# CREATE ASYNC JOBS
# ------------------------------------------------------------------------------
@app.route("/api/admin/asyncUpdateAllCards", methods=["POST"])
def api_async_update_all_cards():
    job_id = create_job("updateAllCards", {})
    return jsonify({"status": "accepted", "job_id": job_id}), 202

@app.route("/api/admin/asyncUpdateCard/<int:tnum>", methods=["POST"])
def api_async_update_card(tnum):
    job_id = create_job("updateOneCard", {"team_number": str(tnum)})
    return jsonify({"status": "accepted", "job_id": job_id}), 202

# ------------------------------------------------------------------------------
# Check Job Status
# ------------------------------------------------------------------------------
@app.route("/api/admin/jobStatus/<job_id>", methods=["GET"])
def api_job_status(job_id):
    rows, headers = read_jobs_csv()
    for row in rows:
        if row["job_id"] == job_id:
            status = row["status"]
            created_at = int(row.get("created_at", 0))
            done_at = int(row.get("done_at", 0))

            if status in ["queued", "running"]:
                run_time = int(time.time()) - created_at
                return jsonify({"status": "running", "run_time": run_time}), 200
            elif status == "OK":
                detail = row.get("job_data", "")
                # You could parse detail if needed
                run_time = done_at - created_at if done_at > 0 else int(time.time()) - created_at
                return jsonify({"status": "OK", "detail": detail, "run_time": run_time}), 200
            elif status == "ERROR":
                detail = row.get("job_data", "")
                run_time = done_at - created_at if done_at > 0 else int(time.time()) - created_at
                return jsonify({"status": "ERROR", "detail": detail, "run_time": run_time}), 200
            else:
                run_time = int(time.time()) - created_at
                return jsonify({"status": status, "run_time": run_time}), 200
    return Response("Invalid job id.\n", status=404)

# ------------------------------------------------------------------------------
# The Big Kahuna: Uploading an image file
# ------------------------------------------------------------------------------
@app.route("/api/admin/uploadRobotImage", methods=["POST"])
def api_upload_robot_image():
    """
    Expects a multipart/form-data with fields:
      - teamNumber
      - robotImage (file)
    """
    if "teamNumber" not in request.form or "robotImage" not in request.files:
        return Response("Missing teamNumber or robotImage.\n", status=400)

    team_number = request.form["teamNumber"].strip()
    file = request.files["robotImage"]
    filename = secure_filename(file.filename or "")
    if not filename:
        return Response("No filename provided.\n", status=400)

    # Only accept png or jpeg
    ext_lower = os.path.splitext(filename)[1].lower()
    if ext_lower not in [".png", ".jpg", ".jpeg"]:
        return Response("Only .png or .jpeg files are supported.\n", status=400)

    # Save to images/robotImages
    if ext_lower == ".jpg":
        ext_lower = ".jpeg"  # unify .jpg => .jpeg
    output_path = os.path.join(IMAGES_FOLDER, f"{team_number}{ext_lower}")
    file.save(output_path)

    # Create job => "updateOneCard"
    create_job("updateOneCard", {"team_number": team_number})
    return Response(f"File uploaded successfully as {output_path}\n", status=200)

# ------------------------------------------------------------------------------
# GET /api/admin/jobs.csv => return jobs.csv
# ------------------------------------------------------------------------------
@app.route("/api/admin/jobs.csv", methods=["GET"])
def api_jobs_csv():
    if not os.path.isfile(JOBS_CSV):
        return Response("Not Found.\n", status=404)
    return send_file(JOBS_CSV, mimetype="text/csv")

# ------------------------------------------------------------------------------
# POST /api/admin/updateTeamsCSV => update teams.csv with JSON body
# ------------------------------------------------------------------------------
@app.route("/api/admin/updateTeamsCSV", methods=["POST"])
def api_update_teams_csv():
    """
    Expects JSON body:
      {
        "updatedRows": [ { "team_number":"XYZ", ... }, ... ],
        "headers": ["team_number","city",...]
      }
    """
    data = request.json
    if not data or "updatedRows" not in data or "headers" not in data:
        return jsonify({"error": "Invalid request format"}), 400

    updated_rows = data["updatedRows"]
    new_headers = data["headers"]

    # read existing
    rows, headers = read_csv(TEAMS_CSV)

    # ensure all new_headers are present
    header_set = set(headers)
    for h in new_headers:
        if h not in header_set:
            headers.append(h)
            header_set.add(h)

    # update or add new
    team_map = {r["team_number"]: r for r in rows}
    for upd in updated_rows:
        tnum = upd.get("team_number")
        if tnum in team_map:
            # update existing
            for k, v in upd.items():
                team_map[tnum][k] = v
        else:
            # new row
            team_map[tnum] = upd

    # reassemble rows
    rows = list(team_map.values())
    write_csv(TEAMS_CSV, rows, headers)
    return jsonify({"message": "Teams CSV updated successfully."}), 200

# ------------------------------------------------------------------------------
# Registration, Login, Logout
# ------------------------------------------------------------------------------
@app.route("/api/register", methods=["POST"])
def api_register():
    data = request.json
    if not data:
        return Response("Missing JSON.\n", status=400)
    uname = data.get("username")
    pword = data.get("password")
    if not uname or not pword:
        return Response("Missing fields.\n", status=400)

    rows, headers = read_users_csv()
    # Check if user exists
    for r in rows:
        if r["username"] == uname:
            return Response("Username already exists.\n", status=400)

    newRow = {
        "username": uname,
        "password_hash": simple_hash(pword),
        "session_token": "",
        "cards_owned": "",
        "money": "20000"
    }
    rows.append(newRow)
    write_users_csv(rows, headers)
    return Response("Registered.\n", status=200)

@app.route("/api/login", methods=["POST"])
def api_login():
    data = request.json
    if not data:
        return Response("Missing JSON.\n", status=400)
    uname = data.get("username")
    pword = data.get("password")
    if not uname or not pword:
        return Response("Missing fields.\n", status=400)

    rows, headers = read_users_csv()
    for r in rows:
        if r["username"] == uname:
            if r["password_hash"] == simple_hash(pword):
                # create session token
                token = str(random.randint(1, 999999999))
                r["session_token"] = token
                write_users_csv(rows, headers)
                return jsonify({"session_token": token}), 200
            else:
                return Response("Invalid password.\n", status=401)
    return Response("User not found.\n", status=401)

@app.route("/api/logout", methods=["GET"])
def api_logout():
    token = request.args.get("token")
    if not token:
        return Response("No token param.\n", status=400)
    user, allRows, allHeaders = find_user_by_token(token)
    if user:
        user["session_token"] = ""
        write_users_csv(allRows, allHeaders)
        return Response("Logged out.\n", status=200)
    return Response("Invalid token.\n", status=400)

@app.route("/api/user/inventory", methods=["GET"])
def api_user_inventory():
    token = request.args.get("token")
    if not token:
        return Response("No token.\n", status=401)
    user, allRows, allHeaders = find_user_by_token(token)
    if not user:
        return Response("Invalid session.\n", status=401)
    cards_str = user.get("cards_owned", "")
    if not cards_str.strip():
        return jsonify([])
    else:
        arr = cards_str.split(",")
        return jsonify(arr)

@app.route("/api/market/top", methods=["GET"])
def api_market_top():
    """ Returns a hardcoded list of top-selling cards. """
    topCards = [
        {"team_number":"1771"},
        {"team_number":"1261"},
        {"team_number":"1683"},
        {"team_number":"1771"},
        {"team_number":"1261"},
        {"team_number":"1683"}
    ]
    return jsonify(topCards)

# ------------------------------------------------------------------------------
# Main entry with Waitress
# ------------------------------------------------------------------------------
def create_app():
    return app

# if __name__ == "__main__":
#     print("Starting Client API Service (CAS) on port 8090...")
#     serve(app, host="0.0.0.0", port=8090)  # Running Flask on all IPs on port 8090
