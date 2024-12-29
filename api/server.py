# server.py

from flask import Flask, request, jsonify
import os
from card_creator import create_card  # Import your card creation logic

app = Flask(__name__)

# Ensure output directory exists
OUTPUT_DIR = os.path.abspath("./robotCards")
os.makedirs(OUTPUT_DIR, exist_ok=True)

@app.route('/create-card', methods=['POST'])
def create_card_api():
    data = request.json
    
    # Extract all necessary fields with defaults
    card_data = {
        "team_number": data.get("team_number", "unknown"),
        "team_name": data.get("team_name", "Unknown Team"),
        "custom_label": data.get("custom_label", ""), # Already filled / dw about it
        "flavor_text": data.get("flavor_text", ""),
        "image_path": os.path.abspath(data.get("image_path", "")),  # Ensure absolute path
        "image_x": data.get("image_x", 0),
        "image_y": data.get("image_y", 0),
        "image_zoom": data.get("image_zoom", 1),
        "attacks_list": data.get("attacks_list", []),
        "abilities_list": data.get("abilities_list", []),
        
        "hitpoints": data.get("hitpoints", "150"),
        "illustrator": data.get("illustrator", "Logan Peterson"),
        "total_number_in_set": data.get("total_number_in_set", "10695"), # Update this to total number of FRC teams for 2025 season
        "type_": data.get("type_", "Metal"),
        "base_set": data.get("base_set", "Sword & Shield"),
        "supertype": data.get("supertype", "Pokémon"),
        "subtype": data.get("subtype", "Basic"),
        "variation": data.get("variation", "None"),
        "rarity": data.get("rarity", "None"),
        "subname": data.get("subname", ""),
        "weakness_type": data.get("weakness_type", "Water"),
        "weakness_amt": data.get("weakness_amt", "2"),
        "resistance_type": data.get("resistance_type", "Lightning"),
        "resistance_amt": data.get("resistance_amt", "30"),
        "retreat_cost": data.get("retreat_cost", "3"),
        "icon_text": data.get("icon_text", "FRC"),
        "output_dir": OUTPUT_DIR,
        "custom_regulation_mark_image": os.path.abspath(data.get("custom_regulation_mark_image", "./images/FIRSTlogo.png")),
    }
    
    # Validate image path
    if not os.path.exists(card_data["image_path"]):
        return jsonify({"status": "failure", "message": "Image file not found"}), 400
    
    try:
        card_path = create_card(
            team_number=card_data["team_number"],
            name=card_data["team_name"],
            image_path=card_data["image_path"],
            image_x=card_data["image_x"],
            image_y=card_data["image_y"],
            image_zoom=card_data["image_zoom"],
            custom_label=card_data["custom_label"],
            flavor_text=card_data["flavor_text"],
            abilities_list=card_data["abilities_list"],
            attacks_list=card_data["attacks_list"],

            illustrator=card_data["illustrator"],
            hitpoints=card_data["hitpoints"],
            base_set=card_data["base_set"],
            supertype=card_data["supertype"],
            type_=card_data["type_"],
            subtype=card_data["subtype"],
            variation=card_data["variation"],
            rarity=card_data["rarity"],
            subname=card_data["subname"],
            weakness_type=card_data["weakness_type"],
            weakness_amt=card_data["weakness_amt"],
            resistance_type=card_data["resistance_type"],
            resistance_amt=card_data["resistance_amt"],
            retreat_cost=card_data["retreat_cost"],
            icon_text=card_data["icon_text"],
            output_dir=card_data["output_dir"],
            total_number_in_set=card_data["total_number_in_set"],
            custom_regulation_mark_image=card_data["custom_regulation_mark_image"],
        )

        return jsonify({"status": "success", "card_path": card_path})
    except Exception as e:
        print(f"Error creating card: {e}")
        return jsonify({"status": "failure", "message": "Card creation failed"}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8091)  # Running Flask on all IPs on port 8091