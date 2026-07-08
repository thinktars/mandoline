#!/usr/bin/env python3
"""Build a local CLIP index for folders/files of media.

This script intentionally imports heavyweight ML dependencies only after CLI
argument parsing so `--help` works on machines that have not installed the
indexer environment yet.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, Sequence


MODEL_NAME = "hf-hub:laion/CLIP-ViT-H-14-laion2B-s32B-b79K"
DEFAULT_LABELS = [
    # Interfaces and screen captures. Keep these specific so generic
    # "Screenshots" does not swallow every app/site cluster.
    "App Screenshots",
    "Website Screenshots",
    "Mobile App Screens",
    "Landing Pages",
    "Dashboards",
    "Code Editors",
    "Terminal Windows",
    "Error Screens",
    "Settings Screens",
    "Chat Interfaces",
    "Social Media Posts",
    "Maps and Navigation",
    "Calendars",
    "Email Screens",
    "Ecommerce Pages",
    "Product Mockups",
    "Design Mockups",
    "Wireframes",
    "Charts and Graphs",
    "Data Tables",
    # Documents and work artifacts.
    "Documents",
    "PDF Pages",
    "Receipts",
    "Invoices",
    "Forms",
    "Spreadsheets",
    "Presentations",
    "Whiteboards",
    "Handwritten Notes",
    "Text Notes",
    "Book Pages",
    # Brand, graphics, and internet ephemera.
    "Logos",
    "Brand Assets",
    "Icons",
    "Illustrations",
    "Posters",
    "Flyers",
    "Memes",
    "Stickers",
    "Diagrams",
    # Photos and videos.
    "People",
    "Selfies",
    "Portraits",
    "Groups of People",
    "Pets",
    "Food",
    "Restaurants",
    "Products",
    "Clothing",
    "Shoes",
    "Cars",
    "Architecture",
    "Home Interiors",
    "Furniture",
    "Nature",
    "Plants",
    "Beaches",
    "Mountains",
    "Travel",
    "Street Scenes",
    "Sports",
    "Events",
    "Concerts",
    "Fitness",
    "Art",
    "Other",
]
TEXT_PROMPT_TEMPLATES = [
    "a clear image of {label}",
    "a screenshot or photo showing {label}",
    "a collection of {label}",
    "a visual example of {label}",
]
FILENAME_HINTS = [
    (("xcode", "vscode", "visual studio", "cursor", "sublime", "atom"), "Code Editor Screenshots"),
    (("terminal", "iterm", "warp", "console", "shell"), "Terminal Screenshots"),
    (("figma",), "Figma Screenshots"),
    (("framer",), "Framer Screenshots"),
    (("webflow",), "Webflow Screenshots"),
    (("github", "pull request", "pr-", "issue"), "GitHub Screenshots"),
    (("linear",), "Linear Screenshots"),
    (("notion",), "Notion Screenshots"),
    (("slack",), "Slack Screenshots"),
    (("discord",), "Discord Screenshots"),
    (("chatgpt", "openai"), "ChatGPT Screenshots"),
    (("claude", "anthropic"), "Claude Screenshots"),
    (("safari", "chrome", "firefox", "browser"), "Browser Screenshots"),
    (("stripe",), "Stripe Screenshots"),
    (("shopify",), "Shopify Screenshots"),
    (("cloudflare",), "Cloudflare Screenshots"),
    (("supabase",), "Supabase Screenshots"),
    (("adobe", "photoshop", "illustrator", "lightroom", "express"), "Adobe Assets"),
    (("canva",), "Canva Designs"),
    (("invoice",), "Invoices"),
    (("receipt",), "Receipts"),
    (("resume", "cv"), "Documents"),
    (("logo", "wordmark", "brand"), "Brand Assets"),
    (("mockup",), "Product Mockups"),
    (("dash", "dashboard", "analytics"), "Dashboards"),
    (("error", "exception", "crash", "bug"), "Error Screens"),
]
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".heic", ".heif", ".webp", ".tiff", ".tif", ".gif"}
VIDEO_EXTENSIONS = {".mp4", ".mov", ".m4v", ".avi", ".mkv", ".webm"}
HEIF_EXTENSIONS = {".heic", ".heif"}
HEIF_REGISTERED = False


@dataclass(frozen=True)
class MediaRecord:
    path: Path
    kind: str


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create a Mandoline Phase 2 CLIP JSON index for local images and videos.",
    )
    parser.add_argument(
        "--input",
        action="append",
        required=True,
        metavar="PATH",
        help="Input folder or file. Repeat this flag to index multiple roots.",
    )
    parser.add_argument("--output", required=True, metavar="JSON", help="Output JSON file path.")
    parser.add_argument(
        "--labels",
        default=None,
        help="Optional comma-separated category labels. Defaults to Mandoline's built-in labels.",
    )
    parser.add_argument(
        "--max-images",
        type=positive_int,
        default=None,
        help="Optional maximum number of media files to index after deterministic traversal.",
    )
    parser.add_argument(
        "--device",
        choices=("auto", "mps", "cpu"),
        default="auto",
        help="Torch device to use. 'auto' prefers Apple MPS when available, otherwise CPU.",
    )
    parser.add_argument(
        "--offline",
        action="store_true",
        help="Force Hugging Face/offline cache mode. The model must already be cached.",
    )
    parser.add_argument(
        "--include-embeddings",
        action="store_true",
        help="Include each image embedding in the output JSON. Disabled by default to keep files small.",
    )
    parser.add_argument(
        "--clusters",
        type=positive_int,
        default=None,
        help="Optional number of clusters to compute. Defaults to a deterministic size based on item count.",
    )
    parser.add_argument(
        "--batch-size",
        type=positive_int,
        default=16,
        help="Images/keyframes per CLIP image batch. Increase for speed if memory allows; lower if the machine gets too hot.",
    )
    return parser.parse_args(argv)


def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed < 1:
        raise argparse.ArgumentTypeError("must be a positive integer")
    return parsed


def parse_labels(raw: str | None) -> list[str]:
    if raw is None:
        return DEFAULT_LABELS[:]
    labels = [part.strip() for part in raw.split(",") if part.strip()]
    if not labels:
        raise SystemExit("--labels did not contain any non-empty labels")
    return labels


def configure_offline_mode(enabled: bool) -> None:
    if not enabled:
        return
    os.environ.setdefault("HF_HUB_OFFLINE", "1")
    os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
    os.environ.setdefault("HF_DATASETS_OFFLINE", "1")


def load_runtime_dependencies() -> tuple[Any, Any, Any, Any]:
    missing: list[str] = []
    try:
        import open_clip  # type: ignore
    except ModuleNotFoundError:
        open_clip = None
        missing.append("open_clip (install package: open_clip_torch)")

    try:
        import torch  # type: ignore
    except ModuleNotFoundError:
        torch = None
        missing.append("torch")

    try:
        from PIL import Image  # type: ignore
    except ModuleNotFoundError:
        Image = None
        missing.append("Pillow (module: PIL)")

    if Image is not None:
        register_optional_heif_opener()

    try:
        import numpy as np  # type: ignore
    except ModuleNotFoundError:
        np = None
        missing.append("numpy")

    if missing:
        raise SystemExit(
            "Missing runtime dependency/dependencies: "
            + ", ".join(missing)
            + ". Install with: python3 -m pip install -r tools/clip/requirements.txt"
        )
    return open_clip, torch, Image, np


def register_optional_heif_opener() -> None:
    """Register pillow-heif when available so Pillow can decode HEIC/HEIF files."""
    global HEIF_REGISTERED
    try:
        from pillow_heif import register_heif_opener  # type: ignore
    except ModuleNotFoundError:
        HEIF_REGISTERED = False
        return

    register_heif_opener()
    HEIF_REGISTERED = True


def resolve_device(torch: Any, requested: str) -> Any:
    if requested == "cpu":
        return torch.device("cpu")
    mps_backend = getattr(torch.backends, "mps", None)
    mps_available = bool(
        mps_backend is not None
        and mps_backend.is_available()
        and getattr(mps_backend, "is_built", lambda: True)()
    )
    if requested == "mps":
        if not mps_available:
            raise SystemExit("--device mps was requested, but torch MPS is not available on this system")
        return torch.device("mps")
    return torch.device("mps" if mps_available else "cpu")


def discover_media(inputs: Iterable[str]) -> list[MediaRecord]:
    records: dict[str, MediaRecord] = {}
    for raw in inputs:
        root = Path(raw).expanduser()
        if not root.exists():
            raise SystemExit(f"Input path does not exist: {root}")
        candidates = [root] if root.is_file() else sorted((p for p in root.rglob("*") if p.is_file()), key=path_sort_key)
        for path in candidates:
            suffix = path.suffix.lower()
            kind: str | None = None
            if suffix in IMAGE_EXTENSIONS:
                kind = "image"
            elif suffix in VIDEO_EXTENSIONS:
                kind = "video"
            if kind is None:
                continue
            absolute = path.resolve()
            records[str(absolute)] = MediaRecord(path=absolute, kind=kind)
    return [records[key] for key in sorted(records)]


def path_sort_key(path: Path) -> str:
    return str(path).casefold()


def load_media_image(record: MediaRecord, Image: Any) -> Any | None:
    if record.kind == "image":
        if record.path.suffix.lower() in HEIF_EXTENSIONS and not HEIF_REGISTERED:
            print(
                f"warning: skipped HEIF image {record.path}: install pillow-heif and rerun "
                "python3 -m pip install -r tools/clip/requirements.txt",
                file=sys.stderr,
            )
            return None
        try:
            with Image.open(record.path) as image:
                if getattr(image, "is_animated", False):
                    image.seek(0)
                return image.convert("RGB")
        except Exception as exc:  # noqa: BLE001 - data-dependent decoding failures should skip one file.
            print(f"warning: skipped image {record.path}: {exc}", file=sys.stderr)
            return None
    frame = extract_video_frame(record.path, Image)
    if frame is None:
        print(
            f"warning: skipped video {record.path}: install opencv-python or imageio[ffmpeg] for frame extraction",
            file=sys.stderr,
        )
    return frame


def extract_video_frame(path: Path, Image: Any) -> Any | None:
    try:
        import cv2  # type: ignore

        capture = cv2.VideoCapture(str(path))
        try:
            ok, frame = capture.read()
        finally:
            capture.release()
        if ok and frame is not None:
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            return Image.fromarray(rgb).convert("RGB")
    except ModuleNotFoundError:
        pass
    except Exception as exc:  # noqa: BLE001
        print(f"warning: opencv could not decode {path}: {exc}", file=sys.stderr)

    try:
        import imageio.v3 as iio  # type: ignore

        frame = iio.imread(path, index=0)
        return Image.fromarray(frame).convert("RGB")
    except ModuleNotFoundError:
        return None
    except Exception as exc:  # noqa: BLE001
        print(f"warning: imageio could not decode {path}: {exc}", file=sys.stderr)
        return None


def load_clip_model(open_clip: Any, torch: Any, device: Any) -> tuple[Any, Any, Any]:
    try:
        model, preprocess_train, preprocess_val = open_clip.create_model_and_transforms(MODEL_NAME)
        tokenizer = open_clip.get_tokenizer(MODEL_NAME)
    except Exception as exc:  # noqa: BLE001
        raise SystemExit(
            f"Failed to load CLIP model {MODEL_NAME}: {exc}. "
            "If --offline is set, verify the Hugging Face/open_clip cache is already populated."
        ) from exc
    del preprocess_train
    model.eval()
    model.to(device)
    return model, preprocess_val, tokenizer


def emit_progress(stage: str, done: int, total: int, message: str) -> None:
    print(
        json.dumps(
            {
                "type": "progress",
                "stage": stage,
                "done": int(done),
                "total": int(total),
                "message": message,
            },
            separators=(",", ":"),
        ),
        flush=True,
    )


def encode_images(
    records: Sequence[MediaRecord],
    model: Any,
    preprocess_val: Any,
    torch: Any,
    Image: Any,
    np: Any,
    device: Any,
    batch_size: int,
) -> tuple[list[str], Any]:
    paths: list[str] = []
    embeddings: list[Any] = []
    total = len(records)
    decoded_since_batch = 0
    batch_tensors: list[Any] = []
    batch_paths: list[str] = []

    def flush_batch(done_count: int) -> None:
        nonlocal batch_tensors, batch_paths, decoded_since_batch
        if not batch_tensors:
            return
        with torch.no_grad():
            tensor = torch.stack(batch_tensors, dim=0).to(device)
            features = model.encode_image(tensor)
            features = features / features.norm(dim=-1, keepdim=True)
            embeddings.append(features.detach().cpu().float().numpy())
            paths.extend(batch_paths)
        batch_tensors = []
        batch_paths = []
        decoded_since_batch = 0
        emit_progress("embedding", done_count, total, f"Embedded {done_count}/{total} media files with CLIP")

    emit_progress("embedding", 0, total, f"Embedding 0/{total} media files with CLIP")
    for index, record in enumerate(records, start=1):
        image = load_media_image(record, Image)
        if image is not None:
            batch_tensors.append(preprocess_val(image))
            batch_paths.append(str(record.path))
            decoded_since_batch += 1
        if decoded_since_batch >= batch_size:
            flush_batch(index)
        elif index % max(1, batch_size) == 0:
            emit_progress("embedding", index, total, f"Decoded {index}/{total} media files")

    flush_batch(total)
    if not embeddings:
        raise SystemExit("No media files could be decoded and embedded")
    return paths, np.vstack(embeddings).astype("float32")


def prompts_for_label(label: str) -> list[str]:
    normalized = label.strip().lower()
    prompts = [template.format(label=normalized) for template in TEXT_PROMPT_TEMPLATES]
    if "screenshot" in normalized or "screen" in normalized or "interface" in normalized:
        prompts.extend(
            [
                f"a desktop screenshot of {normalized}",
                f"a user interface screen showing {normalized}",
            ]
        )
    if "photo" not in normalized and normalized not in {"documents", "pdf pages", "receipts", "invoices", "forms"}:
        prompts.append(f"a photo containing {normalized}")
    return prompts


def encode_text(labels: Sequence[str], model: Any, tokenizer: Any, torch: Any, np: Any, device: Any) -> Any:
    prompt_groups: list[tuple[int, int]] = []
    prompts: list[str] = []
    for label in labels:
        start = len(prompts)
        prompts.extend(prompts_for_label(label))
        prompt_groups.append((start, len(prompts)))

    encoded_batches: list[Any] = []
    batch_size = 128
    with torch.no_grad():
        for start in range(0, len(prompts), batch_size):
            tokens = tokenizer(prompts[start : start + batch_size]).to(device)
            features = model.encode_text(tokens)
            features = features / features.norm(dim=-1, keepdim=True)
            encoded_batches.append(features.detach().cpu().float().numpy().astype("float32"))

    prompt_embeddings = np.vstack(encoded_batches)
    label_embeddings = []
    for start, end in prompt_groups:
        mean = prompt_embeddings[start:end].mean(axis=0)
        norm = np.linalg.norm(mean)
        label_embeddings.append(mean / norm if norm else mean)
    return np.vstack(label_embeddings).astype("float32")


def similarity_matrix(np: Any, lhs: Any, rhs: Any) -> Any:
    """Stable cosine-similarity matrix for already-normalized embeddings.

    NumPy's Accelerate-backed matmul can emit overflow warnings on macOS for
    float32 arrays even when inputs/results are finite. A float64 einsum avoids
    that noisy path and keeps scores deterministic for the small label/cluster
    matrices Mandoline needs.
    """
    lhs64 = np.asarray(lhs, dtype="float64")
    rhs64 = np.asarray(rhs, dtype="float64")
    result = np.einsum("id,jd->ij", lhs64, rhs64)
    return np.nan_to_num(result, nan=0.0, posinf=1.0, neginf=-1.0).astype("float32")


def softmax_scores(similarities: Any, np: Any) -> Any:
    similarities = np.nan_to_num(similarities, nan=0.0, posinf=1.0, neginf=-1.0)
    shifted = similarities - np.max(similarities, axis=-1, keepdims=True)
    exp = np.exp(shifted)
    denominator = np.sum(exp, axis=-1, keepdims=True)
    return exp / np.maximum(denominator, 1e-12)


def label_entries(labels: Sequence[str], probabilities: Any, limit: int = 3) -> list[dict[str, Any]]:
    ranked = sorted(range(len(labels)), key=lambda idx: (-float(probabilities[idx]), labels[idx]))[:limit]
    return [{"label": labels[idx], "score": round(float(probabilities[idx]), 6)} for idx in ranked]


def filename_hint(paths: Sequence[str]) -> str | None:
    haystack = " ".join(Path(path).stem.lower().replace("_", " ").replace("-", " ") for path in paths[:40])
    for terms, label in FILENAME_HINTS:
        if any(term in haystack for term in terms):
            return label
    return None


def choose_cluster_label(labels: Sequence[str], probabilities: Any, member_paths: Sequence[str]) -> tuple[str, float]:
    ranked = sorted(range(len(labels)), key=lambda idx: (-float(probabilities[idx]), labels[idx]))
    top_idx = ranked[0]
    top_label = labels[top_idx]
    top_score = float(probabilities[top_idx])

    hint = filename_hint(member_paths)
    if hint is not None:
        generic_screen_labels = {
            "App Screenshots",
            "Website Screenshots",
            "Mobile App Screens",
            "Desktop Screenshots",
            "Chat Interfaces",
        }
        generic_work_labels = {"Documents", "Other", "Design Mockups", "Product Mockups"}
        if top_label in generic_screen_labels or top_label in generic_work_labels or top_score < 0.24:
            return hint, top_score

    if top_label == "Other" and len(ranked) > 1:
        second_idx = ranked[1]
        if float(probabilities[second_idx]) >= top_score - 0.025:
            return labels[second_idx], float(probabilities[second_idx])

    return top_label, top_score


def choose_cluster_count(item_count: int, requested: int | None) -> int:
    if requested is not None:
        return min(requested, item_count)
    return min(8, max(1, int(round(math.sqrt(item_count)))))


def deterministic_kmeans(np: Any, embeddings: Any, cluster_count: int, max_iterations: int = 50) -> tuple[Any, Any]:
    n = embeddings.shape[0]
    k = min(cluster_count, n)
    centers = initialize_centers(np, embeddings, k)
    assignments = np.zeros(n, dtype="int64")
    for _ in range(max_iterations):
        distances = squared_distances(np, embeddings, centers)
        new_assignments = np.argmin(distances, axis=1)
        new_centers = centers.copy()
        for cluster_id in range(k):
            members = embeddings[new_assignments == cluster_id]
            if len(members):
                center = members.mean(axis=0)
                norm = np.linalg.norm(center)
                new_centers[cluster_id] = center / norm if norm else center
        if np.array_equal(assignments, new_assignments) and np.allclose(centers, new_centers):
            assignments = new_assignments
            centers = new_centers
            break
        assignments = new_assignments
        centers = new_centers
    return assignments, centers


def initialize_centers(np: Any, embeddings: Any, k: int) -> Any:
    selected_indices = [0]
    centers = [embeddings[0]]
    while len(centers) < k:
        current = np.vstack(centers)
        distances = squared_distances(np, embeddings, current)
        min_distances = np.min(distances, axis=1)
        min_distances[selected_indices] = -1.0
        next_idx = int(np.argmax(min_distances))
        selected_indices.append(next_idx)
        centers.append(embeddings[next_idx])
    return np.vstack(centers).astype("float32")


def squared_distances(np: Any, points: Any, centers: Any) -> Any:
    deltas = points[:, None, :] - centers[None, :, :]
    return np.sum(deltas * deltas, axis=2)


def cluster_positions(np: Any, centers: Any) -> list[dict[str, float]]:
    if centers.shape[1] == 1:
        raw = np.column_stack([centers[:, 0], np.zeros(centers.shape[0], dtype="float32")])
    else:
        raw = centers[:, :2]
    positions: list[dict[str, float]] = []
    mins = raw.min(axis=0)
    maxs = raw.max(axis=0)
    spans = maxs - mins
    for row in raw:
        coords: list[float] = []
        for axis in range(2):
            if float(spans[axis]) == 0.0:
                coords.append(0.5)
            else:
                coords.append(float((row[axis] - mins[axis]) / spans[axis]))
        positions.append({"x": round(clamp(coords[0]), 6), "y": round(clamp(coords[1]), 6)})
    return positions


def clamp(value: float) -> float:
    return max(0.0, min(1.0, value))


def build_items(paths: Sequence[str], embeddings: Any, labels: Sequence[str], probabilities: Any, include_embeddings: bool) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    for idx, path in enumerate(paths):
        item: dict[str, Any] = {
            "path": path,
            "labels": label_entries(labels, probabilities[idx]),
        }
        if include_embeddings:
            item["embedding"] = [round(float(value), 7) for value in embeddings[idx].tolist()]
        items.append(item)
    return items


def build_clusters(
    np: Any,
    paths: Sequence[str],
    embeddings: Any,
    labels: Sequence[str],
    text_embeddings: Any,
    item_probabilities: Any,
    cluster_count: int,
) -> list[dict[str, Any]]:
    assignments, centers = deterministic_kmeans(np, embeddings, cluster_count)
    similarities = similarity_matrix(np, centers, text_embeddings)
    center_probabilities = softmax_scores(similarities, np)
    positions = cluster_positions(np, centers)
    clusters: list[dict[str, Any]] = []
    for cluster_id in range(centers.shape[0]):
        member_indices = [idx for idx in range(len(paths)) if int(assignments[idx]) == cluster_id]
        member_paths = [paths[idx] for idx in member_indices]
        if not member_paths:
            continue
        mean_item_probabilities = item_probabilities[member_indices].mean(axis=0)
        combined_probabilities = (center_probabilities[cluster_id] * 0.58) + (mean_item_probabilities * 0.42)
        label, score = choose_cluster_label(labels, combined_probabilities, member_paths)
        clusters.append(
            {
                "id": int(cluster_id),
                "label": label,
                "score": round(float(score), 6),
                "paths": member_paths,
                "position": positions[cluster_id],
            }
        )
    return clusters


def atomic_write_json(output_path: Path, payload: dict[str, Any]) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=output_path.parent, delete=False) as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")
        temp_name = handle.name
    Path(temp_name).replace(output_path)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    labels = parse_labels(args.labels)
    configure_offline_mode(args.offline)

    records = discover_media(args.input)
    if args.max_images is not None:
        records = records[: args.max_images]
    if not records:
        raise SystemExit("No supported image or video files found in the requested input path(s)")
    emit_progress("discovered", 0, len(records), f"Found {len(records)} supported media files")

    open_clip, torch, Image, np = load_runtime_dependencies()
    device = resolve_device(torch, args.device)
    emit_progress("loading_model", 0, len(records), f"Loading CLIP model on {device}")
    model, preprocess_val, tokenizer = load_clip_model(open_clip, torch, device)

    paths, image_embeddings = encode_images(records, model, preprocess_val, torch, Image, np, device, args.batch_size)
    emit_progress("labeling", len(paths), len(records), "Scoring category labels")
    text_embeddings = encode_text(labels, model, tokenizer, torch, np, device)
    label_probabilities = softmax_scores(similarity_matrix(np, image_embeddings, text_embeddings), np)
    cluster_count = choose_cluster_count(len(paths), args.clusters)

    payload = {
        "version": 1,
        "model": MODEL_NAME,
        "embedding_dimension": int(image_embeddings.shape[1]),
        "items": build_items(paths, image_embeddings, labels, label_probabilities, args.include_embeddings),
        "clusters": build_clusters(np, paths, image_embeddings, labels, text_embeddings, label_probabilities, cluster_count),
    }
    atomic_write_json(Path(args.output).expanduser(), payload)
    print(f"wrote {len(paths)} item(s) and {len(payload['clusters'])} cluster(s) to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
