"""공개 ConsultantSheet 읽기가 OAuth 토큰/스코프 없이 API 키로만 이루어지는지 검증."""
import os
import sys
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from utils import web_consultantsheet as wcs


def test_scopes_do_not_include_spreadsheets():
    assert not any("spreadsheets" in s for s in wcs.SCOPES)
    assert "https://www.googleapis.com/auth/drive.file" in wcs.SCOPES


def test_open_public_spreadsheet_uses_api_key_not_oauth():
    fake_client = mock.Mock()
    with mock.patch.object(wcs, "_read_client_values", return_value=("KEY", "id", "sec")), \
         mock.patch.object(wcs.gspread, "api_key", return_value=fake_client) as api_key, \
         mock.patch.object(wcs, "get_creds") as get_creds, \
         mock.patch.object(wcs.gspread, "authorize") as authorize:
        sheet = wcs._open_public_spreadsheet("SHEET")

    api_key.assert_called_once_with("KEY")
    fake_client.open_by_key.assert_called_once_with("SHEET")
    assert sheet is fake_client.open_by_key.return_value
    get_creds.assert_not_called()
    authorize.assert_not_called()


def test_open_sheet_reads_public_sheet_without_login():
    class Stop(Exception):
        pass

    with mock.patch.object(wcs, "_open_public_spreadsheet", return_value=mock.Mock()) as opener, \
         mock.patch.object(wcs, "get_creds") as get_creds, \
         mock.patch.object(wcs, "init_songs_db", side_effect=Stop):
        try:
            wcs.open_sheet()
        except Stop:
            pass

    opener.assert_called_once_with(wcs.SPREADSHEET_ID)
    get_creds.assert_not_called()


def test_private_sheet_paths_still_use_oauth():
    creds = object()
    with mock.patch.object(wcs, "get_creds", return_value=creds), \
         mock.patch.object(wcs.gspread, "authorize") as authorize:
        wcs._open_spreadsheet("PRIVATE")

    authorize.assert_called_once_with(creds)
    authorize.return_value.open_by_key.assert_called_once_with("PRIVATE")
