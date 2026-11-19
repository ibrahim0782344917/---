"""Safe offline tests for Android signing configuration; no actual key is used."""
import base64
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parent / "configure_android_release.py"
FAKE_GRADLE = """plugins {
    id("com.android.application")
}
android {
    namespace = "com.shitreed.shitreed_customer"
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}
"""


class SigningPreflightTests(unittest.TestCase):
    def prepare(self, root):
        config = Path(root) / "android" / "app" / "build.gradle.kts"
        config.parent.mkdir(parents=True)
        config.write_text(FAKE_GRADLE, encoding="utf-8")
        return config

    def exec_script(self, root, **variables):
        env = {key: value for key, value in os.environ.items()
               if not key.startswith("ANDROID_UPLOAD_")}
        env.update(variables)
        return subprocess.run([sys.executable, str(SCRIPT)],
                              cwd=root, env=env, text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def test_missing_signing_secrets_fail_without_writing_a_key(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.prepare(tmp)
            result = self.exec_script(tmp)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((Path(tmp)/"android"/"upload-keystore.jks").exists())

    def test_invalid_data_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.prepare(tmp)
            result = self.exec_script(tmp,
                ANDROID_UPLOAD_KEYSTORE_BASE64="not-base64",
                ANDROID_UPLOAD_STORE_PASSWORD="fake123",
                ANDROID_UPLOAD_KEY_ALIAS="release",
                ANDROID_UPLOAD_KEY_PASSWORD="fake123")
            self.assertNotEqual(result.returncode, 0)

    def test_gradle_template_switches_to_release_only(self):
        with tempfile.TemporaryDirectory() as tmp:
            config = self.prepare(tmp)
            result = self.exec_script(tmp,
                ANDROID_UPLOAD_KEYSTORE_BASE64=base64.b64encode(b"x"*256).decode(),
                ANDROID_UPLOAD_STORE_PASSWORD="not-a-real-password",
                ANDROID_UPLOAD_KEY_ALIAS="upload",
                ANDROID_UPLOAD_KEY_PASSWORD="not-a-real-password")
            self.assertEqual(result.returncode, 0, result.stderr)
            changed = config.read_text()
            self.assertIn('create("release")', changed)
            self.assertIn('signingConfig = signingConfigs.getByName("release")',
                          changed)
            self.assertNotIn('signingConfig = signingConfigs.getByName("debug")',
                             changed)
            self.assertNotIn("not-a-real-password", changed)
            self.assertEqual(
                (Path(tmp)/"android"/"upload-keystore.jks").read_bytes(),
                b"x"*256)


if __name__ == "__main__":
    unittest.main()
