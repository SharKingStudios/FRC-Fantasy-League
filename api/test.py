from card_creator import create_card
import os

print(create_card(
            base_set="Sword & Shield",
            supertype="Pokémon",
            type_="Metal",
            subtype="Basic",
            variation="None",
            rarity="None",
            name="team_name",
            subname="",
            hitpoints="150",
            custom_label="custom_label",
            weakness_type="Water",
            weakness_amt="2",
            resistance_type="Lightning",
            resistance_amt="30",
            retreat_cost="3",
            illustrator="Logan Peterson",
            icon_text="FRC",
            flavor_text="flavor_text",
            image_path=os.path.abspath("./images/1771.jpeg"),
            image_x=-15,
            image_y=-100,
            image_zoom=0.95,
            attacks_list=[],
            abilities_list=[],
            output_dir=os.path.abspath("./robotCards"),
            team_number="1771",
            total_number_in_set="100",
            custom_regulation_mark_image=os.path.abspath("./images/FIRSTlogo.png"),

        ))