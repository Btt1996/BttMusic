#!/usr/bin/env python3
"""
Btt Music — reference yt-dlp extraction server.

The Btt Music iOS app CANNOT run yt-dlp (it is a Python pipeline) and iOS apps
must not extract YouTube streams themselves. The app instead submits YouTube
URLs to a yt-dlp-compatible server that YOU host and control. This file is a
minimal, working implementation of the contract the app expects.

Contract (implemented by the app in YouTubeView.swift):
    POST /extract
    Body:  {"url": "https://youtube.com/watch?v=..."}
    200:   {"title": "...", "download_url": "https://.../file.m4a"}
    other: any non-200 is reported to the user as a server error.

The download_url must be directly fetchable by the phone (publicly reachable;
the app downloads it with a plain URLSession GET).

Run it:
    pip install fastapi uvicorn yt-dlp
    uvicorn ytdlp_server:app --host 0.0.0.0 --port 8000

Then in Btt Music: Get Music -> YouTube Import -> set the server base URL
(e.g. http://your-server:8000). Secure it behind HTTPS + a token if it is
publicly reachable (add your own auth middleware; the app currently sends no
credentials).

Responsibilities you keep as the host operator:
    - Respect YouTube's Terms of Service and applicable law.
    - Only extract content you have the right to download.
    - Keep yt-dlp updated (pip install -U yt-dlp).
"""

import tempfile
import pathlib

import yt_dlp
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel

app = FastAPI(title="Btt Music yt-dlp server")


class ExtractRequest(BaseModel):
    url: str


@app.post("/extract")
def extract(req: ExtractRequest):
    url = req.url.strip()
    if not url.startswith(("http://", "https://")):
        raise HTTPException(status_code=400, detail="not a URL")

    out_dir = pathlib.Path(tempfile.mkdtemp(prefix="bttmu-"))
    options = {
        # Audio only, no video stream, best quality, m4a container.
        "format": "bestaudio[ext=m4a]/bestaudio/best",
        "outtmpl": str(out_dir / "%(title).80s.%(ext)s"),
        "noplaylist": True,
        "quiet": True,
        "no_warnings": True,
    }
    try:
        with yt_dlp.YoutubeDL(options) as ydl:
            info = ydl.extract_info(url, download=True)
            file_path = pathlib.Path(ydl.prepare_filename(info))
    except Exception as exc:  # surfaced to the app as a server error
        return JSONResponse(status_code=502, content={"detail": f"extraction failed: {exc}"})

    if not file_path.exists():
        return JSONResponse(status_code=502, content={"detail": "no file produced"})

    # In production, serve the file over HTTPS (reverse proxy, signed URL,
    # or an object store). For a LAN setup, mount out_dir with a static
    # file server and return that URL here.
    return {
        "title": info.get("title") or file_path.stem,
        "download_url": f"http://YOUR-PUBLIC-HOST:8000/files/{file_path.name}",
    }
