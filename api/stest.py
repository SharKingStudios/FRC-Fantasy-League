from selenium.webdriver.chrome.service import Service
from selenium.webdriver.chrome.options import Options
from selenium import webdriver

service = Service("/home/sharkingstudios/ungoogled-chromium-114/ungoogled-chromium_114.0.5735.198-1.1_linux/chromedriver")
options = Options()
options.binary_location = "/home/sharkingstudios/ungoogled-chromium-114/ungoogled-chromium_114.0.5735.198-1.1_linux/chrome"
options.add_argument("--headless")
options.add_argument("--no-sandbox")
options.add_argument("--disable-dev-shm-usage")

driver = webdriver.Chrome(service=service, options=options)
driver.get("https://www.google.com")
print(driver.title)
driver.quit()
