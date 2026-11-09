(function () {
	"use strict";

	var STATUS_URL = "/cgi-bin/luci/admin/home/status";
	var REFRESH_MS = 30000;
	var running = false;

	function byId(id) {
		return document.getElementById(id);
	}

	function setText(id, text) {
		var node = byId(id);
		if (node && node.textContent !== text) {
			node.textContent = text;
		}
	}

	function flagFor(code) {
		if (!/^[A-Z]{2}$/.test(code)) {
			return "";
		}
		return String.fromCodePoint(
			0x1f1e6 + code.charCodeAt(0) - 65,
			0x1f1e6 + code.charCodeAt(1) - 65
		);
	}

	function countryName(code) {
		if (!code) {
			return "未知地区";
		}
		try {
			return new Intl.DisplayNames(["zh-CN"], { type: "region" }).of(code) || code;
		} catch (error) {
			return code === "CN" ? "中国" : code;
		}
	}

	async function refreshBrand() {
		if (running || document.hidden) {
			return;
		}
		running = true;

		var dot = byId("jl-brand-dot");
		var controller = window.AbortController ? new AbortController() : null;
		var timer = controller ? setTimeout(function () { controller.abort(); }, 8000) : null;

		try {
			var response = await fetch(STATUS_URL + "?_=" + Date.now(), {
				cache: "no-store",
				credentials: "same-origin",
				signal: controller ? controller.signal : undefined
			});
			if (!response.ok) {
				throw new Error("HTTP " + response.status);
			}

			var data = await response.json();
			var egress = data.egress || {};
			var wan = data.wan || {};
			var ip = egress.ip || wan.ip || "";
			var code = String(egress.country || "").toUpperCase();
			var mode = egress.mode === "proxy" ? "proxy" : "direct";
			var country = countryName(code);
			var modeNode = byId("jl-brand-mode");

			setText("jl-brand-ip", ip || "等待连接");
			setText("jl-brand-country", (flagFor(code) ? flagFor(code) + " " : "") + country + (code ? " · " + code : ""));
			setText("jl-brand-mode", mode === "proxy" ? "PROXY" : "DIRECT");

			if (modeNode) {
				modeNode.classList.toggle("proxy", mode === "proxy");
			}
			if (dot) {
				dot.classList.toggle("offline", !ip);
			}
			if (ip) {
				byId("jl-brand-ip").title = egress.node
					? "当前出口节点：" + egress.node
					: "当前出口 IP：" + ip;
			}
		} catch (error) {
			if (!byId("jl-brand-ip")?.textContent || byId("jl-brand-ip").textContent === "正在检测") {
				setText("jl-brand-ip", "暂不可用");
				setText("jl-brand-country", "地区未知");
				setText("jl-brand-mode", "OFFLINE");
			}
			if (dot) {
				dot.classList.add("offline");
			}
		} finally {
			if (timer) {
				clearTimeout(timer);
			}
			running = false;
		}
	}

	function init() {
		if (!byId("jl-brand-ip")) {
			return;
		}
		refreshBrand();
		setInterval(refreshBrand, REFRESH_MS);
		document.addEventListener("visibilitychange", function () {
			if (!document.hidden) {
				refreshBrand();
			}
		});
	}

	if (document.readyState === "loading") {
		document.addEventListener("DOMContentLoaded", init, { once: true });
	} else {
		init();
	}
})();
