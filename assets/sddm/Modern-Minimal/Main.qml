import QtQuick 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: root

    color: "#171a1a"
    property int selectedSession: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
    property string message: ""

    function sessionLabel() {
        if (sessionModel.rowCount() <= 0)
            return "Default session"
        var modelIndex = sessionModel.index(root.selectedSession, 0)
        var name = sessionModel.data(modelIndex, Qt.DisplayRole)
        if (name === undefined || name === null || name === "")
            name = sessionModel.data(modelIndex, Qt.UserRole + 2)
        return name ? name : "Session " + (root.selectedSession + 1)
    }

    function attemptLogin() {
        message = "Signing in…"
        sddm.login(username.text, password.text, selectedSession)
    }

    Connections {
        target: sddm

        function onLoginFailed() {
            root.message = "Sign-in failed. Check your password and try again."
            password.text = ""
            password.forceActiveFocus()
        }

        function onInformationMessage(message) {
            root.message = message
        }
    }

    Rectangle {
        width: Math.max(parent.width, parent.height) * 0.58
        height: width
        radius: width / 2
        color: "#1e2928"
        opacity: 0.42
        x: parent.width * 0.62
        y: -height * 0.42
    }

    Rectangle {
        width: Math.max(parent.width, parent.height) * 0.42
        height: width
        radius: width / 2
        color: "#23302e"
        opacity: 0.30
        x: -width * 0.42
        y: parent.height * 0.58
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(390, parent.width - 48)
        spacing: 18

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: 54
            height: 54
            radius: 17
            color: "#91d7cc"
            Text {
                anchors.centerIn: parent
                text: "L"
                color: "#111515"
                font.pixelSize: 29
                font.bold: true
                font.family: "monospace"
            }
        }

        Text {
            Layout.fillWidth: true
            text: "Welcome back"
            color: "#eee9dc"
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 30
            font.bold: true
        }

        Text {
            Layout.fillWidth: true
            text: Qt.formatDateTime(new Date(), "dddd, MMMM d  •  hh:mm")
            color: "#9baba7"
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 13
            font.family: "monospace"
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 7
            radius: 18
            color: "#222727"
            border.color: "#343b39"
            border.width: 2
            implicitHeight: loginColumn.implicitHeight + 40

            ColumnLayout {
                id: loginColumn
                anchors.fill: parent
                anchors.margins: 20
                spacing: 13

                Text {
                    text: "USERNAME"
                    color: "#91d7cc"
                    font.pixelSize: 11
                    font.bold: true
                    font.family: "monospace"
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    radius: 10
                    color: "#171b1b"
                    border.color: username.activeFocus ? "#91d7cc" : "#414947"
                    border.width: 2

                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        verticalAlignment: Text.AlignVCenter
                        text: "Username"
                        color: "#6d7c78"
                        font.pixelSize: 15
                        visible: username.text.length === 0
                    }

                    TextInput {
                        id: username
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        verticalAlignment: TextInput.AlignVCenter
                        text: userModel.lastUser
                        color: "#eee9dc"
                        clip: true
                        selectByMouse: true
                        font.pixelSize: 15
                        KeyNavigation.tab: password
                    }
                }

                Text {
                    text: "PASSWORD"
                    color: "#91d7cc"
                    font.pixelSize: 11
                    font.bold: true
                    font.family: "monospace"
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    radius: 10
                    color: "#171b1b"
                    border.color: password.activeFocus ? "#91d7cc" : "#414947"
                    border.width: 2

                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        verticalAlignment: Text.AlignVCenter
                        text: "Password"
                        color: "#6d7c78"
                        font.pixelSize: 15
                        visible: password.text.length === 0
                    }

                    TextInput {
                        id: password
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password
                        color: "#eee9dc"
                        clip: true
                        selectByMouse: true
                        font.pixelSize: 15
                        inputMethodHints: Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoAutoUppercase
                        KeyNavigation.tab: username
                        KeyNavigation.backtab: username
                        onAccepted: root.attemptLogin()
                    }
                }

                Rectangle {
                    id: sessionButton
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    radius: 9
                    color: sessionMouse.pressed ? "#353e3b" : "#292f2e"

                    Text {
                        anchors.centerIn: parent
                        text: root.sessionLabel() + "  ·  change"
                        color: "#9baba7"
                        font.pixelSize: 12
                        font.family: "monospace"
                    }

                    MouseArea {
                        id: sessionMouse
                        anchors.fill: parent
                        onClicked: {
                            if (sessionModel.rowCount() > 0)
                                root.selectedSession = (root.selectedSession + 1) % sessionModel.rowCount()
                        }
                    }
                }

                Rectangle {
                    id: loginButton
                    Layout.fillWidth: true
                    Layout.topMargin: 5
                    Layout.preferredHeight: 44
                    radius: 10
                    color: loginMouse.pressed ? "#79bdb3" : "#91d7cc"

                    Text {
                        anchors.centerIn: parent
                        text: "Sign in"
                        color: "#111515"
                        font.pixelSize: 15
                        font.bold: true
                    }

                    MouseArea {
                        id: loginMouse
                        anchors.fill: parent
                        onClicked: root.attemptLogin()
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: root.message
                    color: "#e9a28f"
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    font.pixelSize: 12
                }
            }
        }
    }

    Component.onCompleted: {
        if (username.text.length > 0)
            password.forceActiveFocus()
        else
            username.forceActiveFocus()
    }
}
