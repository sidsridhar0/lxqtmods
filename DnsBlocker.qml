pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

Singleton {
    id: root

    readonly property string helper: Qt.resolvedUrl("lucidprefs/dnsblocker.py").toString().replace("file://", "")
    property bool enabled: false
    property bool available: false
    property bool loaded: false
    property bool busy: false
    property int profiles: 0
    property string warning: ""
    property string error: ""
    property string action: ""
    property string output: ""

    function refresh() {
        root.run("status");
    }

    function setEnabled(value) {
        root.run(value ? "enable" : "disable");
    }

    function run(nextAction) {
        if (root.busy)
            return;

        root.action = nextAction;
        root.error = "";
        root.warning = "";
        root.output = "";
        root.busy = true;
        blockerProc.command = ["python3", root.helper, nextAction];
        blockerProc.running = true;
    }

    Process {
        id: blockerProc

        stdout: StdioCollector {
            onStreamFinished: root.output = text.trim()
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "" && root.error === "")
                    root.error = text.trim();
            }
        }

        onExited: (code) => {
            root.busy = false;
            let result = null;
            try {
                result = JSON.parse(root.output);
            } catch (e) {
                root.error = root.error || "The DNS blocker returned an invalid response.";
            }
            if (result) {
                if (result.error)
                    root.error = result.error;
                else {
                    root.enabled = result.enabled === true;
                    if (result.available !== undefined)
                        root.available = result.available === true;
                    root.loaded = true;
                    root.profiles = Number(result.profiles) || 0;
                    root.warning = result.warning || "";
                }
            }
            if (result && result.error) {
                if (result.enabled !== undefined)
                    root.enabled = result.enabled === true;
                if (result.available !== undefined)
                    root.available = result.available === true;
                if (result.profiles !== undefined)
                    root.profiles = Number(result.profiles) || 0;
                root.loaded = true;
            }
            if (code !== 0 && root.error === "")
                root.error = "The DNS blocker could not complete the request.";
            if (root.action !== "status" && root.error === "")
                Net.refresh();
        }
    }
}
