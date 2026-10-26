# ImageLabel

Native **macOS** SwiftUI app that labels a folder of images with [Google Cloud Vision](https://cloud.google.com/vision) and renames each file to its **best-score label** (no score in the filename). Optionally group pictures into topic folders — you pick which label/topic to group by.

Requires **macOS 14+** and **Xcode 15+**.

## Open & run

1. Clone this repo on a Mac.
2. Open `ImageLabel.xcodeproj` in Xcode.
3. Select the **ImageLabel** scheme and a **My Mac** destination.
4. Press **Run** (⌘R).

Signing: with Automatic signing, pick your Team under the ImageLabel target → Signing & Capabilities if Xcode asks.

## Google Cloud Vision credentials

You need an existing Google Cloud project with the **Cloud Vision API** enabled.

### Option A — API key (simplest)

1. In [Google Cloud Console](https://console.cloud.google.com/) → APIs & Services → Credentials, create an **API key**.
2. Restrict it to the Vision API if you can.
3. In ImageLabel: **Settings** (gear) or **ImageLabel → Settings…** (⌘,), choose **API Key**, paste the key.

The key is stored in the macOS **Keychain**, not in the repo.

### Option B — Service account JSON

1. Create a service account with permission to call Vision (e.g. **Cloud Vision AI User** / Vision-related role).
2. Download a JSON key file — keep it **outside** this repository.
3. In Settings, choose **Service Account JSON** and browse to that file.

The app stores only the **file path** in preferences. `.gitignore` already excludes common credential filenames — never commit keys or JSON secrets.

## How to use

1. **Select Folder** — choose a directory of images (`jpg`, `jpeg`, `png`, `heic`, `heif`, `webp`, `gif`, `tif`/`tiff`, `bmp`). HEIC/HEIF are re-encoded to JPEG for the API when needed.
2. **Label Images** — calls Vision label detection per file. Progress shows in the footer. Failures are recorded **per file**; the batch continues.
3. **Rename Preview** — dry-run of proposed names from the top label only (e.g. `golden_retriever.jpg`). Collisions get `_2`, `_3`, … suffixes. Confirm to apply. **Undo** restores the last rename/group batch when available.
4. **Group by Topic** — pick a label from the menu (sorted by how often it appears). Preview which files move into a folder named after that topic, then confirm.

## Notes

- Rename uses the **highest-score label only**; scores are never written into filenames.
- Grouping matches the **topic you select** against each image’s labels (not only the top label).
- Out of scope: training custom models, iOS, non-Mac platforms.
