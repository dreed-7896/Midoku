#!/usr/bin/env python3
"""Build every source in src/ and write an Aidoku/Midoku source list at the repo root.

Requires: rustup target add wasm32-unknown-unknown
Output: index.json, index.min.json, sources/<id>-v<version>.aix, icons/<id>-v<version>.png
"""
import json, pathlib, shutil, subprocess, zipfile

root = pathlib.Path(__file__).resolve().parent.parent
(root / "sources").mkdir(exist_ok=True)
(root / "icons").mkdir(exist_ok=True)
items = []
for src in sorted((root / "src").iterdir()):
    if not (src / "res" / "source.json").exists():
        continue
    subprocess.run(["cargo", "build", "--release"], cwd=src, check=True)
    wasm = next((src / "target/wasm32-unknown-unknown/release").glob("*.wasm"))
    info = json.loads((src / "res/source.json").read_text())["info"]
    name = f"{info['id']}-v{info['version']}"
    for old in list((root / "sources").glob(f"{info['id']}-v*.aix")) + list((root / "icons").glob(f"{info['id']}-v*.png")):
        old.unlink()
    with zipfile.ZipFile(root / "sources" / f"{name}.aix", "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted((src / "res").iterdir()):
            if f.is_file():
                z.write(f, f"Payload/{f.name}")
        z.write(wasm, "Payload/main.wasm")
    shutil.copy(src / "res/icon.png", root / "icons" / f"{name}.png")
    item = {
        "id": info["id"], "name": info["name"], "version": info["version"],
        "iconURL": f"icons/{name}.png", "downloadURL": f"sources/{name}.aix",
        "languages": info.get("languages"), "contentRating": info.get("contentRating", 0),
        "altNames": info.get("altNames"), "baseURL": info.get("url"),
        "minAppVersion": info.get("minAppVersion"), "maxAppVersion": info.get("maxAppVersion"),
    }
    items.append({k: v for k, v in item.items() if v is not None})

index = {"name": "dreed extensions", "sources": items}
(root / "index.json").write_text(json.dumps(index, indent=2, ensure_ascii=False) + "\n")
(root / "index.min.json").write_text(json.dumps(index, separators=(",", ":"), ensure_ascii=False))
print(f"built {len(items)} source(s)")
