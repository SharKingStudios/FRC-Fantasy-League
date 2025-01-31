#!/usr/bin/env python3
"""
batch_process_cards.py

Downloads 'teams.csv' from the server, spawns up to N parallel processes
to generate Pokémon-style cards with `card_creator.py`, then uploads
the resulting card image AND a 220px thumbnail back to the server.

This version passes additional command-line flags:
  --image_x, --image_y, --image_zoom, --name, --custom_label,
  --flavor_text, --hitpoints, --rarity_icon, --resistance_type,
  --resistance_amt, --card_number, --type
...all based on row data in teams.csv (if present).
"""

import os
import csv
import requests
import subprocess
import sys
import shutil
import json
from concurrent.futures import ThreadPoolExecutor, as_completed

# ----------------------------
# Configuration
# ----------------------------
SERVER_BASE_URL       = "http://sharkingstudios.hackclub.app:8090"
TEAMS_CSV_URL         = f"{SERVER_BASE_URL}/api/teams.csv"
ROBOT_IMAGES_URL      = f"{SERVER_BASE_URL}/api/robotImages"
UPLOAD_CARD_URL       = f"{SERVER_BASE_URL}/api/admin/uploadFinalCard"
UPLOAD_THUMBNAIL_URL  = f"{SERVER_BASE_URL}/api/admin/uploadFinalCardThumbnail"

LOCAL_DOWNLOAD_FOLDER = "./temp_robot_images"
LOCAL_OUTPUT_FOLDER   = "./temp_robot_cards"
LOCAL_THUMBNAIL_FOLDER= "./temp_robot_cards/size_220"
DEFAULT_IMAGE_PATH    = "./temp_robot_images/default.png"  # fallback if no remote image found


MAX_WORKERS = 20  # Number of parallel processes to run
MAX_RETRIES = 20 # Retry attempts for card creation

# Limit the number of teams to process (for testing)
LIMIT = -1 # Process only first n teams. Use -1 for all.


os.makedirs(LOCAL_DOWNLOAD_FOLDER, exist_ok=True)
os.makedirs(LOCAL_OUTPUT_FOLDER, exist_ok=True)


def download_csv():
    """
    Fetch teams.csv from the server, return a list of row dicts.
    """
    print(f"[INFO] Downloading teams.csv from: {TEAMS_CSV_URL}")
    r = requests.get(TEAMS_CSV_URL)
    r.raise_for_status()
    lines = r.text.splitlines()
    reader = csv.DictReader(lines)
    rows = list(reader)
    print(f"[INFO] Received {len(rows)} team rows.")
    return rows


def download_robot_image(team_number: str) -> str:
    """
    Attempts to download the robot image from:
      /api/robotImages/<team_number>.png
      /api/robotImages/<team_number>.jpeg
      /api/robotImages/<team_number>.jpg
    If none found, uses default.png from local disk.
    Returns the local path to the final image file.
    """
    possible_exts = [".png", ".jpeg", ".jpg"]
    for ext in possible_exts:
        url = f"{ROBOT_IMAGES_URL}/{team_number}{ext}"
        local_path = os.path.join(LOCAL_DOWNLOAD_FOLDER, f"{team_number}{ext}")
        print(f"[INFO] Trying: {url}")
        resp = requests.get(url)
        if resp.status_code == 200:
            with open(local_path, "wb") as f:
                f.write(resp.content)
            print(f"[INFO] Downloaded => {local_path}")
            return local_path

    # No image found => use default
    print(f"[WARN] No image found for team {team_number}; using default.png")
    local_path = os.path.join(LOCAL_DOWNLOAD_FOLDER, f"{team_number}.png")
    # shutil.copy(DEFAULT_IMAGE_PATH, local_path)
    local_path = DEFAULT_IMAGE_PATH
    return local_path


def run_card_creator(team_number: str, local_image_path: str, row_data: dict) -> str:
    """
    Runs card_creator.py in a subprocess, passing arguments from row_data.
    Returns path to the final card image on success, or None on failure.
    """

    # Construct the final .png path
    output_path = os.path.join(LOCAL_OUTPUT_FOLDER, f"{team_number}.png")

    # Gather extra fields from row_data (with fallback defaults)
    if local_image_path == DEFAULT_IMAGE_PATH:
        print(f"[WARN] Using default image for team {team_number}")
        image_x = "0"
        image_y = "-80"
        image_zoom = "0.6"
    else:
        image_x     = row_data.get("image_x", "0")
        image_y     = row_data.get("image_y", "-80")
        image_zoom  = row_data.get("image_zoom", "0.6")
    
    print(f"[INFO] Processing team {team_number} with: imagex={image_x}, imagey={image_y}, zoom={image_zoom}")
    print(f"Supposed to be: imagex={row_data.get('image_x', '0')}, imagey={row_data.get('image_y', '-80')}, zoom={row_data.get('image_zoom', '0.6')}")

    name        = row_data.get("nickname", f"Team {team_number}")
    custom_label= row_data.get("custom_label", f"No. {team_number} FRC")
    flavor_text = row_data.get("flavor_text", "")
    hitpoints   = row_data.get("hitpoints", "150")
    rarity_icon = row_data.get("rarity", "None")
    resistance_type = row_data.get("resistance_type", "Lightning")
    resistance_amt  = row_data.get("resistance_amt", "30")
    card_number = team_number
    type_       = row_data.get("type_", "Metal")
    
    abilities_list_num = row_data.get("abilities_list", "")
    attacks_list_num   = row_data.get("attacks_list", "")

    # Custom abilities and attacks for specific teams
    if abilities_list_num == "1":
        abilities_list = [ # !!! ONLY ADD ONE ABILITY FOR NOW !!! Does not work with multiple abilities
        {
            "name": "Boosted Collection",
            "description": "Once during your turn, if a note is collected from your active robot, another note is collected.",
        },
        ]
    elif abilities_list_num == "2":
        abilities_list = [
        {
            "name": "Encore Performance",
            "description": "Once per turn, if this robot scores a Note, flip a coin. If heads, score another note.",
        },
        ]
    elif abilities_list_num == "3":
        abilities_list = [
        {
            "name": "Auto-Tuned Precision",
            "description": "During your first turn, your Collect Note ability lets you draw two cards instead of one.",
        },
        ]
    elif abilities_list_num == "4": # Specifically for OTTO's Backpack
        abilities_list = [
        {
            "name": "OTTO's Backpack",
            "description": "Once per turn, you may flood the field with notes. Shuffle the note pile and draw 5 cards.",
        },
        ]
    else: # Generic abilities
        abilities_list = [
        {
            "name": "Harmony Mode",
            "description": "When this Robot is in play, all of your Robots require one less Energy to use Score Note.",
        },
        ]
    
    # Custom attacks for specific teams
    if attacks_list_num == "1": # A note collector card
        attacks_list = [
        {
            "name": "Rapid Pickup",
            "energy_costs": ["Lightning"],
            "damage": "",
            "description": "Draw two Notes from the pile instead of one.",
        },
        {
            "name": "Score Note",
            "energy_costs": ["Lightning", "Lightning", "Colorless"],
            "damage": "100",
            "description": "Take a note from your hand and discard it.",
        },
        ]
    elif attacks_list_num == "2": # An assist card
        attacks_list = [
        {
            "name": "Backstage Assist",
            "energy_costs": ["Lightning"],
            "damage": "",
            "description": "Search your deck for an Energy card and attach it to any of your robots.",
        },
        {
            "name": "Bass Drop",
            "energy_costs": ["Lightning", "Lightning", "Colorless"],
            "damage": "100",
            "description": "Discard the top two cards of your deck. If at least one is an Energy, deal 20 more damage.",
        },
        ]
    else: # Generic attacks
        attacks_list = [
        {
            "name": "Collect Note",
            "energy_costs": ["Lightning"],
            "damage": "",
            "description": "Draw a card from the note pile and add it to your hand.",
        },
        {
            "name": "Score Note",
            "energy_costs": ["Lightning", "Lightning", "Colorless"],
            "damage": "100",
            "description": "Take a note from your hand and discard it.",
        },
        ]

    # Build up CLI args for card_creator.py
    cmd = [
        sys.executable,
        "card_creator.py",
        f"--team_number={team_number}",
        f"--image_path={local_image_path}",
        f"--output_path={output_path}",
        f"--image_x={image_x}",
        f"--image_y={image_y}",
        f"--image_zoom={image_zoom}",
        f"--name={name}",
        f"--custom_label={custom_label}",
        f"--flavor_text={flavor_text}",
        f"--hitpoints={hitpoints}",
        f"--rarity_icon={rarity_icon}",
        f"--resistance_type={resistance_type}",
        f"--resistance_amt={resistance_amt}",
        f"--card_number={card_number}",
        f"--type={type_}",
        f"--abilities_list={json.dumps(abilities_list)}",
        f"--attacks_list={json.dumps(attacks_list)}",
    ]

    print(f"[INFO] Running card_creator => {cmd}")
    try:
        subprocess.run(cmd, check=True)
        if os.path.exists(output_path):
            print(f"[INFO] Card created => {output_path}")
            return output_path
        else:
            print(f"[ERROR] Card creation script did not produce {output_path}")
            return None
    except subprocess.CalledProcessError as e:
        print(f"[ERROR] Subprocess error: {e}")
        return None


def upload_final_card(team_number: str, card_path: str):
    """
    POST the final card to /api/admin/uploadFinalCard
    """
    files = {
        "cardImage": open(card_path, "rb"),
    }
    data = {"teamNumber": team_number}
    print(f"[INFO] Uploading final card => {UPLOAD_CARD_URL}")
    resp = requests.post(UPLOAD_CARD_URL, files=files, data=data)
    if resp.status_code == 200:
        print(f"[INFO] Card upload succeeded for team {team_number}")
    else:
        print(f"[ERROR] Card upload FAILED for team {team_number}: {resp.text}")


def resize_image_imagemagick(input_path, output_path, width=220):
    """
    Resize `input_path` to have a width of `width` pixels
    using ImageMagick's `mogrify`. The resulting file is saved
    at `output_path`.
    """
    try:
        # Copy the original file to the thumbnail path
        shutil.copy2(input_path, output_path)

        cmd = [
            "mogrify",
            "-resize", f"{width}",
            os.path.abspath(output_path)
        ]
        print(f"[INFO] Running mogrify => {cmd}")
        subprocess.run(cmd, check=True)
        print(f"[INFO] Resized image with mogrify => {output_path}")
    except subprocess.CalledProcessError as e:
        print(f"[ERROR] mogrify conversion failed: {e}")


def upload_thumbnail(team_number: str, thumb_path: str):
    """
    POST the thumbnail to /api/admin/uploadFinalCardThumbnail
    """
    files = {
        "cardThumbnail": open(thumb_path, "rb"),
    }
    data = {"teamNumber": team_number}
    print(f"[INFO] Uploading thumbnail => {UPLOAD_THUMBNAIL_URL}")
    resp = requests.post(UPLOAD_THUMBNAIL_URL, files=files, data=data)
    if resp.status_code == 200:
        print(f"[INFO] Thumbnail upload succeeded for team {team_number}")
    else:
        print(f"[ERROR] Thumbnail upload FAILED for team {team_number}: {resp.text}")


def process_one_team(row: dict) -> str:
    """
    1) Download robot image or use default.png
    2) Retry up to MAX_RETRIES to run card_creator
    3) Upload final card
    4) Create & upload 220px thumbnail
    """
    team_number = row.get("team_number", "").strip()
    if not team_number:
        return "[ERROR] Row missing team_number"

    # 1) Download the image
    local_img_path = download_robot_image(team_number)

    # 2) Re-try up to MAX_RETRIES
    final_card = None
    for attempt in range(MAX_RETRIES):
        final_card = run_card_creator(team_number, local_img_path, row)
        if final_card:
            print(f"[INFO] Team {team_number} succeeded on attempt {attempt+1}")
            break
        else:
            print(f"[WARN] Team {team_number} failed attempt {attempt+1} - retrying...")

    if not final_card:
        return f"[ERROR] Card creation failed after {MAX_RETRIES} tries: team {team_number}"

    # 3) Upload final card
    upload_final_card(team_number, final_card)

    # 4) Create + upload thumbnail
    print(f"[INFO] Creating thumbnail for team {team_number}...")
    thumb_path = os.path.join(LOCAL_THUMBNAIL_FOLDER, f"{team_number}.png")
    print(f"[INFO] Thumbnail path => {thumb_path}")
    print(f"[INFO] Resizing image with ImageMagick...")
    resize_image_imagemagick(final_card, thumb_path, width=220)
    print(f"[INFO] Thumbnail created => {thumb_path}")
    thumb_path = thumb_path.replace("\\", "/")  # Windows fix
    thumb_path = os.path.abspath(thumb_path)
    upload_thumbnail(team_number, thumb_path)

    return f"[OK] Team {team_number} processed."


def main():

    teams_data = download_csv()

    # Slice the list if LIMIT is positive
    if LIMIT > 0:
        teams_data = teams_data[:LIMIT]
        print(f"[DEBUG] Only processing the first {LIMIT} teams for testing.")

    print(f"[INFO] Starting parallel processing for {len(teams_data)} teams...")
    print(f"[INFO] Max workers = {MAX_WORKERS}")

    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        future_map = {
            executor.submit(process_one_team, row): row.get("team_number", "???")
            for row in teams_data
        }

        for future in as_completed(future_map):
            tnum = future_map[future]
            try:
                result = future.result()
                print(f"[TEAM {tnum}] {result}")
            except Exception as exc:
                print(f"[TEAM {tnum}] Exception: {exc}")

    print("[INFO] All done.")



if __name__ == "__main__":
    main()
