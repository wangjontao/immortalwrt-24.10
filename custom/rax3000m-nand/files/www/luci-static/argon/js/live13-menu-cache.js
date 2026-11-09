(function () {
	"use strict";

	var revision = "live13-20261109-upnp";
	var key = "luci-session-store";

	try {
		var sessions = JSON.parse(sessionStorage.getItem(key) || "{}");
		if (!sessions || typeof sessions !== "object") {
			sessions = {};
		}

		Object.keys(sessions).forEach(function (id) {
			var entry = sessions[id];
			if (!entry || typeof entry !== "object") {
				return;
			}
			if (entry.juliangMenuRevision !== revision) {
				delete entry.menu;
				entry.juliangMenuRevision = revision;
			}
		});

		sessionStorage.setItem(key, JSON.stringify(sessions));
	} catch (error) {
		/* Storage can be unavailable in private browsing modes. */
	}
})();
