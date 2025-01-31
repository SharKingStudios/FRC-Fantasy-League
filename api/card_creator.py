from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait, Select
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.common.action_chains import ActionChains
from selenium.webdriver.common.keys import Keys
import os
import time
import argparse
import json

def safe_click(driver, element):
    """
    Scrolls the element into view, removes obstructions (like iframes), and clicks the element.
    """
    try:
        remove_all_overlays(driver)
        # Scroll the element into view
        driver.execute_script("arguments[0].scrollIntoView(true);", element)

        # Wait for the element to be clickable
        WebDriverWait(driver, 10).until(EC.element_to_be_clickable(element))

        # Remove any potential iframes that might block the click
        for iframe in driver.find_elements(By.TAG_NAME, "iframe"):
            try:
                driver.execute_script("arguments[0].remove();", iframe)
                print("Obstructing iframe removed.")
            except Exception as e:
                print(f"Failed to remove iframe: {e}")

        # Attempt to click the element
        try:
            element.click()
            print("Element clicked successfully.")
        except:
            js_click_element(driver, element)
            print("Error with clicking, clicked via JavaScript.")

    except Exception as e:
        print(f"Failed to safely click element: {e}")
        raise

def js_click_element(driver, element):
    """
    Fallback to clicking an element using JavaScript if normal click fails.
    """
    try:
        driver.execute_script("arguments[0].click();", element)
        print("Element clicked via JavaScript.")
    except Exception as e:
        print(f"JavaScript click failed: {e}")
        raise

def remove_all_overlays(driver):
    """
    Removes modal overlays, consent dialogs, and banners that interfere with interactions.
    """
    try:
        overlay_classes = [
            "fc-dialog-overlay",    # Consent dialog overlay
            "fc-consent-root",      # Consent modal root
            "cookie-banner",        # Example cookie banners
        ]
        for overlay_class in overlay_classes:
            overlays = driver.find_elements(By.CLASS_NAME, overlay_class)
            for overlay in overlays:
                driver.execute_script("arguments[0].remove();", overlay)
                print(f"Overlay of class {overlay_class} removed.")
        print("All overlays removed.")
    except Exception as e:
        print(f"Error removing overlays: {e}")


# Custom Regulaiton Mark
def select_custom_regulation_mark(driver):
    """
    Selects 'Custom' from the Regulation Mark dropdown.
    """
    try:
        # Locate and click the dropdown to open it
        dropdown = WebDriverWait(driver, 10).until(
            EC.element_to_be_clickable((By.XPATH, "//label[text()='Regulation Mark']/following-sibling::div"))
        )
        safe_click(driver, dropdown)
        print("Regulation Mark dropdown clicked.")

        # Select 'Custom' from the options
        custom_option = WebDriverWait(driver, 10).until(
            EC.element_to_be_clickable((By.XPATH, "//div[contains(@class, 'css-j7qwjs') and text()='Custom']"))
        )
        safe_click(driver, custom_option)
        print("Custom Regulation Mark option selected.")
    except Exception as e:
        print(f"Error selecting Custom Regulation Mark: {e}")
        raise


def upload_custom_logo(driver, custom_regulation_mark_image):
    """
    Directly uploads the custom logo for the Custom Regulation Mark using the hidden file input field.
    """
    try:
        # Locate the hidden file input field directly
        file_input = WebDriverWait(driver, 10).until(
            EC.presence_of_element_located((By.XPATH, "//input[@type='file' and contains(@id, 'customrotationIconSrc')]"))
        )

        # Use send_keys to upload the file directly
        file_input.send_keys(custom_regulation_mark_image)
        print("Custom logo uploaded successfully without triggering the file manager.")
    except Exception as e:
        print(f"Error uploading custom logo: {e}")
        raise

# Add Ability
def fill_ability_fields(driver, ability_name, description):
    """
    Fills out the ability fields for name and description.
    """
    try:
        # Locate the most recently added ability (last in the ability list)
        ability_div = WebDriverWait(driver, 10).until(
            EC.presence_of_element_located(
                (By.XPATH, "(//div[contains(@class, 'css-k0fkzx') and .//p[contains(text(), 'Ability')]])[last()]")
            )
        )
        print("Located the most recently added ability.")

        # Fill the name field
        name_field = ability_div.find_element(By.XPATH, ".//label[contains(text(), 'Name')]/following-sibling::div//input")
        name_field.clear()
        name_field.send_keys(Keys.CONTROL + "a")  # Select all
        name_field.send_keys(Keys.BACKSPACE)
        name_field.send_keys(ability_name)
        print(f"Ability name set to: {ability_name}")

        # Fill the description field
        description_field = ability_div.find_element(By.XPATH, ".//label[contains(text(), 'Description')]/following-sibling::div//textarea")
        description_field.clear()
        description_field.send_keys(Keys.CONTROL + "a")  # Select all
        description_field.send_keys(Keys.BACKSPACE)
        description_field.send_keys(description)
        print(f"Ability description set to: {description}")

    except Exception as e:
        print(f"Error filling ability fields: {e}")
        raise

def add_abilities(driver, abilities):
    """
    Adds all abilities from the provided list.

    :param driver: Selenium WebDriver instance
    :param abilities: List of abilities, each being a dictionary with 'name' and 'description'.
    """
    for ability in abilities:
        print(f"Adding ability: {ability['name']}")

        # Click the "Add Ability" button
        click_add_ability_button(driver)

        # Fill out the ability fields for the most recently added ability
        fill_ability_fields(
            driver,
            ability_name=ability["name"],
            description=ability["description"],
        )

        print(f"Ability '{ability['name']}' added successfully.\n")

def click_add_ability_button(driver):
    """
    Clicks the 'Add Ability' button safely.
    """
    try:
        add_ability_button = WebDriverWait(driver, 10).until(
            EC.element_to_be_clickable((By.XPATH, "//button[contains(text(), 'Add Ability')]"))
        )
        safe_click(driver, add_ability_button)
        print("Add Ability button clicked.")
    except Exception as e:
        print(f"Error clicking 'Add Ability' button: {e}")
        raise

# Add Attack
def add_attacks(driver, attacks):
    """
    Adds all attacks from the provided list.
    
    :param driver: Selenium WebDriver instance
    :param attacks: List of attacks, each being a dictionary with 'name', 'energy_costs', 'damage', and 'description'.
    """
    for attack in attacks:
        print(f"Adding attack: {attack['name']}")

        # Click the "Add Attack" button
        click_add_attack_button(driver)

        # Fill out the attack fields
        fill_attack_fields(
            driver,
            attack_name=attack["name"],
            energy_costs=attack["energy_costs"],
            damage=attack["damage"],
            description=attack["description"],
        )

        print(f"Attack '{attack['name']}' added successfully.\n")

def click_add_attack_button(driver):
    try:
        add_attack_button = WebDriverWait(driver, 10).until(
            EC.element_to_be_clickable((By.XPATH, "//button[contains(text(), 'Add Attack')]"))
        )
        safe_click(driver, add_attack_button)
        print("Add Attack button clicked.")
    except Exception as e:
        print(f"Error clicking 'Add Attack' button: {e}")
        raise


def fill_attack_fields(driver, attack_name, energy_costs, damage, description):
    # Locate the most recently added attack (last in the attack list)
    attack_div = WebDriverWait(driver, 10).until(
        EC.presence_of_element_located(
            (By.XPATH, "(//div[@data-rfd-draggable-id and contains(@class, 'css-k0fkzx')])[last()]")
        )
    )
    print("Located the most recently added attack.")

    # Fill the name field
    name_field = attack_div.find_element(By.XPATH, ".//label[contains(text(), 'Name')]/following-sibling::div//input")
    name_field.clear()
    name_field.send_keys(Keys.CONTROL + "a")  # Select all
    name_field.send_keys(Keys.BACKSPACE)

    # Ensure it's cleared using JS
    driver.execute_script("arguments[0].value = '';", name_field)
    name_field.send_keys(attack_name)
    print(f"Set attack name to: {attack_name}")

    # Set the energy costs
    energy_buttons = attack_div.find_elements(
        By.XPATH, ".//div[@id[contains(.,'EnergyCost')]]//button[contains(@aria-label, 'add')]"
    )
    for energy in energy_costs:
        for button in energy_buttons:
            if energy in button.get_attribute("aria-label"):
                safe_click(driver, button)
                print(f"Added energy cost: {energy}")
                break

    # Set the damage
    damage_field = attack_div.find_element(By.XPATH, ".//label[contains(text(), 'Damage')]/following-sibling::div//input")
    damage_field.clear()
    # Ensure it's cleared using backspace
    damage_field.send_keys(Keys.CONTROL + "a")  # Select all
    damage_field.send_keys(Keys.BACKSPACE)

    # Ensure it's cleared using JS
    driver.execute_script("arguments[0].value = '';", damage_field)
    damage_field.send_keys(damage)
    print(f"Set attack damage to: {damage}")

    # Set the description
    description_field = attack_div.find_element(
        By.XPATH, ".//label[contains(text(), 'Description')]/following-sibling::div//textarea"
    )
    description_field.clear()
    # Ensure it's cleared using backspace
    description_field.send_keys(Keys.CONTROL + "a")  # Select all
    description_field.send_keys(Keys.BACKSPACE)

    # Ensure it's cleared using JS
    driver.execute_script("arguments[0].value = '';", description_field)
    description_field.send_keys(description)
    print(f"Set attack description to: {description}")



# Image Cropping
def click_crop_button(driver):
    crop_button = WebDriverWait(driver, 10).until(
        EC.element_to_be_clickable((By.XPATH, "//button[contains(text(), 'Crop')]"))
    )
    safe_click(driver, crop_button)
    print("Crop button clicked.")

def click_advanced_crop_button(driver):
    advanced_crop_button = WebDriverWait(driver, 10).until(
        EC.element_to_be_clickable((By.XPATH, "//button[contains(text(), 'Advanced Crop')]"))
    )
    safe_click(driver, advanced_crop_button)
    print("Advanced Crop button clicked.")

def set_crop_values(driver, x_value, y_value, zoom_value):
    # Set X-coordinate
    x_input = WebDriverWait(driver, 10).until(
        EC.presence_of_element_located(
            (By.XPATH, "//label[text()='X-Coordinate']/following-sibling::div//input")
        )
    )
    x_input.clear()
    # Ensure it's cleared using backspace
    x_input.send_keys(Keys.CONTROL + "a")  # Select all
    x_input.send_keys(Keys.BACKSPACE)

    # Ensure it's cleared using JS
    driver.execute_script("arguments[0].value = '';", x_input)
    x_input.send_keys(str(x_value))
    print(f"X-coordinate set to {x_value}.")

    # Set Y-coordinate
    y_input = WebDriverWait(driver, 10).until(
        EC.presence_of_element_located(
            (By.XPATH, "//label[text()='Y-Coordinate']/following-sibling::div//input")
        )
    )
    y_input.clear()
    # Ensure it's cleared using backspace
    y_input.send_keys(Keys.CONTROL + "a")  # Select all
    y_input.send_keys(Keys.BACKSPACE)

    # Ensure it's cleared using JS
    driver.execute_script("arguments[0].value = '';", y_input)
    y_input.send_keys(str(y_value))
    print(f"Y-coordinate set to {y_value}.")

    # Set Zoom level
    zoom_input = WebDriverWait(driver, 10).until(
        EC.presence_of_element_located(
            (By.XPATH, "//label[text()='Zoom level']/following-sibling::div//input")
        )
    )
    zoom_input.clear()
    # Ensure it's cleared using backspace
    zoom_input.send_keys(Keys.CONTROL + "a")  # Select all
    zoom_input.send_keys(Keys.BACKSPACE)

    # Ensure it's cleared using JS
    driver.execute_script("arguments[0].value = '';", zoom_input)
    zoom_input.send_keys(str(zoom_value))
    print(f"Zoom level set to {zoom_value}.")

def create_card(
    base_set, supertype, type_, subtype, variation, rarity,
    name, subname, hitpoints, custom_label, weakness_type, weakness_amt,
    resistance_type, resistance_amt, retreat_cost, illustrator, icon_text,
    flavor_text, image_path, image_x, image_y, image_zoom, attacks_list,
    abilities_list, output_dir, team_number, total_number_in_set, custom_regulation_mark_image
):
    # Configure Chrome options
    chrome_options = Options()
    chrome_options.add_argument("--no-sandbox")
    chrome_options.add_argument("--disable-dev-shm-usage")
    chrome_options.add_argument("--ignore-certificate-errors")
    chrome_options.add_argument("--window-size=1000,1000")
    # chrome_options.add_argument("--disable-gpu")
    # chrome_options.add_argument("--headless=new")
    # chrome_options.add_argument("--headless")  # Run headless for server use

    # Set the download directory
    prefs = {
        "download.default_directory": os.path.abspath(output_dir),  # Absolute path to your desired download folder
        "download.prompt_for_download": False,  # Disable download prompt
        "download.directory_upgrade": True,  # Ensure downloads overwrite existing files
        "safebrowsing.enabled": True  # Enable safe browsing for downloads
    }
    chrome_options.add_experimental_option("prefs", prefs)

    # Construct the desired file paths
    original_filename = f"{name}.png"  # Name as the site generates it
    renamed_filename = f"{team_number}.png"  # New desired name
    original_filepath = os.path.join(output_dir, original_filename)
    renamed_filepath = os.path.join(output_dir, renamed_filename)

    # Delete existing files if they exist
    for path in [original_filepath, renamed_filepath]:
        if os.path.exists(path):
            os.remove(path)
            print(f"Deleted existing file: {path}")

    # Initialize WebDriver
    driver = webdriver.Chrome(options=chrome_options)
    # driver = webdriver.Chrome(
    # executable_path="~/frcfantasyserver/FRC-Fantasy-League/api/chromedriver",
    # options=chrome_options)


    try:
        # Open the website
        driver.get("https://pokecardmaker.net/creator")

        # Wait for the page to load
        WebDriverWait(driver, 30).until(
            EC.presence_of_element_located((By.TAG_NAME, "body"))
        )
        # Fill text fields
        def fill_field(field_id, value):
            # Locate the field
            field = WebDriverWait(driver, 10).until(
                EC.presence_of_element_located((By.ID, field_id))
            )
            # Clear the field
            try:
                field.clear()  # Try native clear
            except:
                pass  # Ignore errors if .clear() fails

            # Ensure it's cleared using backspace
            field.send_keys(Keys.CONTROL + "a")  # Select all
            field.send_keys(Keys.BACKSPACE)

            # Ensure it's cleared using JS
            driver.execute_script("arguments[0].value = '';", field)

            # Enter new value
            field.send_keys(value)


        def remove_obstructing_iframe(driver):
            try:
                iframe = driver.find_element(By.TAG_NAME, "iframe")
                driver.execute_script("arguments[0].remove();", iframe)
                print("Obstructing iframe removed.")
            except Exception as e:
                print("No obstructing iframe found.")

        def select_custom_dropdown_by_label(driver, label_text, option_text):
            try:
                # Locate the parent container by the label
                parent_div = WebDriverWait(driver, 10).until(
                    EC.presence_of_element_located(
                        (By.XPATH, f"//label[text()='{label_text}']/following-sibling::div//div[contains(@class, 'css-5bhydl')]")
                    )
                )
                # Scroll into view and use safe_click
                safe_click(driver, parent_div)

                # Wait for the dropdown options to appear
                options_xpath = f"//div[contains(@class, 'css-j7qwjs') and normalize-space(text())='{option_text}']"
                option = WebDriverWait(driver, 10).until(
                    EC.element_to_be_clickable((By.XPATH, options_xpath))
                )

                # Scroll to the option and use safe_click
                safe_click(driver, option)
            except Exception as e:
                print(f"Failed to select from dropdown '{label_text}'. Error: {e}")

        # Use the functions

        # Fill out the dropdowns
        # Select Base Set dropdown
        select_custom_dropdown_by_label(driver, "Base set", base_set)

        # Select Type dropdown
        select_custom_dropdown_by_label(driver, "Type", type_)

        # Select Subtype dropdown
        select_custom_dropdown_by_label(driver, "Subtype", subtype)

        # Select Variation dropdown
        select_custom_dropdown_by_label(driver, "Variation", variation)

        # Select Rarity dropdown
        select_custom_dropdown_by_label(driver, "Rarity", rarity)

        # Select Weakness Type dropdown
        remove_obstructing_iframe(driver)
        select_custom_dropdown_by_label(driver, "Weakness Type", weakness_type)

        # Select Resistance Type dropdown
        remove_obstructing_iframe(driver)
        select_custom_dropdown_by_label(driver, "Resistance Type", "Lightning")

        # Fill out the form
        fill_field("name-input", name)
        fill_field("hitpoints-input", hitpoints)
        fill_field("subname-input", subname)
        fill_field("dexStatsCustom-input", custom_label)
        fill_field("weaknessAmount-input", weakness_amt)
        fill_field("illustrator-input", illustrator)
        fill_field("customSetIconText-input", icon_text)
        fill_field("dexEntry-input", flavor_text)
        fill_field("cardNumber-input", team_number)
        fill_field("totalInSet-input", total_number_in_set)
        fill_field("resistanceAmount-input", resistance_amt)
        # fill_field("retreat-cost-input", retreat_cost)


        # Upload custom regulation mark image
        if custom_regulation_mark_image:
            select_custom_regulation_mark(driver)  # Step 1: Select 'Custom' from the dropdown
            upload_custom_logo(driver, custom_regulation_mark_image)  # Step 2: Upload the logo

        # Upload an image
        upload_input = WebDriverWait(driver, 30).until(
            EC.presence_of_element_located((By.ID, "imgUpload-input"))
        )
        upload_input.send_keys(image_path)
        print("Image uploaded successfully.")

        # Crop the image
        click_crop_button(driver)
        click_advanced_crop_button(driver)
        set_crop_values(driver, image_x, image_y, image_zoom)

        # Add all attacks
        add_attacks(driver, attacks_list)

        # Add all abilities
        add_abilities(driver, abilities_list)

        time.sleep(1)

        # Click the download button
        download_button = WebDriverWait(driver, 30).until(
        EC.element_to_be_clickable((By.XPATH, '//button[contains(text(), "Download")]'))
        )
        safe_click(driver, download_button)
        print("Download initiated.")

        # Wait for the download to complete
        download_wait_time = 10
        for _ in range(download_wait_time):
            if os.path.exists(original_filepath):
                print(f"File downloaded: {original_filepath}")
                break
            time.sleep(1)
        else:
            raise Exception(f"File did not download within {download_wait_time} seconds")

        # Rename the file
        os.rename(original_filepath, renamed_filepath)
        print(f"File renamed to: {renamed_filepath}")

        return renamed_filepath

    except Exception as e:
        print(f"Error creating card: {e}")
        return None
    finally:
        driver.quit()

# Example usage:
if __name__ == "__main__":

    # Example list of attacks
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

    # Example list of abilities
    abilities_list = [ # !!! ONLY ADD ONE ABILITY FOR NOW !!! Does not work with multiple abilities
        # {
        #     "name": "Overload",
        #     "description": "This Robot's attacks deal 30 more damage for each Lightning Energy attached to it.",
        # },
        {
            "name": "Boosted Collection",
            "description": "Once during your turn, if a note is collected from your active robot, another note is collected.",
        },
    ]

    parser = argparse.ArgumentParser()
    parser.add_argument("--team_number", required=True)
    parser.add_argument("--image_path",  required=True)
    parser.add_argument("--output_path", required=True)
    parser.add_argument("--image_x", default="-15")
    parser.add_argument("--image_y", default="-100")
    parser.add_argument("--image_zoom", default="0.95")
    parser.add_argument("--name", default="North Gwinnett Robotics")
    parser.add_argument("--custom_label", default="No. 1771 FRC")
    parser.add_argument("--flavor_text", default="")
    parser.add_argument("--hitpoints", default="150")
    parser.add_argument("--rarity_icon", default="None")
    parser.add_argument("--resistance_type", default="Lightning")
    parser.add_argument("--resistance_amt", default="30")
    parser.add_argument("--card_number", default="1771")
    parser.add_argument("--attacks_list", default="[]")
    parser.add_argument("--abilities_list", default="[]")
    parser.add_argument("--type", default="Metal")

    args = parser.parse_args()

    output_dir = os.path.abspath("./temp_robot_cards")
    os.makedirs(output_dir, exist_ok=True)

    # Example data
    #Specific Things to change
    # team_number = "1771"
    team_number = args.team_number
    # image_path = os.path.abspath("./images/robotImages/1771.jpeg")
    image_path = os.path.abspath(args.image_path)
    image_x = args.image_x
    image_y = args.image_y
    image_zoom = args.image_zoom
    name = args.name
    type_ = args.type
    custom_label = f"No. {team_number} FRC"
    flavor_text = args.flavor_text
    hitpoints = args.hitpoints
    rarity_icon = args.rarity_icon
    resistance_type = args.resistance_type
    resistance_amt = args.resistance_amt
    card_number = f"{team_number}"
    
    attacks_list = json.loads(args.attacks_list)
    abilities_list = json.loads(args.abilities_list)
    
    # Default Stuff
    illustrator = "Logan Peterson"
    custom_regulation_mark_image = os.path.abspath("./images/FIRSTlogo.png")
    base_set = "Sword & Shield"
    supertype = "Pokémon"
    subtype = "Basic"
    variation = "None"
    rarity = "None"
    weakness_type = "Water"
    weakness_amt = "2"
    retreat_cost = "3"
    subname = ""
    icon = "Custom Rectangle"
    icon_text = "PCH"
    total_number_in_set = "10714"


    create_card(
        base_set, supertype, type_, subtype, variation, rarity,
        name, subname, hitpoints, custom_label, weakness_type, weakness_amt,
        resistance_type, resistance_amt, retreat_cost, illustrator, icon_text,
        flavor_text, image_path, image_x, image_y, image_zoom, attacks_list, abilities_list,
        output_dir, team_number, total_number_in_set, custom_regulation_mark_image
    )