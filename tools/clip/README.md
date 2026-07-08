# Mandoline CLIP Indexer

Python helper for Mandoline Phase 2 CLIP indexing. It uses `open_clip` with the Hugging Face model `hf-hub:laion/CLIP-ViT-H-14-laion2B-s32B-b79K` to label media and write a JSON index.

Labels are generated locally by scoring image/video embeddings against Mandoline's built-in text-label taxonomy. This is much cheaper than captioning each image: the expensive part is embedding the media, then scoring hundreds of text prompts is small. The default taxonomy intentionally avoids a generic `Screenshots` bucket and instead uses specific local labels such as `Code Editors`, `Landing Pages`, `Product Mockups`, `Dashboards`, `Error Screens`, `Documents`, `Brand Assets`, and photo categories. Cluster titles also use filename hints for common tools like Figma, GitHub, ChatGPT, Xcode, Terminal, Stripe, Shopify, and Cloudflare.

## Setup

```bash
cd /Users/rowan/Programming/tars/mandoline
python3 -m venv .venv-clip
source .venv-clip/bin/activate
python3 -m pip install -r tools/clip/requirements.txt
```

`pillow-heif` is included so HEIC/HEIF images can be decoded by Pillow. If it is missing, HEIC/HEIF files are skipped with a warning.

Video frame extraction uses `imageio[ffmpeg]`, included in `requirements.txt`. If you prefer OpenCV for video decoding, you can also install it into the venv:

```bash
python3 -m pip install opencv-python
```

## First model download / cache warm-up

The Mandoline app invokes this helper with `--offline` by default for privacy. Before using Auto-categories in the app, run one terminal command without `--offline` so Hugging Face/open_clip can download and cache the model:

```bash
. .venv-clip/bin/activate
python3 tools/clip/index_folder.py --input /path/to/media --output /tmp/mandoline_clip_warmup.json
```

After the model is cached, use `--offline` to verify the app's default mode will work:

```bash
python3 tools/clip/index_folder.py --input /path/to/media --output /tmp/mandoline_clip_check.json --offline
```

If `--offline` is set and the model is not already cached, startup fails with a model-loading error. You can control the cache location with standard Hugging Face environment variables such as `HF_HOME`.

## Usage

```bash
python3 tools/clip/index_folder.py \
  --input /path/to/media \
  --output clip_index.json \
  --include-embeddings \
  --clusters 8
```

`--input` can be repeated for multiple files or folders. By default item embeddings are omitted to keep JSON small; pass `--include-embeddings` when downstream tooling needs vectors.

## App integration

Mandoline searches for the helper in this order:

1. `MANDOLINE_CLIP_INDEXER_PATH` from the process environment.
2. `MANDOLINE_CLIP_INDEXER_PATH` from UserDefaults.
3. `~/Library/Application Support/Mandoline/CLIP/index_folder.py`.
4. `tools/clip/index_folder.py` in a DEBUG/development checkout.

For a production-style local install:

```bash
mkdir -p "$HOME/Library/Application Support/Mandoline/CLIP"
cp tools/clip/index_folder.py "$HOME/Library/Application Support/Mandoline/CLIP/index_folder.py"
```

Mandoline does not rely on an activated shell virtual environment. Set `MANDOLINE_CLIP_PYTHON_PATH` to the venv Python executable, especially for Finder-launched apps that do not inherit shell environment variables:

```bash
# Environment form, useful when launching from Terminal:
export MANDOLINE_CLIP_PYTHON_PATH="/Users/you/Programming/mandoline/.venv-clip/bin/python3"

# Finder-launched app form:
defaults write com.rowan.Mandoline MANDOLINE_CLIP_PYTHON_PATH "/Users/you/Programming/mandoline/.venv-clip/bin/python3"
```

DEBUG/development builds also auto-detect `.venv-clip/bin/python3` in the checkout when present.

The app passes `--offline` unless downloads are explicitly allowed. To permit a one-off app-launched model download, set `MANDOLINE_CLIP_ALLOW_DOWNLOADS=1` in the environment or UserDefaults; leave it unset for the normal offline/private mode:

```bash
defaults write com.rowan.Mandoline MANDOLINE_CLIP_ALLOW_DOWNLOADS -bool true
# Reset to offline default:
defaults delete com.rowan.Mandoline MANDOLINE_CLIP_ALLOW_DOWNLOADS
```
