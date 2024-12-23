import os
import requests

# Base URLs for scraping
base_icons_url = "https://pokecardmaker.net/assets/icons/types/swordAndShield/border/"
base_cards_url = "https://pokecardmaker.net/assets/cards/baseSets/swordAndShield/supertypes/pokemon/types/"

# Categories to try for 'border'
icon_types = ["dark", "water", "fairy", "fire", "grass", "electric", "psychic", "fighting", "dragon", "metal"]

# Subdirectories to try for cards
card_types = ["dark", "water", "fairy", "fire", "grass", "electric", "psychic", "fighting", "dragon", "metal"]
card_subtypes = ["basic", "stage1", "stage2"]

# Directory to save images
os.makedirs("downloaded_images/icons", exist_ok=True)
os.makedirs("downloaded_images/cards", exist_ok=True)

def download_image(url, save_path):
    """Download an image from the URL and save it to the specified path."""
    try:
        response = requests.get(url)
        if response.status_code == 200:
            with open(save_path, 'wb') as file:
                file.write(response.content)
            print(f"Downloaded: {url}")
        else:
            print(f"Failed (status {response.status_code}): {url}")
    except Exception as e:
        print(f"Error downloading {url}: {e}")

# Download icons (borders)
for icon_type in icon_types:
    url = f"{base_icons_url}{icon_type}.png"
    save_path = f"downloaded_images/icons/{icon_type}.png"
    download_image(url, save_path)

# Download cards
for card_type in card_types:
    for subtype in card_subtypes:
        url = f"{base_cards_url}{card_type}/subtypes/{subtype}.png"
        save_path = f"downloaded_images/cards/{card_type}_{subtype}.png"
        download_image(url, save_path)

print("Scraping completed!")
