# PortBridge Privacy

PortBridge does not collect, transmit, or store any personal data.

## Update checks

To detect new releases, PortBridge sends anonymous HTTPS `GET` requests to
`https://api.github.com/repos/yhzion/PortBridge/releases/latest`. These requests
include only a generic `User-Agent` header (`PortBridge/<version>`) as required
by the GitHub API. No user data, identifiers beyond your IP address (visible to
GitHub by virtue of the connection), or usage statistics are sent.

Update checks fire:

- Once when the app launches (subject to a 24-hour debounce)
- When you select "Check for Updates Now…" from the menu bar

You can disable automatic checks in the menu bar by unticking
"Check for Updates Automatically". Manual checks remain available.

## SSH and forwarding

PortBridge spawns local `ssh` processes to establish port forwards to the
servers you configure. Connection data (server addresses, credentials handled
by SSH) never leaves your machine via PortBridge itself.

## No telemetry

PortBridge has no analytics, crash reporting, or telemetry of any kind.
