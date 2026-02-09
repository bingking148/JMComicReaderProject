
import jmcomic
import sys

try:
    from jmcomic import JmImageSupport
    print("JmImageSupport found")
    print(dir(JmImageSupport))
except ImportError:
    print("JmImageSupport NOT found in top level")
    try:
        from jmcomic.jm_toolkit import JmImageSupport
        print("JmImageSupport found in toolkit")
    except ImportError:
        print("JmImageSupport NOT found in toolkit")

# Check where decode logic might be
print(f"jmcomic version: {jmcomic.__version__}")
