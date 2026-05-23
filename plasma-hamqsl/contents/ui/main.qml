import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    preferredRepresentation: fullRepresentation

    // ── Date ──────────────────────────────────────────────────────────────────
    property string sfi:      "—"
    property string aIndex:   "—"
    property string kIndex:   "—"
    property string sunspots: "—"
    property string xray:     "—"
    property string geomag:   "—"
    property var    bands:    ({})
    property string updated:  ""
    property bool   loading:  true
    property bool   hasError: false

    // ── Parsare XML ───────────────────────────────────────────────────────────
    function tagValue(xml, tag) {
        var open  = "<" + tag + ">"
        var close = "</" + tag + ">"
        var s = xml.indexOf(open)
        if (s === -1) return "—"
        s += open.length
        var e = xml.indexOf(close, s)
        return (e === -1) ? "—" : xml.substring(s, e).trim()
    }

    function parseBands(xml) {
        var result = {}
        var pos = 0
        while (pos < xml.length) {
            var start  = xml.indexOf("<band ", pos)
            if (start === -1) break
            var tagEnd = xml.indexOf(">", start)
            var valEnd = xml.indexOf("</band>", tagEnd)
            if (tagEnd === -1 || valEnd === -1) break
            var tag   = xml.substring(start, tagEnd + 1)
            var value = xml.substring(tagEnd + 1, valEnd).trim()
            var nm    = tag.match(/name="([^"]+)"/)
            var tm    = tag.match(/time="([^"]+)"/)
            if (nm && tm) result[nm[1] + "_" + tm[1]] = value
            pos = valEnd + 7
        }
        return result
    }

    // ── Fetch date ────────────────────────────────────────────────────────────
    function fetch() {
        root.loading = true
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== 4) return
            if (xhr.status === 200) {
                var t = xhr.responseText
                root.sfi      = tagValue(t, "SFI")
                root.aIndex   = tagValue(t, "aindex")
                root.kIndex   = tagValue(t, "kindex")
                root.sunspots = tagValue(t, "sunspots")
                root.xray     = tagValue(t, "xray")
                root.geomag   = tagValue(t, "geomagsphere")
                root.bands    = parseBands(t)
                root.updated  = Qt.formatTime(new Date(), "hh:mm")
                root.hasError = false
            } else {
                root.hasError = true
            }
            root.loading = false
        }
        xhr.open("GET", "http://www.hamqsl.com/solar.xml")
        xhr.send()
    }

    Timer { interval: 600000; running: true; repeat: true; onTriggered: root.fetch() }
    Component.onCompleted: root.fetch()

    // ── Culori ───────────────────────────────────────────────────────────────
    function condColor(c) {
        if (c === "Good") return "#4CAF50"
        if (c === "Fair") return "#FF9800"
        if (c === "Poor") return "#F44336"
        return "#555555"
    }
    function kColor(k) {
        var v = parseInt(k, 10)
        if (isNaN(v)) return "#888888"
        if (v <= 2)   return "#4CAF50"
        if (v <= 4)   return "#FF9800"
        return "#F44336"
    }
    function aColor(a) {
        var v = parseInt(a, 10)
        if (isNaN(v)) return "#888888"
        if (v <= 7)   return "#4CAF50"
        if (v <= 15)  return "#FF9800"
        return "#F44336"
    }

    // ── UI ────────────────────────────────────────────────────────────────────
    fullRepresentation: Rectangle {
        width:  280
        radius: 10
        color:  Qt.rgba(0.06, 0.06, 0.10, 0.88)
        implicitHeight: col.implicitHeight + 24
        border.color: Qt.rgba(1, 1, 1, 0.10)
        border.width: 1

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
            spacing: 10

            // Header
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "HF Propagation"
                    color: "#ffffff"
                    font { pixelSize: 15; bold: true }
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: root.loading ? "…" : (root.hasError ? "ERR" : root.updated)
                    color: root.hasError ? "#F44336" : "#888888"
                    font.pixelSize: 11
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(1,1,1,0.15) }

            // Indici solari
            RowLayout {
                Layout.fillWidth: true
                spacing: 0

                Repeater {
                    model: [
                        { label: "SFI",   value: root.sfi,      color: "#90CAF9"                  },
                        { label: "A-Idx", value: root.aIndex,   color: root.aColor(root.aIndex)   },
                        { label: "K-Idx", value: root.kIndex,   color: root.kColor(root.kIndex)   },
                        { label: "Spots", value: root.sunspots, color: "#CE93D8"                  },
                        { label: "X-Ray", value: root.xray,     color: "#FFCC80"                  }
                    ]

                    delegate: ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.label
                            color: "#888888"; font.pixelSize: 9
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.value
                            color: modelData.color
                            font { pixelSize: 16; bold: true }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(1,1,1,0.15) }

            // Header benzi
            RowLayout {
                Layout.fillWidth: true
                spacing: 0
                Item { Layout.preferredWidth: 72 }
                Text {
                    text: "☀  Zi"
                    color: "#FFD54F"; font.pixelSize: 10
                    Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    text: "☾  Noapte"
                    color: "#90CAF9"; font.pixelSize: 10
                    Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                }
            }

            // Rânduri benzi
            Repeater {
                model: ["80m-40m", "30m-20m", "17m-15m", "10m-12m"]

                delegate: RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    property string dayVal:   root.bands[modelData + "_day"]   || "—"
                    property string nightVal: root.bands[modelData + "_night"] || "—"

                    Text {
                        text: modelData
                        color: "#cccccc"; font.pixelSize: 11
                        Layout.preferredWidth: 68
                    }

                    Rectangle {
                        Layout.fillWidth: true; height: 20; radius: 4
                        color: root.condColor(dayVal); opacity: 0.85
                        Text {
                            anchors.centerIn: parent
                            text: dayVal; color: "white"
                            font { pixelSize: 10; bold: true }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true; height: 20; radius: 4
                        color: root.condColor(nightVal); opacity: 0.85
                        Text {
                            anchors.centerIn: parent
                            text: nightVal; color: "white"
                            font { pixelSize: 10; bold: true }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(1,1,1,0.15) }

            // Câmp geomagnetic
            RowLayout {
                Layout.fillWidth: true
                Text { text: "Câmp geomagnetic:"; color: "#888888"; font.pixelSize: 10 }
                Item { Layout.fillWidth: true }
                Text { text: root.geomag; color: "#ffffff"; font { pixelSize: 10; bold: true } }
            }

            // Sursă + buton refresh
            RowLayout {
                Layout.fillWidth: true
                Text { text: "hamqsl.com"; color: "#444444"; font.pixelSize: 9 }
                Item { Layout.fillWidth: true }
                Text {
                    text: "↺"; color: "#666666"; font.pixelSize: 14
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.fetch()
                    }
                }
            }

            Item { height: 2 }
        }
    }
}
