// Lets the primary user start/stop/restart openconnect-luc@1000.service
// (the root-privileged half of the openconnect VPN backend,
// modules/globalprotect-openconnect.nix) without a polkit password prompt --
// same narrow, single-unit grant pattern as scripts/polkit-fprint-enroll.js.
// Scoped to exactly this unit name and this user; nothing else is granted,
// and no other unit (including by wildcard) is covered.
polkit.addRule(function (action, subject) {
  if (
    action.id === "org.freedesktop.systemd1.manage-units" &&
    action.lookup("unit") === "openconnect-luc@1000.service" &&
    subject.user === "joelsgc"
  ) {
    return polkit.Result.YES;
  }
});
