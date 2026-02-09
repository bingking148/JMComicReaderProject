
import jmcomic
import requests

option = jmcomic.create_option_by_file("test_option.yml")
client = option.build_jm_client()
domain = client.domain_list[0]
aid = "438696"

patterns = [
    f"https://{domain}/media/albums/{aid}.jpg",
    f"https://{domain}/media/albums/{aid}_300x400.jpg",
    f"https://{domain}/media/albums/{aid}_small.jpg",
    f"https://{domain}/media/photos/{aid}.jpg",
]

for url in patterns:
    print(f"Trying: {url}")
    try:
        headers = {"User-Agent": "Mozilla/5.0"}
        resp = requests.head(url, headers=headers)
        print(f"Status: {resp.status_code}")
    except:
        pass
