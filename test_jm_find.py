
import jmcomic
import inspect

def find_class(module, class_name):
    for name, obj in inspect.getmembers(module):
        if name == class_name:
            print(f"Found {class_name} in {module.__name__}")
            return obj
        if inspect.ismodule(obj) and obj.__name__.startswith('jmcomic'):
            try:
                find_class(obj, class_name)
            except:
                pass

print("Searching for JmImageSupport...")
find_class(jmcomic, "JmImageSupport")
