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
  ipcTarget: ""
  manageIpc: false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property bool vertical: root.bar ? root.bar.vertical : false
  readonly property color foreground: root.barForeground
  readonly property color urgentColor: root.bar ? root.bar.urgent : Commons.Color.urgent
  readonly property color accentColor: Commons.Color.accent
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
  property bool showPercentage: setting("showPercentage", false) === true
  property string defaultTop: setting("defaultTop", "btop")

  property var availableTops: ["btop"]
  readonly property var advancedTops: availableTops.filter(function(t) { return t !== "top" || availableTops.length === 1 })

  property string netInterface: ""
  property real prevNetRx: 0
  property real prevNetTx: 0
  property real prevNetTime: 0
  property string netDownStr: "0 B/s"
  property string netUpStr: "0 B/s"
  property string netRxTotalStr: "0 B"
  property string netTxTotalStr: "0 B"

  function formatSpeed(bytesPerSec) {
    if (!bytesPerSec || bytesPerSec <= 0) return "0 B/s"
    if (bytesPerSec >= 1073741824) return (bytesPerSec / 1073741824).toFixed(1) + " GB/s"
    if (bytesPerSec >= 1048576) return (bytesPerSec / 1048576).toFixed(1) + " MB/s"
    if (bytesPerSec >= 1024) return (bytesPerSec / 1024).toFixed(0) + " KB/s"
    return Math.round(bytesPerSec) + " B/s"
  }

  function formatBytes(bytes) {
    if (!bytes || bytes <= 0) return "0 B"
    if (bytes >= 1073741824) return (bytes / 1073741824).toFixed(1) + " GB"
    if (bytes >= 1048576) return (bytes / 1048576).toFixed(1) + " MB"
    if (bytes >= 1024) return (bytes / 1024).toFixed(0) + " KB"
    return Math.round(bytes) + " B"
  }

  function togglePercentage() {
    showPercentage = !showPercentage
    root.settings = Object.assign({}, root.settings, { showPercentage: showPercentage })
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  function isAvailable(cmd) {
    return availableTops && availableTops.indexOf(cmd) !== -1
  }

  function getSystemMonitorCmd() {
    if (defaultTop && isAvailable(defaultTop)) {
      return defaultTop
    }
    var preference = ["btop", "htop", "btm", "top"]
    for (var i = 0; i < preference.length; i++) {
      if (isAvailable(preference[i])) return preference[i]
    }
    return availableTops.length > 0 ? availableTops[0] : "btop"
  }
  function getSystemManagerCmd() { return getSystemMonitorCmd() }

  function getSystemMonitorName() {
    var cmd = getSystemMonitorCmd()
    if (cmd === "btm") return "bottom"
    return cmd
  }
  function getSystemManagerName() { return getSystemMonitorName() }

  function getTopLabel(cmd) {
    if (cmd === "btm") return "bottom"
    return cmd
  }

  function getTopIcon(cmd) {
    if (cmd === "htop") return "\uf0ae"
    if (cmd === "btm" || cmd === "bottom") return "\uf1fe"
    if (cmd === "top") return "\uf120"
    return "\uf080" // btop
  }

  function setDefaultTop(cmd) {
    if (!cmd) return
    defaultTop = cmd
    root.settings = Object.assign({}, root.settings, { defaultTop: cmd })
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  function launchSystemMonitor(cmd) {
    root.close()
    var target = cmd || getSystemMonitorCmd()
    if (root.bar && typeof root.bar.run === "function") {
      root.bar.run("omarchy launch or focus tui " + target)
    } else {
      Quickshell.execDetached(["omarchy", "launch", "or", "focus", "tui", target])
    }
  }
  function launchSystemManager(cmd) { return launchSystemMonitor(cmd) }

  function openBtop() {
    launchSystemMonitor()
  }

  ShellIpc {
    target: root.moduleName
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function togglePercentage(): void { root.togglePercentage() }
    function openSystemMonitor(): void { root.launchSystemMonitor() }
    function openSystemManager(): void { root.launchSystemMonitor() }
    function launch(monitor: string): void { root.launchSystemMonitor(monitor) }
    function setDefault(monitor: string): void { root.setDefaultTop(monitor) }
  }

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  property int cpuPercent: 0
  property int cpuTemp: 0
  property real prevCpuIdle: 0
  property real prevCpuTotal: 0

  property int gpuPercent: 0
  property int gpuTemp: 0
  property string gpuName: "GPU"
  property string gpuClock: ""
  property real prevGpuRc6: 0
  property real prevGpuTime: 0

  property bool hasBattery: false
  property int batteryPercent: 0
  property string batteryStatus: ""
  property string batteryPowerW: "0.0"

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

      gpuName = data.gpu_name || "GPU"
      gpuClock = data.gpu_clock || ""

      if (data.gpu_pct !== undefined && data.gpu_pct > 0) {
        gpuPercent = Math.max(0, Math.min(100, Math.round(data.gpu_pct)))
      } else if (data.gpu_rc6_ms !== undefined && data.gpu_timestamp_ms !== undefined) {
        if (prevGpuTime > 0 && data.gpu_timestamp_ms > prevGpuTime) {
          var dt = data.gpu_timestamp_ms - prevGpuTime
          var dRc6 = data.gpu_rc6_ms - prevGpuRc6
          if (dt > 0 && dRc6 >= 0) {
            var idleFraction = Math.min(1.0, Math.max(0.0, dRc6 / dt))
            gpuPercent = Math.max(0, Math.min(100, Math.round((1.0 - idleFraction) * 100)))
          }
        }
        prevGpuRc6 = data.gpu_rc6_ms
        prevGpuTime = data.gpu_timestamp_ms
      }

      netInterface = data.net_iface || ""
      if (data.net_rx_bytes !== undefined && data.net_tx_bytes !== undefined && data.gpu_timestamp_ms !== undefined) {
        if (prevNetTime > 0 && data.gpu_timestamp_ms > prevNetTime) {
          var dtNet = (data.gpu_timestamp_ms - prevNetTime) / 1000.0
          if (dtNet > 0) {
            var dRx = Math.max(0, data.net_rx_bytes - prevNetRx)
            var dTx = Math.max(0, data.net_tx_bytes - prevNetTx)
            netDownStr = root.formatSpeed(dRx / dtNet)
            netUpStr = root.formatSpeed(dTx / dtNet)
          }
        }
        prevNetRx = data.net_rx_bytes
        prevNetTx = data.net_tx_bytes
        prevNetTime = data.gpu_timestamp_ms

        netRxTotalStr = root.formatBytes(data.net_rx_bytes)
        netTxTotalStr = root.formatBytes(data.net_tx_bytes)
      }

      if (data.available_tops && data.available_tops.length > 0) {
        availableTops = data.available_tops
      }

      memUsedGb = (data.mem_used_mb / 1024).toFixed(1)
      memTotalGb = (data.mem_total_mb / 1024).toFixed(1)
      memPercent = Math.round(data.mem_pct)

      swapUsedGb = (data.swap_used_mb / 1024).toFixed(1)
      swapTotalGb = (data.swap_total_mb / 1024).toFixed(1)
      swapPercent = Math.round(data.swap_pct)

      diskUsed = data.disk_used || "0G"
      diskTotal = data.disk_total || "0G"
      diskPercent = data.disk_pct || 0

      cpuTemp = data.cpu_temp || 0
      gpuTemp = data.gpu_temp || 0
      hasBattery = data.has_battery || false
      batteryPercent = data.battery_pct !== undefined ? Math.round(data.battery_pct) : 0
      batteryStatus = data.battery_status || ""
      batteryPowerW = data.battery_power_w !== undefined ? String(data.battery_power_w) : "0.0"

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
    tooltipText: strings.t("sysmon.tooltip").arg(root.cpuPercent).arg(root.gpuPercent).arg(root.memPercent).arg(root.cpuTemp).arg(root.gpuTemp) + " (" + root.memUsedGb + "G / " + root.memTotalGb + "G)\n↓ " + root.netDownStr + "  ↑ " + root.netUpStr + (root.hasBattery ? ("\nBattery: " + root.batteryPercent + "% (" + root.batteryStatus + ")") : "")
    active: root.opened || root.cpuPercent >= 85 || root.gpuPercent >= 85
    activeColor: (root.cpuPercent >= 85 || root.gpuPercent >= 85) ? root.urgentColor : root.accentColor
    onPressed: function(b) {
      if (b === Qt.RightButton) {
        root.togglePercentage()
      } else if (b === Qt.MiddleButton) {
        root.launchSystemMonitor()
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
            width: Math.max(0, parent.width - Style.space(36))
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Row {
              width: parent.width

              Text {
                textFormat: Text.PlainText
                text: strings.t("sysmon.title")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }

              Item {
                width: Math.max(0, parent.width - parent.children[0].implicitWidth - netRatesRow.implicitWidth)
                height: 1
              }

              Row {
                id: netRatesRow
                spacing: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  textFormat: Text.PlainText
                  text: "↓ " + root.netDownStr
                  color: root.accentColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
                Text {
                  textFormat: Text.PlainText
                  text: "↑ " + root.netUpStr
                  color: root.accentColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
              }
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
          label: strings.t("sysmon.cpu") + (root.cpuTemp > 0 ? (" (" + root.cpuTemp + "°C)") : "")
          valueText: root.cpuPercent + "%"
          fraction: root.cpuPercent / 100.0
          urgentThreshold: 0.85
        }

        MetricBar {
          label: strings.t("sysmon.gpu") + (root.gpuTemp > 0 ? (" (" + root.gpuTemp + "°C)") : "")
          valueText: (root.gpuClock ? (root.gpuClock + " · ") : "") + root.gpuPercent + "%"
          fraction: root.gpuPercent / 100.0
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

        // Battery Monitor Row
        MetricBar {
          visible: root.hasBattery
          label: strings.t("sysmon.battery") + (root.batteryStatus ? (" (" + root.batteryStatus + ")") : "")
          valueText: (Number(root.batteryPowerW) > 0 ? (root.batteryPowerW + "W · ") : "") + root.batteryPercent + "%"
          fraction: root.batteryPercent / 100.0
          urgentThreshold: 0.20
          invertUrgent: true
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

        // Action button: Open System Monitor
        Column {
          width: parent.width
          spacing: Style.space(6)

          Button {
            width: parent.width
            text: strings.t("sysmon.openSystemMonitor")
            iconText: root.getTopIcon(root.getSystemMonitorCmd())
            foreground: root.foreground
            fontFamily: root.fontFamily
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            bordered: true
            tooltipText: "Open " + root.getSystemMonitorName()
            onClicked: root.launchSystemMonitor()
          }

          // If multiple advanced system monitors are installed, allow switching:
          Row {
            visible: root.advancedTops.length > 1
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.advancedTops

              Button {
                required property var modelData
                width: Math.floor((parent.width - ((root.advancedTops.length - 1) * Style.space(6))) / root.advancedTops.length)
                text: root.getTopLabel(modelData)
                iconText: root.getTopIcon(modelData)
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                selected: root.getSystemMonitorCmd() === modelData
                tooltipText: "Set " + root.getTopLabel(modelData) + " as default system monitor"
                horizontalPadding: Style.space(4)
                verticalPadding: Style.space(4)
                bordered: true
                onClicked: {
                  root.setDefaultTop(modelData)
                  root.launchSystemMonitor(modelData)
                }
              }
            }
          }
        }
      }
    }
  }

  component MetricBar: Column {
    property string label: ""
    property string valueText: ""
    property real fraction: 0.0
    property real urgentThreshold: 0.85
    property bool invertUrgent: false
    readonly property bool isUrgent: (!invertUrgent && fraction >= urgentThreshold) || (invertUrgent && fraction <= urgentThreshold)

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
        color: isUrgent ? root.urgentColor : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: isUrgent
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
        color: isUrgent ? root.urgentColor : root.accentColor
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
