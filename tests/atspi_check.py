from dogtail.tree import root
try:
    print("Connecting to AT-SPI...")
    apps = root.applications()
    print("Connected!")
    for app in apps:
        print(f"App: {app.name}")
except Exception as e:
    print(f"Failed: {e}")
