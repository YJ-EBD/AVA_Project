from __future__ import annotations

import os
import tempfile
import wave
from array import array
from pathlib import Path
from threading import Lock
from typing import Annotated

from fastapi import FastAPI, File, Form, Header, HTTPException, Query, Request, UploadFile
from pydantic import BaseModel


BASE_DIR = Path(__file__).resolve().parent
MODEL_ROOT = Path(os.getenv("NOTIVA_WHISPER_MODEL_ROOT", BASE_DIR / "models"))
BATCH_MODEL_NAME = os.getenv("NOTIVA_WHISPER_BATCH_MODEL", os.getenv("NOTIVA_WHISPER_MODEL", "large-v3"))
REALTIME_MODEL_NAME = os.getenv("NOTIVA_WHISPER_REALTIME_MODEL", "turbo")
DEVICE = os.getenv("NOTIVA_WHISPER_DEVICE", "cpu")
COMPUTE_TYPE = os.getenv("NOTIVA_WHISPER_COMPUTE_TYPE", "int8")
BATCH_BEAM_SIZE = int(os.getenv("NOTIVA_WHISPER_BATCH_BEAM_SIZE", os.getenv("NOTIVA_WHISPER_BEAM_SIZE", "5")))
REALTIME_BEAM_SIZE = int(os.getenv("NOTIVA_WHISPER_REALTIME_BEAM_SIZE", "1"))
MIN_WAV_RMS = float(os.getenv("NOTIVA_MIN_WAV_RMS", "0.005"))
MIN_WAV_PEAK = float(os.getenv("NOTIVA_MIN_WAV_PEAK", "0.025"))
MIN_WAV_ACTIVE_RATIO = float(os.getenv("NOTIVA_MIN_WAV_ACTIVE_RATIO", "0.002"))

app = FastAPI(title="AVA Notiva AI Whisper Server", version="0.1.0")
_models = {}
_model_lock = Lock()


class SegmentResponse(BaseModel):
    start: float
    end: float
    text: str


class TranscriptionResponse(BaseModel):
    text: str
    segments: list[SegmentResponse]
    language: str
    duration: float


def _load_model(mode: str):
    model_name = _model_name_for_mode(mode)
    if model_name in _models:
        return _models[model_name]
    with _model_lock:
        if model_name in _models:
            return _models[model_name]
        try:
            from faster_whisper import WhisperModel
        except ImportError as error:
            raise RuntimeError(
                "faster-whisper is not installed. Run install_whisper_large_v3.ps1 first."
            ) from error

        MODEL_ROOT.mkdir(parents=True, exist_ok=True)
        model = WhisperModel(
            model_name,
            device=DEVICE,
            compute_type=COMPUTE_TYPE,
            download_root=str(MODEL_ROOT),
        )
        _models[model_name] = model
        return model


@app.get("/health")
def health():
    return {
        "status": "ok",
        "batchModel": BATCH_MODEL_NAME,
        "realtimeModel": REALTIME_MODEL_NAME,
        "modelRoot": str(MODEL_ROOT),
        "loadedModels": sorted(_models.keys()),
    }


@app.post("/v1/notiva/transcribe", response_model=TranscriptionResponse)
async def transcribe(
    request: Request,
    file: Annotated[UploadFile | None, File()] = None,
    language: Annotated[str | None, Form()] = "ko",
    mode: Annotated[str | None, Form()] = "batch",
):
    if file is None:
        form = await request.form()
        candidate = form.get("file")
        if _is_upload_file(candidate):
            file = candidate
        else:
            for value in form.values():
                if _is_upload_file(value):
                    file = value
                    break
    if file is None:
        raise HTTPException(status_code=400, detail="Audio file field 'file' is required.")

    suffix = Path(file.filename or "audio.webm").suffix or ".webm"
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as temp:
        temp_path = Path(temp.name)
        temp.write(await file.read())

    try:
        return _transcribe_path(temp_path, language, mode)
    finally:
        try:
            temp_path.unlink(missing_ok=True)
        except OSError:
            pass


@app.post("/v1/notiva/transcribe-raw", response_model=TranscriptionResponse)
async def transcribe_raw(
    request: Request,
    language: Annotated[str | None, Query()] = "ko",
    mode: Annotated[str | None, Query()] = "batch",
    header_mode: Annotated[str | None, Header(alias="X-Notiva-Mode")] = None,
    filename: Annotated[str | None, Header(alias="X-Notiva-Filename")] = "audio.webm",
):
    suffix = Path(filename or "audio.webm").suffix or ".webm"
    body = await request.body()
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as temp:
        temp_path = Path(temp.name)
        temp.write(body)

    try:
        return _transcribe_path(temp_path, language, header_mode or mode)
    finally:
        try:
            temp_path.unlink(missing_ok=True)
        except OSError:
            pass


def _is_upload_file(value) -> bool:
    return isinstance(value, UploadFile) or (
        hasattr(value, "filename") and hasattr(value, "read")
    )


def _normalize_mode(mode: str | None) -> str:
    normalized = (mode or "batch").strip().lower()
    return "realtime" if normalized == "realtime" else "batch"


def _model_name_for_mode(mode: str) -> str:
    return REALTIME_MODEL_NAME if mode == "realtime" else BATCH_MODEL_NAME


def _beam_size_for_mode(mode: str) -> int:
    return REALTIME_BEAM_SIZE if mode == "realtime" else BATCH_BEAM_SIZE


def _transcribe_path(temp_path: Path, language: str | None, mode: str | None) -> TranscriptionResponse:
    if temp_path.stat().st_size <= 0:
        raise HTTPException(status_code=400, detail="Empty audio file.")
    resolved_mode = _normalize_mode(mode)
    if not _audio_file_has_speech(temp_path):
        return TranscriptionResponse(text="", segments=[], language=language or "", duration=0.0)

    model = _load_model(resolved_mode)
    selected_language = None if language is None or language.strip().lower() == "auto" else language.strip()
    segments_iter, info = model.transcribe(
        str(temp_path),
        language=selected_language,
        beam_size=_beam_size_for_mode(resolved_mode),
        vad_filter=True,
        word_timestamps=False,
        condition_on_previous_text=False,
    )
    segments: list[SegmentResponse] = []
    for segment in segments_iter:
        text = (segment.text or "").strip()
        if text:
            segments.append(SegmentResponse(start=segment.start, end=segment.end, text=text))
    return TranscriptionResponse(
        text=" ".join(segment.text for segment in segments).strip(),
        segments=segments,
        language=getattr(info, "language", "") or "",
        duration=float(getattr(info, "duration", 0.0) or 0.0),
    )


def _audio_file_has_speech(path: Path) -> bool:
    if path.suffix.lower() != ".wav":
        return True
    try:
        with wave.open(str(path), "rb") as wav:
            if wav.getsampwidth() != 2:
                return True
            frame_count = wav.getnframes()
            if frame_count <= 0:
                return False
            raw_frames = wav.readframes(frame_count)
    except (OSError, wave.Error):
        return True

    if len(raw_frames) < 2:
        return False

    samples = array("h")
    samples.frombytes(raw_frames)
    if not samples:
        return False

    total_squares = 0.0
    peak = 0.0
    active = 0
    for sample in samples:
        normalized = abs(sample) / 32768.0
        total_squares += normalized * normalized
        if normalized > peak:
            peak = normalized
        if normalized >= MIN_WAV_PEAK:
            active += 1

    rms = (total_squares / len(samples)) ** 0.5
    active_ratio = active / len(samples)
    return rms >= MIN_WAV_RMS or (
        peak >= MIN_WAV_PEAK and active_ratio >= MIN_WAV_ACTIVE_RATIO
    )
