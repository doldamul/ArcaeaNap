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

    // true이면 targetSource가 ""인 동안(클라우드 보관 썸네일 다운로드 대기 중)
    // 이전 이미지를 그대로 유지하고(없으면 빈 화면 유지), 유효한 target이 들어와 로드가 끝난 뒤에야 크로스페이드한다.
    // false이면 "" 는 '이미지 없음'으로 간주하여 기존 이미지를 페이드아웃한다.
    property bool holdWhileEmpty: false

    // 내부 상태 관리
    property int activeSlot: 0 // 0: slotA, 1: slotB
    property bool isTransitioning: false
    property url pendingSource: ""

    // 외부 읽기 전용 상태
    readonly property real activeOpacity: Math.max(slotA.opacity, slotB.opacity)
    readonly property bool isLoaded: ((activeSlot === 0 ? slotA.status : slotB.status) === Image.Ready) && activeOpacity > 0.0

    // ------------------------------------------------------------------
    // 동작 원칙
    //  - 모든 입력(targetSource 변경, 슬롯 로드 완료, 애니메이션 종료, ensureLoaded)은
    //    sync() 한 곳으로 모여, "현재 targetSource" 기준으로 슬롯 상태를 수렴시킨다.
    //  - 클라우드 보관(Dataless) 썸네일은 경로가 ""였다가 다운로드 완료 후 뒤늦게 유효해질 수 있고,
    //    사용자가 항목을 빠르게 바꾸면 진행 중인 애니메이션 도중에 target이 여러 번 바뀐다.
    //    따라서 어떤 애니메이션이 끝나는 시점에도 "그 시점의 target"을 다시 확인한다.
    // ------------------------------------------------------------------
    onTargetSourceChanged: root.sync()
    onHoldWhileEmptyChanged: root.sync()

    Component.onCompleted: root.sync()

    // 슬롯 1 (화면 노출 1번)
    Image {
        id: slotA
        anchors.fill: parent
        asynchronous: true
        cache: true
        fillMode: root.fillMode
        smooth: root.smooth
        antialiasing: root.antialiasing
        opacity: 0.0
        visible: opacity > 0.0
        z: 0

        onStatusChanged: {
            if (status === Image.Ready) root.sync()
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
        opacity: 0.0
        visible: opacity > 0.0
        z: 0

        onStatusChanged: {
            if (status === Image.Ready) root.sync()
        }
    }

    // 백그라운드 프리로드 슬롯 (화면 미표시, 전환 중 대기 요청의 선행 디코딩 전용)
    Image {
        id: preloadSlot
        visible: false
        width: 0
        height: 0
        asynchronous: true
        cache: true

        onStatusChanged: {
            if (status === Image.Ready && root.pendingSource.toString() !== "") root.sync()
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
            var curSlot = root.activeSlot === 0 ? slotA : slotB
            var prevSlot = root.activeSlot === 0 ? slotB : slotA
            curSlot.opacity = 1.0
            prevSlot.opacity = 0.0
            prevSlot.source = ""
            prevSlot.z = 0

            // 전환 도중 targetSource가 바뀌었을 수 있으므로, 종료 시점의 target 기준으로 재수렴
            root.sync()
        }
    }

    // 소스 부재 시 페이드아웃 애니메이션 (두 슬롯 모두 대상: 전환 중단 직후에도 잔상이 남지 않도록)
    ParallelAnimation {
        id: fadeOutAnim

        NumberAnimation {
            target: slotA
            property: "opacity"
            to: 0.0
            duration: root.duration
            easing.type: root.easingType
        }
        NumberAnimation {
            target: slotB
            property: "opacity"
            to: 0.0
            duration: root.duration
            easing.type: root.easingType
        }

        onFinished: {
            // 페이드아웃 도중 유효한 target이 다시 들어왔다면(fadeOutAnim.stop()으로 이미 중단됨) 지우지 않는다.
            if (root.targetSource.toString() !== "") return
            root.clearSlots()
        }
    }

    function activeItem() { return activeSlot === 0 ? slotA : slotB }
    function inactiveItem() { return activeSlot === 0 ? slotB : slotA }

    function clearSlots() {
        slotA.source = ""
        slotB.source = ""
        preloadSlot.source = ""
        slotA.opacity = 0.0
        slotB.opacity = 0.0
        slotA.z = 0
        slotB.z = 0
        root.pendingSource = ""
        root.isTransitioning = false
    }

    // 현재 targetSource에 맞춰 슬롯 상태를 수렴시키는 단일 진입점
    function sync() {
        var target = root.targetSource.toString()

        // 1-a. 소스 부재 + 다운로드 대기 중: 현재 표시를 그대로 유지 (진행 중인 전환은 끝까지 진행)
        if (target === "" && root.holdWhileEmpty) {
            root.pendingSource = ""
            preloadSlot.source = ""
            fadeOutAnim.stop()
            // 이전에 중단된 페이드아웃으로 투명해진 활성 이미지가 있다면 복원
            var heldActive = activeItem()
            if (!root.isTransitioning && heldActive.status === Image.Ready && heldActive.source.toString() !== "" && heldActive.opacity > 0.0) {
                heldActive.opacity = 1.0
            }
            return
        }

        // 1-b. 소스 부재: 진행 중인 전환을 중단하고 보이는 이미지를 페이드아웃
        if (target === "") {
            root.pendingSource = ""
            preloadSlot.source = ""
            if (crossfadeAnim.running) crossfadeAnim.stop()
            root.isTransitioning = false
            if (slotA.opacity > 0.0 || slotB.opacity > 0.0) {
                fadeOutAnim.restart()
            } else {
                fadeOutAnim.stop()
                clearSlots()
            }
            return
        }

        // 2. 크로스페이드 진행 중: 새 target이 진입 중인 슬롯과 다르면 대기 큐잉하고 백그라운드 프리로드
        //    (진행 중인 애니메이션은 끝까지 가며, onFinished에서 sync()가 재호출된다)
        if (root.isTransitioning) {
            var incoming = crossfadeAnim.nextSlotIndex === 0 ? slotA : slotB
            if (incoming.source.toString() !== target) {
                root.pendingSource = root.targetSource
                if (preloadSlot.source.toString() !== target) preloadSlot.source = root.targetSource
            } else {
                root.pendingSource = ""
            }
            return
        }

        // 3. 안정 상태
        var active = activeItem()
        var inactive = inactiveItem()

        // 3-1. 이미 활성 슬롯이 target을 표시 중이면 (페이드아웃이 진행 중이었더라도) 복원하고 종료
        if (active.source.toString() === target && active.status === Image.Ready && active.opacity > 0.0) {
            fadeOutAnim.stop()
            active.opacity = 1.0
            inactive.opacity = 0.0
            if (inactive.source.toString() !== "") inactive.source = ""
            root.pendingSource = ""
            return
        }

        // 3-2. 비활성 슬롯에 target 로드 (이미 로드 중/완료면 source 재지정 없음)
        fadeOutAnim.stop()
        root.pendingSource = ""
        if (inactive.source.toString() !== target) {
            inactive.opacity = 0.0
            inactive.source = root.targetSource
        }
        if (preloadSlot.source.toString() !== "") preloadSlot.source = ""

        // 3-3. 로드가 끝난 경우에만 크로스페이드 시작 (미완료면 onStatusChanged -> sync()로 재진입)
        if (inactive.status === Image.Ready) {
            root.startCrossfade(root.activeSlot === 0 ? 1 : 0)
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

        // 2. 불투명도 분기: 기존 슬롯에 유효한 이미지가 있고 불투명도가 > 0일 때만 그 불투명도를 보존 (Fade-Over)
        // 초기 로드나 reset() 직후 빈 상태에서는 0.0을 유지하여 activeOpacity의 조기 1.0 점프(스냅) 차단.
        // (페이드아웃이 중간에 끊긴 경우에도 현재 불투명도를 그대로 이어받아 이전 이미지가 다시 밝아지지 않음)
        var hasExistingImage = (oldSlot.status === Image.Ready && oldSlot.source.toString() !== "" && oldSlot.opacity > 0.0)
        oldSlot.opacity = hasExistingImage ? Math.min(1.0, oldSlot.opacity) : 0.0
        newSlot.opacity = 0.0

        // 3. 단일 상단 레이어 페이드인 가동
        fadeOutAnim.stop()
        crossfadeAnim.stop()
        crossfadeAnim.target = newSlot
        crossfadeAnim.property = "opacity"
        crossfadeAnim.from = 0.0
        crossfadeAnim.to = 1.0
        crossfadeAnim.start()
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

    // reset() 이후처럼 슬롯은 비었는데 targetSource만 유효한 경우 로드를 복원한다.
    function ensureLoaded() {
        if (!targetSource || targetSource.toString() === "") {
            return
        }
        var target = targetSource.toString()

        // 이미 활성 슬롯에 targetSource가 정상 표시 중(opacity > 0)이거나,
        // 같은 target으로 진입 중인 전환이 진행 중이라면 no-op
        var active = activeItem()
        if (!isTransitioning && active.source.toString() === target && active.status === Image.Ready && active.opacity > 0.0) {
            return
        }
        if (isTransitioning) {
            var incoming = crossfadeAnim.nextSlotIndex === 0 ? slotA : slotB
            if (incoming.source.toString() === target) {
                return
            }
        }

        // 엇갈린 전환/페이드아웃을 정리한 뒤 target 기준으로 재수렴
        crossfadeAnim.stop()
        fadeOutAnim.stop()
        isTransitioning = false
        pendingSource = ""
        root.sync()
    }
}
