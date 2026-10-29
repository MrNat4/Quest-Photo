"""Check delivered calibration pixels, including eye order and disparity."""
from pathlib import Path
import unittest

from PIL import Image, ImageChops

ASSETS = Path(__file__).resolve().parents[1] / "assets"


class StereoAssetTests(unittest.TestCase):
    def setUp(self):
        self.left = Image.open(ASSETS / "stereo_left.png").convert("RGB")
        self.right = Image.open(ASSETS / "stereo_right.png").convert("RGB")
        self.sbs = Image.open(ASSETS / "stereo_test_sbs.png").convert("RGB")

    def test_eye_order_and_full_sbs_dimensions(self):
        self.assertEqual(self.left.size, (1024, 768))
        self.assertEqual(self.right.size, self.left.size)
        self.assertEqual(self.sbs.size, (2048, 768))
        self.assertIsNone(ImageChops.difference(
            self.sbs.crop((0, 0, 1024, 768)), self.left).getbbox())
        self.assertIsNone(ImageChops.difference(
            self.sbs.crop((1024, 0, 2048, 768)), self.right).getbbox())
        self.assertIsNotNone(ImageChops.difference(self.left, self.right).getbbox())

    def test_disparity_geometry_from_actual_pixels(self):
        # Independent expected geometry; do not use generator metadata.
        expectations = [((61, 224, 168), 24), ((245, 200, 72), 0),
                        ((92, 167, 255), -16)]
        for color, expected_disparity in expectations:
            centers = []
            for image in (self.left, self.right):
                coords = [(x, y) for y in range(280, 480)
                          for x in range(128, 896) if image.getpixel((x, y)) == color]
                self.assertGreater(len(coords), 10000)
                centers.append((sum(p[0] for p in coords)/len(coords),
                                sum(p[1] for p in coords)/len(coords)))
            self.assertAlmostEqual(centers[0][0]-centers[1][0], expected_disparity)
            self.assertAlmostEqual(centers[0][1], centers[1][1])

    def test_grid_is_at_zero_disparity(self):
        # Away from the intentional eye label and depth targets.
        self.assertIsNone(ImageChops.difference(
            self.left.crop((40, 165, 980, 270)),
            self.right.crop((40, 165, 980, 270))).getbbox())

    def test_real_photo_is_decodable(self):
        with Image.open(ASSETS / "sample_photo.jpg") as photo:
            self.assertEqual(photo.format, "JPEG")
            self.assertEqual(photo.size, (512, 600))
            photo.load()


if __name__ == "__main__":
    unittest.main()
