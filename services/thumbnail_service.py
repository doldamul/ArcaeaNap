"""
썸네일 서비스: 경로 검색, 대표 색상 추출.

썸네일 파일 시스템 접근과 이미지 처리를 담당한다.
"""
import os
from PyQt6.QtCore import QUrl
from PyQt6.QtGui import QImage, QColor


# 난이도 코드 → 파일명 매핑
DIFF_CODE_MAP = {0: 'pst', 1: 'prs', 2: 'ftr', 3: 'byd', 4: 'etr'}

# 썸네일 검색 우선순위 (높은 난이도 우선)
THUMBNAIL_PRIORITY = ['ftr', 'byd', 'etr', 'prs', 'pst']


class ThumbnailService:
    """썸네일 경로 검색 및 대표 색상 추출 서비스."""

    def __init__(self, thumbnails_dir: str):
        self._thumbnails_dir = thumbnails_dir

    @property
    def thumbnails_dir(self):
        return self._thumbnails_dir

    @thumbnails_dir.setter
    def thumbnails_dir(self, value):
        self._thumbnails_dir = value

    def find_by_priority(self, arcaea_id: str) -> str:
        """우선순위에 따라 썸네일 검색. QUrl 문자열 반환. 없으면 빈 문자열."""
        for diff in THUMBNAIL_PRIORITY:
            filename = f"{arcaea_id}_{diff}.jpg"
            filepath = os.path.join(self._thumbnails_dir, filename)
            if os.path.exists(filepath):
                return QUrl.fromLocalFile(filepath).toString()
        return ""

    def get_path(self, arcaea_id: str) -> str:
        """arcaea_id로 썸네일 경로 반환 (우선순위 검색)."""
        if not arcaea_id:
            return ""
        return self.find_by_priority(arcaea_id)

    def get_path_for_difficulty(self, arcaea_id: str, difficulty: int) -> str:
        """특정 난이도 썸네일 → 해당 난이도가 없으면 우선순위 폴백."""
        if not arcaea_id:
            return ""

        if difficulty >= 0 and difficulty in DIFF_CODE_MAP:
            diff_code = DIFF_CODE_MAP[difficulty]
            filename = f"{arcaea_id}_{diff_code}.jpg"
            filepath = os.path.join(self._thumbnails_dir, filename)
            if os.path.exists(filepath):
                return QUrl.fromLocalFile(filepath).toString()

        return self.find_by_priority(arcaea_id)

    def get_representative_color(self, arcaea_id: str, difficulty: int) -> str:
        """
        썸네일의 대표 색상 계산.
        Returns: hex color string (e.g. "#FF0000"). 기본값 "#FFFFFF".
        """
        path_url = self.get_path_for_difficulty(arcaea_id, difficulty)
        if not path_url:
            return "#FFFFFF"

        local_path = QUrl(path_url).toLocalFile()
        if not local_path:
            local_path = path_url

        if not os.path.exists(local_path):
            return "#FFFFFF"

        try:
            image = QImage(local_path)
            if image.isNull():
                return "#FFFFFF"

            pixel = image.scaled(1, 1).pixel(0, 0)
            color = QColor(pixel)

            h, s, v, a = color.getHsv()
            v = max(v, 220)
            if s > 20:
                s = max(s, 180)
            else:
                s = 0
            color.setHsv(h, s, v)
            return color.name()
        except Exception:
            return "#FFFFFF"
