#!/usr/bin/env python3
import importlib.util
import sys
from pathlib import Path

module_path = Path(__file__).resolve().parents[2] / "tools" / "clip" / "index_folder.py"
spec = importlib.util.spec_from_file_location("clip_index_folder", module_path)
clip = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = clip
spec.loader.exec_module(clip)

assert "Screenshots" not in clip.DEFAULT_LABELS
assert "Code Editors" in clip.DEFAULT_LABELS
assert "Landing Pages" in clip.DEFAULT_LABELS
assert "Product Mockups" in clip.DEFAULT_LABELS

figma = clip.filename_hint(["/Users/me/Desktop/Figma checkout-flow 2026.png"])
assert figma == "Figma Screenshots", figma

chatgpt = clip.filename_hint(["/tmp/ChatGPT Image July 8.png"])
assert chatgpt == "ChatGPT Screenshots", chatgpt

class FakeProb:
    def __init__(self, values):
        self.values = values
    def __getitem__(self, index):
        return self.values[index]

labels = ["Other", "App Screenshots", "Code Editors"]
label, score = clip.choose_cluster_label(labels, FakeProb([0.4, 0.38, 0.22]), ["/tmp/xcode-build-log.png"])
assert label == "Code Editor Screenshots", label
assert score == 0.4

label, score = clip.choose_cluster_label(labels, FakeProb([0.4, 0.395, 0.205]), ["/tmp/unknown.png"])
assert label == "App Screenshots", label
assert score == 0.395

print("clip labeling helpers ok")
