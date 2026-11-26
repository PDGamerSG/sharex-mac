"""Resize a PNG for screenshot output or offline recognition using the desktop image loader."""
import sys
import gi

gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf

if __name__ == "__main__":
    source, width, height, target = sys.argv[1:]
    try:
        image = GdkPixbuf.Pixbuf.new_from_file_at_scale(source, int(width), int(height), False)
        image.savev(target, "png", [], [])
    except Exception as error:
        sys.exit(str(error))
