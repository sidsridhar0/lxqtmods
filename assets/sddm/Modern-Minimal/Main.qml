import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import SddmComponents 2.0

Rectangle {
    id: root

    color: "#171a1a"
    property int selectedSession: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
    property string message: ""

    function attemptLogin() {
        message = "Signing in…"
        sddm.login(username.text, password.text, selectedSession)
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            root.message = "Sign-in failed. Check your password and try again."
            password.clear()
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

                TextField {
                    id: username
                    Layout.fillWidth: true
                    text: userModel.lastUser
                    placeholderText: "Username"
                    color: "#eee9dc"
                    selectByMouse: true
                    font.pixelSize: 15
                    background: Rectangle {
                        radius: 10
                        color: "#171b1b"
                        border.color: username.activeFocus ? "#91d7cc" : "#414947"
                        border.width: 2
                    }
                }

                Text {
                    text: "PASSWORD"
                    color: "#91d7cc"
                    font.pixelSize: 11
                    font.bold: true
                    font.family: "monospace"
                }

                TextField {
                    id: password
                    Layout.fillWidth: true
                    placeholderText: "Password"
                    echoMode: TextInput.Password
                    color: "#eee9dc"
                    selectByMouse: true
                    font.pixelSize: 15
                    onAccepted: root.attemptLogin()
                    background: Rectangle {
                        radius: 10
                        color: "#171b1b"
                        border.color: password.activeFocus ? "#91d7cc" : "#414947"
                        border.width: 2
                    }
                }

                Button {
                    id: sessionButton
                    Layout.fillWidth: true
                    text: sessionModel.rowCount() > 0
                          ? sessionModel.data(sessionModel.index(root.selectedSession, 0), Qt.DisplayRole)
                          : "Default session"
                    onClicked: {
                        if (sessionModel.rowCount() > 0)
                            root.selectedSession = (root.selectedSession + 1) % sessionModel.rowCount()
                    }
                    contentItem: Text {
                        text: sessionButton.text + "  ·  change"
                        color: "#9baba7"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 12
                        font.family: "monospace"
                    }
                    background: Rectangle {
                        radius: 9
                        color: "#292f2e"
                    }
                }

                Button {
                    id: loginButton
                    Layout.fillWidth: true
                    Layout.topMargin: 5
                    text: "Sign in"
                    onClicked: root.attemptLogin()
                    contentItem: Text {
                        text: loginButton.text
                        color: "#111515"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 15
                        font.bold: true
                    }
                    background: Rectangle {
                        radius: 10
                        color: loginButton.down ? "#79bdb3" : "#91d7cc"
                        implicitHeight: 44
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
