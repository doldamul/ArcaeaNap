"""Profile 핸들러: account_connections.json에서 프로필 데이터 로드."""
import os
import json
from configuration import config
from PyQt6.QtCore import QObject, pyqtSlot, pyqtSignal, QVariant
from models.constants import POTENTIAL_GRADES, DEFAULT_POTENTIAL_COLOR


class ProfileHandler(QObject):
    """프로필 데이터를 account_connections.json에서 읽어 QML에 제공하는 핸들러."""
    profileChanged = pyqtSignal()

    def __init__(self):
        super().__init__()
        self._connections_file = os.path.join(
            config['general']['cache_path'], 'account_connections.json'
        )

    def _load_connections(self):
        if not os.path.exists(self._connections_file):
            return {}
        try:
            with open(self._connections_file, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception:
            return {}

    @staticmethod
    def _get_potential_color(rating) -> str:
        """포텐셜 값 → 색상 코드. POTENTIAL_GRADES 상수 참조."""
        if rating is None or rating < 0:
            return DEFAULT_POTENTIAL_COLOR
        for threshold, color, _, _ in POTENTIAL_GRADES:
            if rating >= threshold:
                return color
        return DEFAULT_POTENTIAL_COLOR

    @staticmethod
    def _get_potential_badge(rating) -> str:
        """포텐셜 값 → 뱃지 텍스트. POTENTIAL_GRADES 상수 참조."""
        if rating is None:
            return ""
        for threshold, _, badge, _ in POTENTIAL_GRADES:
            if rating >= threshold:
                return badge
        return ""

    @staticmethod
    def _get_potential_stars(rating) -> int:
        """포텐셜 값 → 별 개수 (0-3). POTENTIAL_GRADES 상수 참조."""
        if rating is None:
            return 0
        for threshold, _, _, stars in POTENTIAL_GRADES:
            if rating >= threshold:
                return stars
        return 0

    @staticmethod
    def _format_user_code(code) -> str:
        """유저코드 9자리를 'XXX XXX XXX' 포맷으로 변환."""
        if not code:
            return ""
        digits = code.replace(" ", "")
        if len(digits) != 9:
            return code
        return f"{digits[:3]} {digits[3:6]} {digits[6:9]}"

    @pyqtSlot(result='QVariant')
    def getProfile(self):
        """프로필 데이터를 dict로 반환. 미연결 시 connected=False."""
        connections = self._load_connections()
        ao_info = connections.get('arcaea_online', {})
        if not ao_info.get('connected', False):
            return {'connected': False}

        rating = ao_info.get('rating')
        user_code = ao_info.get('user_code', '')

        return {
            'connected': True,
            'name': ao_info.get('name', ''),
            'user_code': user_code,
            'rating': rating,
            'join_date': ao_info.get('join_date'),
            # 계산된 포텐셜 표시 값
            'potentialColor': self._get_potential_color(rating),
            'potentialBadge': self._get_potential_badge(rating),
            'potentialStars': self._get_potential_stars(rating),
            'formattedUserCode': self._format_user_code(user_code),
        }

    @pyqtSlot()
    def refreshProfile(self):
        """프로필 데이터를 다시 읽고 QML에 알림."""
        self.profileChanged.emit()
