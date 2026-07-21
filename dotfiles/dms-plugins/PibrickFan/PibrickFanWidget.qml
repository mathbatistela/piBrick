import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

// Bar widget + Control Center toggle for the piBrick CPU fan. Talks to the
// `pibrick-fan` CLI (see docs/setup/fan-control.md) rather than touching sysfs
// directly - that CLI already knows how to hold a manual level and hand
// control back to the kernel governor safely (see that doc for why a naive
// stop-and-hope handoff isn't safe on this hardware).
PluginComponent {
    id: root
    property var popoutService: null

    readonly property var levelNames: ["Off", "Low", "Med", "High", "Max"]

    property string mode: "unknown" // "auto" | "manual" | "unknown"
    property int curState: -1 // 0-4, always reflects the live cur_state
    property int manualLevel: -1 // 0-4, only meaningful when mode === "manual"
    property var tempC: null
    property var rpm: null
    property bool busy: false

    function levelLabel(n) {
        return n >= 0 && n < levelNames.length ? levelNames[n] : "?";
    }

    function parseStatus(stdout) {
        const modeMatch = stdout.match(/mode:\s*(auto|manual)/);
        const levelMatch = stdout.match(/level\s+(\d+)/);
        const curStateMatch = stdout.match(/cur_state=(\d+)/);
        const tempMatch = stdout.match(/temp=(-?\d+)C/);
        const rpmMatch = stdout.match(/rpm=(\d+)/);
        mode = modeMatch ? modeMatch[1] : "unknown";
        manualLevel = levelMatch ? parseInt(levelMatch[1], 10) : -1;
        curState = curStateMatch ? parseInt(curStateMatch[1], 10) : -1;
        tempC = tempMatch ? parseInt(tempMatch[1], 10) : null;
        rpm = rpmMatch ? parseInt(rpmMatch[1], 10) : null;
    }

    function refreshStatus() {
        Proc.runCommand("pibrickFan.status", ["sudo", "/usr/local/bin/pibrick-fan", "status"], (stdout, exitCode) => {
            if (exitCode === 0)
                parseStatus(stdout);
        });
    }

    function setLevel(n) {
        busy = true;
        Proc.runCommand("pibrickFan.set", ["sudo", "/usr/local/bin/pibrick-fan", "set", String(n)], (stdout, exitCode) => {
            busy = false;
            if (exitCode !== 0)
                ToastService?.showInfo("Fan control failed: exit " + exitCode);
            refreshStatus();
            // Only retry here if the debounce timer isn't running - if it is,
            // a newer request is still "settling" and will fire tryCommit()
            // itself when it elapses, rather than the instant this one finishes.
            if (!pendingDebounce.running)
                root.tryCommit();
        });
    }

    function setAuto() {
        busy = true;
        Proc.runCommand("pibrickFan.auto", ["sudo", "/usr/local/bin/pibrick-fan", "auto"], (stdout, exitCode) => {
            busy = false;
            if (exitCode !== 0)
                ToastService?.showInfo("Fan control failed: exit " + exitCode);
            refreshStatus();
            if (!pendingDebounce.running)
                root.tryCommit();
        });
    }

    // Single-flight, truly-debounced request queue shared by both slider
    // instances (popout + Control Center) and the mode toggle. A command is
    // only ever sent once scrolling has actually gone quiet for a full
    // `pendingDebounce` interval AND nothing else is in flight - never on
    // every tick, and never the instant a previous command happens to finish.
    // This alone doesn't cap *how often* commands go out over a longer fast
    // scroll, though - each one restarts pibrick-fan-manual.service, and
    // systemd's own default restart rate limit can still reject a burst of
    // legitimate serialized restarts; see StartLimitIntervalSec=0 in that
    // unit file for the other half of this fix.
    property int pendingLevel: -1 // -1 = nothing queued
    property bool pendingAuto: false

    function requestLevel(n) {
        pendingAuto = false;
        pendingLevel = n;
        pendingDebounce.restart();
    }

    function requestAuto() {
        pendingAuto = true;
        pendingLevel = -1;
        pendingDebounce.stop();
        tryCommit();
    }

    function tryCommit() {
        if (root.busy)
            return; // the in-flight command's own completion will retry
        if (pendingAuto) {
            pendingAuto = false;
            setAuto();
        } else if (pendingLevel >= 0) {
            const n = pendingLevel;
            pendingLevel = -1;
            setLevel(n);
        }
    }

    Timer {
        id: pendingDebounce
        interval: 250
        onTriggered: root.tryCommit()
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshStatus()
    }

    function statusLine() {
        const temp = root.tempC !== null ? root.tempC + "°C" : "--";
        const rpmText = root.rpm !== null ? root.rpm + " RPM" : "--";
        return temp + " · " + rpmText;
    }

    // Icon-only pills - this bar is already tight on this small screen, so no
    // text label. It still needs to exist as a real bar widget instance for
    // `dms ipc call widget toggle pibrickFan` (the Mod+S hotkey) to find it -
    // DMS's plugin popout mechanism has no way to open without one.
    horizontalBarPill: Component {
        StyledRect {
            width: parent.widgetThickness
            height: parent.widgetThickness
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            DankIcon {
                anchors.centerIn: parent
                name: "mode_fan"
                color: root.mode === "manual" ? Theme.primary : Theme.surfaceText
                size: Theme.iconSize - 4
            }
        }
    }

    verticalBarPill: Component {
        StyledRect {
            width: parent.widgetThickness
            height: parent.widgetThickness
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            DankIcon {
                anchors.centerIn: parent
                name: "mode_fan"
                color: root.mode === "manual" ? Theme.primary : Theme.surfaceText
                size: Theme.iconSizeSmall
            }
        }
    }

    popoutWidth: 380
    popoutHeight: 220

    popoutContent: Component {
        PopoutComponent {
            headerText: "CPU Fan"
            detailsText: root.statusLine()
            showCloseButton: true

            MouseArea {
                id: fanWheelArea
                width: parent.width
                height: content.implicitHeight
                acceptedButtons: Qt.MiddleButton // left clicks pass through to the toggle/slider below
                onClicked: mouse => {
                    if (mouse.button === Qt.MiddleButton)
                        root.requestAuto();
                }
                onWheel: wheel => {
                    const next = Math.max(0, Math.min(4, fanSlider.value + (wheel.angleDelta.y > 0 ? 1 : -1)));
                    fanSlider.value = next;
                    root.requestLevel(next);
                }

                // Wheel events are always positional (delivered to whatever's
                // under the cursor), never focus-based - opening this popup via
                // the Mod+S hotkey doesn't move the mouse there, so scrolling
                // does nothing until the cursor happens to be over it. DMS's
                // popup host already grabs keyboard focus on open
                // (PluginPopout.qml's forceActiveFocus()) and re-grabs it on
                // every reveal via a shouldBeVisibleChanged connection - the
                // content underneath is reused across opens, not recreated, so
                // a one-time Component.onCompleted focus grab here only ever
                // won that race on the very first open. Hooking the same
                // signal via the injected `parentPopout` (set by
                // PluginPopout.qml onto this content's root PopoutComponent)
                // re-claims focus every time, after DMS's own grab.
                focus: true
                Connections {
                    target: parentPopout
                    function onShouldBeVisibleChanged() {
                        if (parentPopout.shouldBeVisible)
                            Qt.callLater(() => fanWheelArea.forceActiveFocus());
                    }
                }
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Up || event.key === Qt.Key_Right) {
                        const next = Math.max(0, Math.min(4, fanSlider.value + 1));
                        fanSlider.value = next;
                        root.requestLevel(next);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Left) {
                        const next = Math.max(0, Math.min(4, fanSlider.value - 1));
                        fanSlider.value = next;
                        root.requestLevel(next);
                        event.accepted = true;
                    }
                }

                Column {
                    id: content
                    width: parent.width
                    spacing: Theme.spacingM

                    Item {
                        width: parent.width
                        height: Math.max(modeToggle.height, Theme.iconSize)

                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingS

                            DankIcon {
                                name: "mode_fan"
                                size: Theme.iconSize
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: root.mode === "manual" ? "Manual" : root.mode === "auto" ? "Auto" : "..."
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        DankToggle {
                            id: modeToggle
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            checked: root.mode === "manual"
                            onToggled: checked => {
                                if (checked)
                                    root.requestLevel(fanSlider.value >= 0 ? fanSlider.value : (root.curState >= 0 ? root.curState : 2));
                                else
                                    root.requestAuto();
                            }
                        }
                    }

                    DankSlider {
                        id: fanSlider
                        width: parent.width
                        minimum: 0
                        maximum: 4
                        step: 1
                        showValue: false
                        wheelEnabled: false // handled by the wrapping MouseArea above instead - this slider's own hit-area is thin and disabled outside manual mode, so it can't be the only way to scroll
                        enabled: root.mode === "manual"
                        value: 0

                        Component.onCompleted: value = root.manualLevel >= 0 ? root.manualLevel : Math.max(0, root.curState)

                        onSliderValueChanged: newValue => root.requestLevel(newValue)
                        onSliderDragFinished: finalValue => root.requestLevel(finalValue)

                        Connections {
                            target: root
                            function onManualLevelChanged() {
                                if (!fanSlider.isDragging && root.mode === "manual")
                                    fanSlider.value = Math.max(0, root.manualLevel);
                            }
                            function onCurStateChanged() {
                                if (!fanSlider.isDragging && root.mode !== "manual")
                                    fanSlider.value = Math.max(0, root.curState);
                            }
                        }
                    }

                    StyledText {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: root.levelLabel(fanSlider.value)
                        font.pixelSize: Theme.fontSizeSmall
                        color: root.mode === "manual" ? Theme.primary : Theme.surfaceVariantText
                    }
                }
            }
        }
    }

    ccWidgetIcon: "mode_fan"
    ccWidgetPrimaryText: "CPU Fan"
    ccWidgetSecondaryText: root.mode === "manual" ? root.levelLabel(root.manualLevel) : "Auto"
    ccWidgetIsActive: root.mode === "manual"

    onCcWidgetToggled: {
        if (root.mode === "manual")
            root.requestAuto();
        else
            root.requestLevel(4);
    }

    ccDetailContent: Component {
        Rectangle {
            implicitHeight: detailColumn.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            MouseArea {
                id: ccWheelArea
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.spacingM
                height: detailColumn.implicitHeight
                acceptedButtons: Qt.MiddleButton // left clicks pass through to the toggle/slider below
                onClicked: mouse => {
                    if (mouse.button === Qt.MiddleButton)
                        root.requestAuto();
                }
                onWheel: wheel => {
                    const next = Math.max(0, Math.min(4, ccFanSlider.value + (wheel.angleDelta.y > 0 ? 1 : -1)));
                    ccFanSlider.value = next;
                    root.requestLevel(next);
                }

                // Note: unlike the bar-pill popout above, the Control Center
                // detail panel isn't hotkey-reachable (only opened by tapping
                // its tile, cursor/touch already right there), and its host
                // doesn't inject a `parentPopout`-equivalent to hook a repeat
                // focus grab into - so this is a best-effort one-time attempt,
                // not depended on the way the popout's is.
                focus: true
                Component.onCompleted: Qt.callLater(() => ccWheelArea.forceActiveFocus())
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Up || event.key === Qt.Key_Right) {
                        const next = Math.max(0, Math.min(4, ccFanSlider.value + 1));
                        ccFanSlider.value = next;
                        root.requestLevel(next);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Left) {
                        const next = Math.max(0, Math.min(4, ccFanSlider.value - 1));
                        ccFanSlider.value = next;
                        root.requestLevel(next);
                        event.accepted = true;
                    }
                }

                Column {
                    id: detailColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    spacing: Theme.spacingM

                    Item {
                        width: parent.width
                        height: Math.max(ccModeToggle.height, Theme.iconSize)

                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingS

                            DankIcon {
                                name: "mode_fan"
                                size: Theme.iconSize
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: root.mode === "manual" ? "Manual" : root.mode === "auto" ? "Auto" : "..."
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        DankToggle {
                            id: ccModeToggle
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            checked: root.mode === "manual"
                            onToggled: checked => {
                                if (checked)
                                    root.requestLevel(ccFanSlider.value >= 0 ? ccFanSlider.value : (root.curState >= 0 ? root.curState : 2));
                                else
                                    root.requestAuto();
                            }
                        }
                    }

                    DankSlider {
                        id: ccFanSlider
                        width: parent.width
                        minimum: 0
                        maximum: 4
                        step: 1
                        showValue: false
                        wheelEnabled: false // handled by ccWheelArea above instead
                        enabled: root.mode === "manual"
                        value: 0

                        Component.onCompleted: value = root.manualLevel >= 0 ? root.manualLevel : Math.max(0, root.curState)

                        onSliderValueChanged: newValue => root.requestLevel(newValue)
                        onSliderDragFinished: finalValue => root.requestLevel(finalValue)

                        Connections {
                            target: root
                            function onManualLevelChanged() {
                                if (!ccFanSlider.isDragging && root.mode === "manual")
                                    ccFanSlider.value = Math.max(0, root.manualLevel);
                            }
                            function onCurStateChanged() {
                                if (!ccFanSlider.isDragging && root.mode !== "manual")
                                    ccFanSlider.value = Math.max(0, root.curState);
                            }
                        }
                    }

                    StyledText {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: root.levelLabel(ccFanSlider.value) + "  ·  " + root.statusLine()
                        font.pixelSize: Theme.fontSizeSmall
                        color: root.mode === "manual" ? Theme.primary : Theme.surfaceVariantText
                    }
                }
            }
        }
    }
}
