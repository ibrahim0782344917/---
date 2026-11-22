import importlib.util
import struct
import tempfile
import unittest
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1] / 'scripts/configure_alani_icon.py'
spec = importlib.util.spec_from_file_location("alani_icon", SOURCE)
icon = importlib.util.module_from_spec(spec)
spec.loader.exec_module(icon)

class AlAniBrandTest(unittest.TestCase):
    def test_png_generated_for_every_android_density(self):
        for n in [48,72,96,144,192]:
            data=icon.png(n)
            self.assertTrue(data.startswith(b'\x89PNG\r\n\x1a\n'))
            self.assertEqual(struct.unpack(">II", data[16:24]),(n,n))

    def test_launcher_label_changes_without_touching_package(self):
        with tempfile.TemporaryDirectory() as tmp:
            app=Path(tmp)
            file=app/"android/app/src/main/AndroidManifest.xml"
            file.parent.mkdir(parents=True)
            file.write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application android:label="old" android:icon="@mipmap/ic_launcher"/></manifest>')
            icon.configure(app,'admin')
            new=file.read_text()
            self.assertIn('السيد إبراهيم العاني - الإدارة',new)
            self.assertTrue((app/"android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png").exists())

if __name__=="__main__":
    unittest.main()
