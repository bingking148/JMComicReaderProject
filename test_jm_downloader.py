
import jmcomic

try:
    from jmcomic import JmDownloader
    print("JmDownloader found")
    print(dir(JmDownloader))
    
    # Check if there is a method to download image
    # usually download_image(self, image_url, path, scramble_id)
except ImportError:
    print("JmDownloader NOT found")
