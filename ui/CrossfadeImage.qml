import QtQuick

Item {
    id: root

    // 외부 설정 프로퍼티
    property url targetSource: ""
    property int fillMode: Image.PreserveAspectCrop
    property bool smooth: true
    property bool antialiasing: true
    property int duration: 140
    property int easingType: Easing.OutQuad

    // 내부 상태 관리
    property int activeSlot: 0 // 0: slotA, 1: slotB
    property bool isTransitioning: false
    property url pendingSource: ""

    // 외부 읽기 전용 상태
    readonly property real activeOpacity: Math.max(slotA.opacity, slotB.opacity)
    readonly property bool isLoaded: ((activeSlot === 0 ? slotA.status : slotB.status) === Image.Ready) && activeOpacity > 0.0

    onTargetSourceChanged: {
        var currentSource = activeSlot === 0 ? slotA.source : slotB.source
        var currentOpacity = activeSlot === 0 ? slotA.opacity : slotB.opacity
        if (targetSource.toString() === currentSource.toString() && currentOpacity > 0.0) {
            pendingSource = ""
            return
        }

        if (targetSource === "" || targetSource.toString() === "") {
            // 소스 부재 시 페이드아웃
            pendingSource = ""
            fadeOutAnim.start()
            return
        }

        if (isTransitioning) {
            // 전환 중 인터럽트: 현재 애니메이션은 완주시키고 새 목표를 백그라운드 프리로드에 큐잉
            pendingSource = targetSource
            preloadSlot.source = targetSource
            return
        }

        // 안정 상태에서 새 이미지 입력: 비활성 슬롯에 로드 시작
        pendingSource = ""
        var inactiveSlot = activeSlot === 0 ? slotB : slotA
        inactiveSlot.source = targetSource
        if (inactiveSlot.status === Image.Ready) {
            root.startCrossfade(activeSlot === 0 ? 1 : 0)
        }
    }

    Component.onCompleted: {
        if (targetSource && targetSource.toString() !== "") {
            var inactiveSlot = activeSlot === 0 ? slotB : slotA
            inactiveSlot.source = targetSource
            if (inactiveSlot.status === Image.Ready) {
                root.startCrossfade(activeSlot === 0 ? 1 : 0)
            }
        }
    }

    // 슬롯 1 (화면 노출 1번)
    Image {
        id: slotA
        anchors.fill: parent
        asynchronous: true
        cache: true
        fillMode: root.fillMode
        smooth: root.smooth
        antialiasing: root.antialiasing
        opacity: root.activeSlot === 0 ? 1.0 : 0.0
        visible: opacity > 0.0
        z: root.activeSlot === 0 ? 1 : 0

        onStatusChanged: {
            if (status === Image.Ready && root.activeSlot === 1 && !root.isTransitioning) {
                if (slotA.source.toString() === root.targetSource.toString()) {
                    root.startCrossfade(0)
                }
            }
        }
    }

    // 슬롯 2 (화면 노출 2번)
    Image {
        id: slotB
        anchors.fill: parent
        asynchronous: true
        cache: true
        fillMode: root.fillMode
        smooth: root.smooth
        antialiasing: root.antialiasing
        opacity: root.activeSlot === 1 ? 1.0 : 0.0
        visible: opacity > 0.0
        z: root.activeSlot === 1 ? 1 : 0

        onStatusChanged: {
            if (status === Image.Ready && root.activeSlot === 0 && !root.isTransitioning) {
                if (slotB.source.toString() === root.targetSource.toString()) {
                    root.startCrossfade(1)
                }
            }
        }
    }

    // 백그라운드 프리로드 슬롯 (화면 미표시, 선행 디코딩 전용)
    Image {
        id: preloadSlot
        visible: false
        width: 0
        height: 0
        asynchronous: true
        cache: true

        onStatusChanged: {
            if (status === Image.Ready && !root.isTransitioning && root.pendingSource !== "") {
                if (preloadSlot.source.toString() === root.targetSource.toString()) {
                    root.handlePendingTransition()
                }
            }
        }
    }

    // Zero-Flicker Fade-Over 단일 페이드인 트랜지션:
    // 기존 활성 슬롯은 100% 불투명도(opacity: 1.0)로 밑바탕(z: 0)에 온전히 유지하고,
    // 새 슬롯만 최상단(z: 1)에 올려 0.0 -> 1.0으로 페이드인!
    // 이를 통해 전환 전 구간에서 합성 불투명도가 항상 100%로 유지되어 단색 플레이스홀더 노출 0% 보장.
    NumberAnimation {
        id: crossfadeAnim
        property int nextSlotIndex: 0
        duration: root.duration
        easing.type: root.easingType

        onFinished: {
            root.activeSlot = crossfadeAnim.nextSlotIndex
            root.isTransitioning = false

            // 새 이미지가 완전히 100%로 덮었으므로, 밑에 깔려 있던 이전 슬롯을 안전하게 정리
            var prevSlot = root.activeSlot === 0 ? slotB : slotA
            prevSlot.opacity = 0.0
            prevSlot.source = ""
            prevSlot.z = 0

            // 대기 중인 후속 요청이 있다면 지체 없이 연계
            var curSource = root.activeSlot === 0 ? slotA.source : slotB.source
            if (root.pendingSource !== "" && root.pendingSource.toString() !== curSource.toString()) {
                root.handlePendingTransition()
            }
        }
    }

    // 소스 부재 시 페이드아웃 애니메이션
    NumberAnimation {
        id: fadeOutAnim
        target: root.activeSlot === 0 ? slotA : slotB
        property: "opacity"
        to: 0.0
        duration: root.duration
        easing.type: root.easingType
        onFinished: {
            slotA.source = ""
            slotB.source = ""
            slotA.opacity = 0.0
            slotB.opacity = 0.0
            root.isTransitioning = false
        }
    }

    function startCrossfade(nextIndex) {
        root.isTransitioning = true
        crossfadeAnim.nextSlotIndex = nextIndex

        var newSlot = nextIndex === 0 ? slotA : slotB
        var oldSlot = nextIndex === 0 ? slotB : slotA

        // 1. Z-Order 설정: 새 슬롯을 최상단(z=1), 기존 슬롯을 밑바탕(z=0)
        newSlot.z = 1
        oldSlot.z = 0

        // 2. 불투명도 분기: 기존 슬롯에 유효한 이미지가 있고 불투명도가 > 0일 때만 1.0 보존 (Fade-Over)
        // 초기 로드나 reset() 직후 빈 상태에서는 0.0을 유지하여 activeOpacity의 조기 1.0 점프(스냅) 차단
        var hasExistingImage = (oldSlot.status === Image.Ready && oldSlot.source.toString() !== "" && oldSlot.opacity > 0.0)
        oldSlot.opacity = hasExistingImage ? 1.0 : 0.0
        newSlot.opacity = 0.0

        // 3. 단일 상단 레이어 페이드인 가동
        crossfadeAnim.target = newSlot
        crossfadeAnim.property = "opacity"
        crossfadeAnim.from = 0.0
        crossfadeAnim.to = 1.0
        crossfadeAnim.start()
    }

    function handlePendingTransition() {
        var nextTarget = root.pendingSource
        root.pendingSource = ""
        var targetNextSlot = root.activeSlot === 0 ? 1 : 0
        var nextSlotItem = targetNextSlot === 0 ? slotA : slotB

        nextSlotItem.source = nextTarget
        if (nextSlotItem.status === Image.Ready) {
            root.startCrossfade(targetNextSlot)
        }
        // 로드가 덜 끝난 경우 nextSlotItem.onStatusChanged에서 준비 완료 시 startCrossfade 트리거
    }

    function reset() {
        crossfadeAnim.stop()
        fadeOutAnim.stop()
        root.isTransitioning = false
        root.pendingSource = ""
        slotA.source = ""
        slotB.source = ""
        preloadSlot.source = ""
        slotA.opacity = 0.0
        slotB.opacity = 0.0
        slotA.z = 0
        slotB.z = 0
        root.activeSlot = 0
    }

    function ensureLoaded() {
        if (!targetSource || targetSource.toString() === "") {
            return
        }
        var currentSource = activeSlot === 0 ? slotA.source : slotB.source
        var currentOpacity = activeSlot === 0 ? slotA.opacity : slotB.opacity

        // 이미 활성 슬롯에 targetSource가 정상 표시 중(opacity > 0)이라면 no-op
        if (currentSource.toString() === targetSource.toString() && currentOpacity > 0.0 && !isTransitioning) {
            return
        }

        // 전환 중이던 애니메이션 정리 후 비활성 슬롯에 로드 시작
        crossfadeAnim.stop()
        fadeOutAnim.stop()
        isTransitioning = false
        pendingSource = ""

        var inactiveSlot = activeSlot === 0 ? slotB : slotA
        if (inactiveSlot.source.toString() !== targetSource.toString()) {
            inactiveSlot.source = targetSource
        }
        if (inactiveSlot.status === Image.Ready) {
            root.startCrossfade(activeSlot === 0 ? 1 : 0)
        }
    }
}

