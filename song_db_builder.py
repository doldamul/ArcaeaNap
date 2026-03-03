"""songs.db 리빌드 유틸리티."""
import os

from repositories.song_repository import get_db_path
from web_consultantsheet import open_sheet
from web_wiki import open_wiki


def rebuild_songs_db():
    """Delete existing songs.db and rebuild from online sources (ConsultantSheet + Wiki)."""
    db_path = get_db_path()
    if os.path.exists(db_path):
        os.remove(db_path)
        print(f"[rebuild_songs_db] Deleted existing {db_path}")

    print("[rebuild_songs_db] Loading data from Consultant Sheet...")
    open_sheet()
    print("[rebuild_songs_db] Consultant Sheet load successful.")

    print("[rebuild_songs_db] Loading data from Wiki...")
    open_wiki()
    print("[rebuild_songs_db] Wiki load successful.")
