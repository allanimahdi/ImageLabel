# ImageLabel

Native **macOS** SwiftUI app that labels a folder of images and renames each file to its **best-score label** (no score in the filename). Optionally group pictures into topic folders — you pick which label/topic to group by.

Requires **macOS 14+** and **Xcode 15+**.

## Open & run

1. Clone this repo on a Mac.
2. Open `ImageLabel.xcodeproj` in Xcode.
3. Select the **ImageLabel** scheme and a **My Mac** destination.
4. Press **Run** (⌘R).

Signing: with Automatic signing, pick your Team under the ImageLabel target → Signing & Capabilities if Xcode asks.

## Labeling backends (Settings)

**Settings → Labeling** chooses the engine. Default is **Local (Apple Vision)** (free / offline).

| Backend | Cost / network | Credentials | Capability |
|---------|----------------|-------------|------------|
| **Local (Apple Vision)** | Free, on-device, no network | None | Apple’s built-in image classifier (`VNClassifyImageRequest`). Fewer / less specific labels than Google; weak photos may get no confident label. |
| **Google Cloud Vision** | Network + GCP billing | API key or service-account JSON | Stronger LABEL_DETECTION; needs Vision API enabled on the project. |

Rename and Group by Topic work the same after labels arrive for either backend.

### Local (Apple Vision)

1. Settings → Labeling → **Local (Apple Vision)**.
2. Select a folder → **Label Images** (no API key).
3. Review **Rename to Top Labels** → **Apply Renames**.

Limits: taxonomy and accuracy are whatever Apple ships on the Mac; abstract / unusual images often score low. If labeling fails with “no confident labels”, try a clearer photo or switch to Google.

### Google Cloud Vision credentials

You need an existing Google Cloud project with the **Cloud Vision API** enabled. In Settings, choose **Google Cloud Vision**, then pick **one** auth mode — do not mix API key and JSON.

#### Option A — API key (simplest)

1. In [Google Cloud Console](https://console.cloud.google.com/) → APIs & Services → Credentials, create an **API key**.
2. Restrict it to the Vision API if you can.
3. Choose **API Key**, paste the key only (the `AIza…` string).

The key is stored in the macOS **Keychain**, not in the repo.

#### Option B — Service account JSON

1. Create a service account with permission to call Vision (e.g. **Cloud Vision AI User** / Vision-related role).
2. Download a JSON key file (`"type": "service_account"`) — keep it **outside** this repository.
3. Choose **Service Account JSON** and **Browse…** to that file.

The app stores only the **file path** in preferences. `.gitignore` already excludes common credential filenames — never commit keys or JSON secrets.

### If Google labeling returns HTTP 403

1. **APIs & Services → Library → Cloud Vision API → Enable**.
2. **Billing → Link a billing account**.
3. **API key:** allow Cloud Vision API; avoid HTTP-referrer restrictions for this Mac app.
4. **Service account:** grant a Vision-related role (+ Service Usage Consumer if needed).

## How to use

The home screen shows four large primary actions: **Label & Rename**, **Auto-Group into Folders**, **Rename by Faces**, and **Settings**. **Home** in the label workspace returns to that landing.

1. **Select Folder** — choose a directory of images (`jpg`, `jpeg`, `png`, `heic`, `heif`, `webp`, `gif`, `tif`/`tiff`, `bmp`). HEIC/HEIF are re-encoded to JPEG for Google when needed; Local can read common formats via Vision.
2. **Label Images** — Local or Google per Settings. Progress in the footer; failures are **per file**. On success, **Rename to Top Labels** opens.
3. **Rename Files…** — apply best-score label only (e.g. `golden_retriever.jpg`). Collisions get `_2`, `_3`, …. **Undo** when available.
4. **Rename by Faces…** — on-device face detection & grouping (no photo upload): Select → Detect & Group → Identify People → Preview & Rename. Names look like `Mahdi-Marija.jpg` (left→right by default; alphabetical optional in Settings). Unknown-only photos keep their original names. Optional: remember people on this Mac / delete stored identities in Settings.
5. **Auto-Group into Folders** (optional) — preview then move each labeled image into one **coarse** folder (`Animals`, `People`, `Nature`, `Food`, `Vehicles`, `Buildings`, `Sports`, `Technology`, `Art`, or `Other`). Fine labels like “Golden Retriever” collapse into `Animals` via keyword rules (not dozens of niche folders).
6. **Group by Topic** (optional) — pick an exact Vision label yourself; preview then move matching files into a folder named after that label.

## Notes

- Rename uses the **highest-score label only**; scores are never written into filenames.
- Auto-Group sums label confidences per main category and picks the strongest bucket; unmatched labels go to `Other`.
- Group by Topic matches the **topic you select** against each image’s labels (not only the top label).
- Out of scope: training custom models, iOS, non-Mac platforms.
