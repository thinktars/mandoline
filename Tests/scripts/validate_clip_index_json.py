#!/usr/bin/env python3
import json, sys
from pathlib import Path

p = Path(sys.argv[1])
data = json.loads(p.read_text())
assert data["version"] == 1
assert data["model"].startswith("hf-hub:laion/CLIP-ViT-H-14")
assert isinstance(data["embedding_dimension"], int) and data["embedding_dimension"] > 0
assert isinstance(data["items"], list) and data["items"]
assert isinstance(data["clusters"], list) and data["clusters"]
for item in data["items"]:
    assert Path(item["path"]).is_absolute()
    if "embedding" in item:
        assert isinstance(item["embedding"], list) and item["embedding"]
        assert all(isinstance(value, (int, float)) for value in item["embedding"])
    assert isinstance(item.get("labels", []), list)
for cluster in data["clusters"]:
    assert isinstance(cluster["id"], int)
    assert cluster["label"]
    assert isinstance(cluster["paths"], list) and cluster["paths"]
    assert 0 <= cluster["position"]["x"] <= 1
    assert 0 <= cluster["position"]["y"] <= 1
print("clip index json contract ok")
