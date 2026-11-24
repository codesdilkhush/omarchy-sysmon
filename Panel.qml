import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "codesdilkhush.sysmon"
  ipcTarget: "codesdilkhush.sysmon"
  manageIpc: false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property bool vertical: root.bar ? root.bar.vertical : false
  readonly property color foreground: root.barForeground
  readonly property color urgentColor: root.bar ? root.bar.urgent : Commons.Color.urgent
  readonly property color accentColor: Commons.Color.accent
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
  property bool showPercentage: setting("showPercentage", false) === true

  function togglePercentage() {
    showPercentage = !showPercentage
    root.settings = Object.assign({}, root.settings, { showPercentage: showPercentage })
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  ShellIpc {
    target: "codesdilkhush.sysmon"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function togglePercentage(): void { root.togglePercentage() }
  }

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  property int cpuPercent: 0
  property real prevCpuIdle: 0
  property real prevCpuTotal: 0

  property string memUsedGb: "0.0"
  property string memTotalGb: "0.0"
  property int memPercent: 0

  property string swapUsedGb: "0.0"
  property string swapTotalGb: "0.0"
  property int swapPercent: 0

  property string diskUsed: "0G"
  property string diskTotal: "0G"
  property int diskPercent: 0

  property string loadStr: "0.00, 0.00, 0.00"
  property int cores: 1
  property var topProcs: []
  property bool hasData: false

  function parseStats(raw) {
    try {
      var data = JSON.parse(raw)
      if (prevCpuTotal > 0 && data.cpu_total > prevCpuTotal) {
        var dIdle = data.cpu_idle - prevCpuIdle
        var dTotal = data.cpu_total - prevCpuTotal
        if (dTotal > 0) {
          cpuPercent = Math.max(0, Math.min(100, Math.round((1.0 - (dIdle / dTotal)) * 100)))
        }
      }
      prevCpuIdle = data.cpu_idle
      prevCpuTotal = data.cpu_total

      memUsedGb = (data.mem_used_mb / 1024).toFixed(1)
      memTotalGb = (data.mem_total_mb / 1024).toFixed(1)
      memPercent = Math.round(data.mem_pct)

      swapUsedGb = (data.swap_used_mb / 1024).toFixed(1)
      swapTotalGb = (data.swap_total_mb / 1024).toFixed(1)
      swapPercent = Math.round(data.swap_pct)

      diskUsed = data.disk_used || "0G"
      diskTotal = data.disk_total || "0G"
      diskPercent = data.disk_pct || 0

      loadStr = (data.load_1 || 0).toFixed(2) + ", " + (data.load_5 || 0).toFixed(2) + ", " + (data.load_15 || 0).toFixed(2)
      cores = data.cores || 1
      topProcs = data.top_procs || []
      hasData = true
    } catch (e) {
      // ignore parse error
    }
  }

  function refresh() {
    if (!statsProc.running) statsProc.running = true
  }

  function openBtop() {
    root.close()
    if (root.bar && typeof root.bar.run === "function") {
      root.bar.run("omarchy launch or focus tui btop")
    } else {
      Quickshell.execDetached(["omarchy", "launch", "or", "focus", "tui", "btop"])
    }
  }

  onOpenedChanged: {
    if (opened) {
      refresh()
    }
  }

  Process {
    id: statsProc
    command: [String(Qt.resolvedUrl("sysmon-stats.sh")).replace(/^file:\/\//, "")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseStats(text)
    }
  }

  Timer {
    interval: root.opened ? 1500 : 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf2db"
    labelText: root.showPercentage && !root.vertical ? (root.cpuPercent + "%") : ""
    slotSize: root.showPercentage && !root.vertical ? Style.bar.iconSlot * 2 : Style.bar.iconSlot
    tooltipText: strings.t("sysmon.tooltip").arg(root.cpuPercent).arg(root.memPercent) + " (" + root.memUsedGb + "G / " + root.memTotalGb + "G)"
    active: root.opened || root.cpuPercent >= 85
    activeColor: root.cpuPercent >= 85 ? root.urgentColor : root.accentColor
    onPressed: function(b) {
      if (b === Qt.RightButton) {
        root.togglePercentage()
      } else if (b === Qt.MiddleButton) {
        root.openBtop()
      } else {
        root.toggle()
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      implicitHeight: contentColumn.implicitHeight
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // Hero header
        Row {
          width: parent.width
          spacing: Style.space(12)

          Text {
            textFormat: Text.PlainText
            text: "\uf2db"
            color: root.accentColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: strings.t("sysmon.title")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              text: strings.tn("sysmon.cores", root.cores).arg(root.cores) + " · " + strings.t("sysmon.load") + ": " + root.loadStr
              color: root.foreground
              opacity: 0.65
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        // Gauges
        MetricBar {
          label: strings.t("sysmon.cpu")
          valueText: root.cpuPercent + "%"
          fraction: root.cpuPercent / 100.0
          urgentThreshold: 0.85
        }

        MetricBar {
          label: strings.t("sysmon.memory")
          valueText: root.memUsedGb + " / " + root.memTotalGb + " GB (" + root.memPercent + "%)"
          fraction: root.memPercent / 100.0
          urgentThreshold: 0.85
        }

        MetricBar {
          visible: Number(root.swapTotalGb) > 0
          label: strings.t("sysmon.swap")
          valueText: root.swapUsedGb + " / " + root.swapTotalGb + " GB (" + root.swapPercent + "%)"
          fraction: root.swapPercent / 100.0
          urgentThreshold: 0.85
        }

        MetricBar {
          label: strings.t("sysmon.disk")
          valueText: root.diskUsed + " / " + root.diskTotal + " (" + root.diskPercent + "%)"
          fraction: root.diskPercent / 100.0
          urgentThreshold: 0.90
        }

        PanelSeparator { foreground: root.foreground }

        // Top processes
        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: root.topProcs.length > 0

          PanelSectionHeader {
            text: strings.t("sysmon.topProcs")
            foreground: root.foreground
          }

          Repeater {
            model: root.topProcs
            Item {
              required property var modelData
              width: parent.width
              implicitHeight: Style.space(18)

              Text {
                textFormat: Text.PlainText
                text: modelData.name || ""
                elide: Text.ElideRight
                width: Style.space(140)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                textFormat: Text.PlainText
                text: (modelData.cpu || 0).toFixed(1) + "% CPU"
                color: (modelData.cpu || 0) > 20 ? root.urgentColor : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: (modelData.cpu || 0) > 20
                anchors.right: ramLabel.left
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: ramLabel
                textFormat: Text.PlainText
                text: (modelData.mem || 0).toFixed(1) + "% RAM"
                color: root.foreground
                opacity: 0.65
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }
          }
        }

        PanelSeparator {
          visible: root.topProcs.length > 0
          foreground: root.foreground
        }

        // Action button
        Button {
          width: parent.width
          text: strings.t("sysmon.openBtop")
          iconText: "\uf080"
          foreground: root.foreground
          fontFamily: root.fontFamily
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          bordered: true
          onClicked: root.openBtop()
        }
      }
    }
  }

  component MetricBar: Column {
    property string label: ""
    property string valueText: ""
    property real fraction: 0.0
    property real urgentThreshold: 0.85

    width: parent ? parent.width : 0
    spacing: Style.space(4)

    Row {
      width: parent.width
      Text {
        textFormat: Text.PlainText
        text: label
        color: root.foreground
        opacity: 0.7
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        anchors.verticalCenter: parent.verticalCenter
      }
      Item {
        width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth)
        height: 1
      }
      Text {
        textFormat: Text.PlainText
        text: valueText
        color: fraction >= urgentThreshold ? root.urgentColor : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: fraction >= urgentThreshold
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Rectangle {
      id: track
      width: parent.width
      height: Style.space(6)
      radius: height / 2
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

      Rectangle {
        anchors.left: track.left
        anchors.verticalCenter: track.verticalCenter
        height: track.height
        radius: track.radius
        color: fraction >= urgentThreshold ? root.urgentColor : root.accentColor
        width: Math.max(track.height, Math.min(track.width, track.width * Math.max(0, Math.min(1, fraction))))

        Behavior on width {
          NumberAnimation {
            duration: Style.duration(320)
            easing.type: Easing.OutCubic
          }
        }
      }
    }
  }
}
