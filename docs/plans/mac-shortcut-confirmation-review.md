# Dayflow Command-Q confirmation follow-up

User clarification 25 Nov: Command-Q truly quits, but first confirms and explains
that Command-W or the red close button only closes the window. No soft-quit.

Own adversarial delta review RAN: ordinary menu and Dock quit converge on the
same prompt; accepted menu action permits termination so no duplicate prompt.
Cancel does not change termination state or release recording resources. Existing
explicit reset, permission and restart reasons bypass the ordinary quit prompt.
Command-H remains separate native hide. Native NSAlert uses Quit Dayflow and
Cancel. No auth/DB/crypto/workflow changes. Version 2.9.4/build182.

Portable source checks pass. XCTest added for confirm/cancel and restart bypass;
macOS compile/runtime, actual NSAlert pixels and capture-stop acceptance await
native CI/device validation. No claim those ran locally. PR only, no merge grant.

Status-bar follow-up 25 Nov: its Quit now uses the same confirmation helper,
preserving the menu_bar_quit diagnostic reason only after confirmation. Added
native confirm/cancel/no-double-prompt coverage for the actual status-bar helper.
Portable status-bar guard failed first, then passed. Updated PERFORMANCE and both
changelog copies, keeping older behavior explicitly historical. Full repository
quit-doc search completed; no workflow/auth/DB/crypto changes. Native dialog pixels
and recording-stop acceptance still require macOS, and are not claimed here.
