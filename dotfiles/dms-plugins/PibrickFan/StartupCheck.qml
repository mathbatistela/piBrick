import QtQuick
import qs.Common

QtObject {
    function check(done) {
        Proc.runCommand("pibrickFan.depCheck", ["sh", "-c", "command -v pibrick-fan"], (stdout, exitCode) => {
            if (exitCode === 0) {
                done(null);
                return;
            }
            done({
                "title": "pibrick-fan is required",
                "details": "The 'pibrick-fan' CLI wasn't found on PATH.\n\nIt's installed by the piBrick admin repo's Ansible dotfiles/fan role (ansible/roles/dotfiles/tasks/fan.yml) - run the playbook, then re-enable this plugin."
            });
        });
    }
}
