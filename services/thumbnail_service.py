"""
썸네일 서비스: 경로 검색 및 클라우드 스토리지 Dataless 파일 비동기 다운로드.

썸네일 파일 시스템 접근과 이미지 처리를 담당한다.
"""
import concurrent.futures
import os
import stat
import threading
from typing import Optional

from PyQt6.QtCore import QObject, pyqtSignal, QUrl, Qt, QTimer, QCoreApplication
from PyQt6.QtGui import QImage, QColor

from utils.configuration import get_cache_dir


# 난이도 코드 ↔ 파일명 매핑
DIFF_CODE_MAP = {0: 'pst', 1: 'prs', 2: 'ftr', 3: 'byd', 4: 'etr'}
CODE_DIFF_MAP = {v: k for k, v in DIFF_CODE_MAP.items()}

# 썸네일 검색 우선순위 (높은 난이도 우선)
THUMBNAIL_PRIORITY = ['ftr', 'byd', 'etr', 'prs', 'pst']


def is_file_hydrated(filepath: str) -> bool:
    """파일이 로컬 디스크에 완전히 다운로드되어 존재하는지 검사 (Dataless/Offline 껍데기 파일 제외)."""
    try:
        st = os.stat(filepath)
        # 0바이트 파일은 비어있거나 다운로드 대기 상태
        if st.st_size == 0:
            return False

        # macOS (APFS / FileProvider): SF_DATALESS (0x40000000) 플래그 검사
        st_flags = getattr(st, 'st_flags', 0)
        sf_dataless = getattr(stat, 'SF_DATALESS', 0x40000000)
        if st_flags & sf_dataless:
            return False

        # Windows (Cloud Files / Files On-Demand): OFFLINE 또는 RECALL_ON_DATA_ACCESS 속성 검사
        st_file_attributes = getattr(st, 'st_file_attributes', 0)
        if st_file_attributes & (0x1000 | 0x400000 | 0x40000):  # OFFLINE | RECALL_ON_DATA_ACCESS | RECALL_ON_OPEN
            return False

        return True
    except OSError:
        return False


class ThumbnailService(QObject):
    """썸네일 경로 검색 및 비동기 다운로드(Hydration) 서비스."""

    thumbnailHydrated = pyqtSignal(str, int)  # (arcaea_id, difficulty)
    thumbnailVersionChanged = pyqtSignal()

    _shared_instance: Optional["ThumbnailService"] = None

    @classmethod
    def get_instance(cls, thumbnails_dir: Optional[str] = None) -> "ThumbnailService":
        if cls._shared_instance is None:
            if thumbnails_dir is None:
                thumbnails_dir = os.path.join(get_cache_dir(), 'thumbnails')
            cls._shared_instance = cls(thumbnails_dir)
        elif thumbnails_dir is not None and cls._shared_instance.thumbnails_dir != thumbnails_dir:
            cls._shared_instance.thumbnails_dir = thumbnails_dir
        return cls._shared_instance

    def __init__(self, thumbnails_dir: str, parent: Optional[QObject] = None):
        super().__init__(parent)
        self._thumbnails_dir = thumbnails_dir
        self._thumbnail_version = 0
        self._path_cache: dict[tuple[str, int], str] = {}
        self._exact_cache: dict[tuple[str, int], str] = {}
        self._color_cache: dict[tuple[str, int], str] = {}
        self._hydrated_cache: dict[str, bool] = {}
        self._hydrating_files: set[str] = set()
        self._lock = threading.Lock()
        self._executor = concurrent.futures.ThreadPoolExecutor(
            max_workers=4, thread_name_prefix="thumb_hydrator"
        )
        self._debounce_timer = QTimer(self)
        self._debounce_timer.setSingleShot(True)
        self._debounce_timer.setInterval(50)
        self._debounce_timer.timeout.connect(self._on_debounce_timeout)
        self.thumbnailHydrated.connect(self._on_thumbnail_hydrated)

    @property
    def thumbnail_version(self) -> int:
        return self._thumbnail_version

    @property
    def thumbnails_dir(self):
        return self._thumbnails_dir

    @thumbnails_dir.setter
    def thumbnails_dir(self, value):
        if self._thumbnails_dir != value:
            self._thumbnails_dir = value
            self.clear_cache()

    def clear_cache(self) -> None:
        """썸네일 경로 및 색상 메모리 캐시를 초기화한다."""
        with self._lock:
            self._path_cache.clear()
            self._exact_cache.clear()
            self._color_cache.clear()
            self._hydrated_cache.clear()
        self._thumbnail_version += 1
        self.thumbnailVersionChanged.emit()

    def _on_thumbnail_hydrated(self, arcaea_id: str, diff_num: int) -> None:
        """스레드 안전 슬롯: 백그라운드 다운로드 완료 시 50ms 디바운스 타이머 가동."""
        if QCoreApplication.instance() is None:
            self._thumbnail_version += 1
            self.thumbnailVersionChanged.emit()
        else:
            if not self._debounce_timer.isActive():
                self._debounce_timer.start(50)

    def _on_debounce_timeout(self) -> None:
        """메인 스레드: 50ms 동안 모인 다운로드 완료 건을 1회 일괄 통보."""
        self._thumbnail_version += 1
        self.thumbnailVersionChanged.emit()

    def _check_and_trigger_hydration(self, filepath: str) -> bool:
        """파일이 실물로 존재하는지 확인하고, 껍데기 파일이면 백그라운드 다운로드를 큐잉한다."""
        with self._lock:
            if filepath in self._hydrated_cache and self._hydrated_cache[filepath]:
                return True

        if not os.path.exists(filepath):
            return False

        if is_file_hydrated(filepath):
            with self._lock:
                self._hydrated_cache[filepath] = True
            return True

        # 껍데기 파일인 경우: 백그라운드 스레드에서 조용히 다운로드(터치/전체읽기) 수행
        with self._lock:
            if filepath not in self._hydrating_files:
                self._hydrating_files.add(filepath)
                self._executor.submit(self._hydrate_worker, filepath)

        return False

    def _hydrate_worker(self, filepath: str) -> None:
        """백그라운드 스레드에서 클라우드 스토리지 파일의 다운로드를 트리거한다."""
        try:
            with open(filepath, 'rb') as f:
                _ = f.read()
            # 다운로드 완료 후 실물 캐시 등록
            if is_file_hydrated(filepath):
                with self._lock:
                    self._hydrated_cache[filepath] = True
                    # 해당 파일 관련 경로 및 색상 캐시를 무효화하여 다음 요청 시 실물 반영
                    self._path_cache.clear()
                    self._exact_cache.clear()
                    self._color_cache.clear()

                filename = os.path.basename(filepath)
                base, _ = os.path.splitext(filename)
                if '_' in base:
                    parts = base.rsplit('_', 1)
                    arcaea_id = parts[0]
                    diff_code = parts[1]
                    diff_num = CODE_DIFF_MAP.get(diff_code, -1)
                else:
                    arcaea_id = base
                    diff_num = -1

                self.thumbnailHydrated.emit(arcaea_id, diff_num)
        except Exception:
            pass
        finally:
            with self._lock:
                self._hydrating_files.discard(filepath)

    def find_by_priority(self, arcaea_id: str) -> str:
        """우선순위에 따라 썸네일 검색. 실물 파일일 때만 QUrl 반환, 껍데기면 백그라운드 다운로드 큐잉 후 빈 문자열 반환."""
        for diff in THUMBNAIL_PRIORITY:
            filename = f"{arcaea_id}_{diff}.jpg"
            filepath = os.path.join(self._thumbnails_dir, filename)
            if not os.path.exists(filepath):
                continue
            if self._check_and_trigger_hydration(filepath):
                return QUrl.fromLocalFile(filepath).toString()
            # 최우선 순위 파일이 디스크에 존재하지만 껍데기인 경우: 다운로드를 큐잉했으므로
            # 다른 불필요한 난이도 4종까지 중복 큐잉하지 않고 즉시 반환
            return ""
        return ""

    def get_path(self, arcaea_id: str) -> str:
        """arcaea_id로 썸네일 경로 반환 (우선순위 검색)."""
        if not arcaea_id:
            return ""
        return self.find_by_priority(arcaea_id)

    def get_exact_path_for_difficulty(self, arcaea_id: str, difficulty: int) -> str:
        """특정 난이도 썸네일만 반환. 실물이면 QUrl 반환, 껍데기면 백그라운드 다운로드 큐잉 후 빈 문자열 반환."""
        if not arcaea_id:
            return ""

        cache_key = (arcaea_id, difficulty)
        with self._lock:
            if cache_key in self._exact_cache:
                return self._exact_cache[cache_key]

        diff_code = DIFF_CODE_MAP.get(difficulty)
        if diff_code is None:
            with self._lock:
                self._exact_cache[cache_key] = ""
            return ""

        filename = f"{arcaea_id}_{diff_code}.jpg"
        filepath = os.path.join(self._thumbnails_dir, filename)
        if not os.path.exists(filepath):
            with self._lock:
                self._exact_cache[cache_key] = ""
            return ""

        if self._check_and_trigger_hydration(filepath):
            result = QUrl.fromLocalFile(filepath).toString()
            with self._lock:
                self._exact_cache[cache_key] = result
            return result

        # 껍데기이거나 다운로드 중인 경우 캐시하지 않고 빈 문자열 반환 (다운로드 완료 시 재평가 가능하도록)
        return ""

    def get_path_for_difficulty(self, arcaea_id: str, difficulty: int) -> str:
        """특정 난이도 썸네일 → 해당 난이도가 없으면 우선순위 폴백."""
        if not arcaea_id:
            return ""

        cache_key = (arcaea_id, difficulty)
        with self._lock:
            if cache_key in self._path_cache:
                return self._path_cache[cache_key]

        exact = self.get_exact_path_for_difficulty(arcaea_id, difficulty)
        if exact:
            with self._lock:
                self._path_cache[cache_key] = exact
            return exact

        # 만약 해당 난이도의 파일이 디스크에 존재하지만 다운로드 중인 상태라면 다른 난이도로 잘못 폴백하지 않고 대기
        diff_code = DIFF_CODE_MAP.get(difficulty)
        if diff_code:
            exact_filename = f"{arcaea_id}_{diff_code}.jpg"
            exact_filepath = os.path.join(self._thumbnails_dir, exact_filename)
            if os.path.exists(exact_filepath) and not is_file_hydrated(exact_filepath):
                return ""

        fallback = self.find_by_priority(arcaea_id)
        if fallback:
            with self._lock:
                self._path_cache[cache_key] = fallback
            return fallback

        return ""

    def get_representative_color(self, arcaea_id: str, difficulty: int) -> str:
        """선택된 썸네일에서 추출한 대표 색상을 반환한다 (메모리 캐싱 및 Dataless 보호)."""
        if not arcaea_id:
            return "#FFFFFF"

        cache_key = (arcaea_id, difficulty)
        with self._lock:
            if cache_key in self._color_cache:
                return self._color_cache[cache_key]

        path_url = self.get_path_for_difficulty(arcaea_id, difficulty)
        if not path_url:
            return "#FFFFFF"

        local_path = QUrl(path_url).toLocalFile()
        if not local_path:
            local_path = path_url

        # Dataless 파일 여부 0ms 사전 검사 (메인 스레드 QImage 동기 블로킹 원천 차단)
        if not is_file_hydrated(local_path):
            return "#FFFFFF"

        try:
            image = QImage(local_path)
            if image.isNull():
                return "#FFFFFF"

            pixel = image.scaled(
                1,
                1,
                Qt.AspectRatioMode.IgnoreAspectRatio,
                Qt.TransformationMode.SmoothTransformation,
            ).pixel(0, 0)
            color = QColor(pixel)
            h, s, v, _ = color.getHsv()
            v = max(v, 220)
            if s > 20:
                s = max(s, 180)
            else:
                s = 0
            color.setHsv(h, s, v)
            result = color.name()
            with self._lock:
                self._color_cache[cache_key] = result
            return result
        except Exception:
            return "#FFFFFF"
