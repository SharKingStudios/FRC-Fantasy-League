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
    team_number = data.get("team_number", "unknown")
    team_name = data.get("team_name", "Unknown Team")
    custom_label = data.get("custom_label", "")
    flavor_text = data.get("flavor_text", "")
    image_path = os.path.abspath(data.get("image_path", ""))  # Resolve absolute path

    # if not os.path.exists(image_path):
    #     return jsonify({"status": "failure", "message": "Image file not found"}), 400

    try:
        card_path = create_card(
            base_set="Sword & Shield",
            supertype="Pokémon",
            type_="Metal",
            subtype="Basic",
            variation="None",
            rarity="None",
            name=team_name,
            subname="",
            hitpoints="150",
            custom_label=custom_label,
            weakness_type="Water",
            weakness_amt="2",
            resistance_type="Lightning",
            resistance_amt="30",
            retreat_cost="3",
            illustrator="Logan Peterson",
            icon_text="FRC",
            flavor_text="flavor_text",
            image_path=os.path.abspath(f"./images/robotImages/{team_number}.jpeg"),
            image_x=-15,
            image_y=-100,
            image_zoom=0.95,
            attacks_list=[],
            abilities_list=[],
            output_dir=os.path.abspath("./robotCards"),
            team_number=team_number,
            total_number_in_set="100",
            custom_regulation_mark_image=os.path.abspath("./images/FIRSTlogo.png"),

        )

        return jsonify({"status": "success", "card_path": card_path})
    except Exception as e:
        print(f"Error creating card: {e}")
        return jsonify({"status": "failure", "message": "Card creation failed"}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8091)  # Running Flask on all IPs on port 8091
