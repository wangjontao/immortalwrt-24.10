#
# JuLiang OS v2.8.5 LuCI theme
#

include $(TOPDIR)/rules.mk

LUCI_TITLE:=JuLiang OS Network Console Theme
LUCI_DEPENDS:=+luci-base

PKG_VERSION:=2.8.5
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=JuLiang OS

define Package/luci-theme-juliang/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	uci -q delete luci.themes.JuLiang
	if [ "$$(uci -q get luci.main.mediaurlbase)" = "/luci-static/juliang" ]; then
		uci -q set luci.main.mediaurlbase=/luci-static/bootstrap
	fi
	uci commit luci
}
endef

include ../../luci.mk

# call BuildPackage - OpenWrt buildroot signature
