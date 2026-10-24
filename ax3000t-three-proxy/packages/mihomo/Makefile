# Pinned official ARM64 release, verified by SHA256; no unverified mirrors.
include $(TOPDIR)/rules.mk
PKG_NAME:=mihomo
PKG_VERSION:=1.19.33
PKG_RELEASE:=1
PKG_SOURCE:=mihomo-linux-arm64-v1.19.33.gz
PKG_SOURCE_URL:=https://github.com/MetaCubeX/mihomo/releases/download/v1.19.33
PKG_HASH:=ba408b317080ee265c46cb923a50018c1b82cbd708551cdd46a1e3e307396187
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)-prebuilt
PKG_LICENSE:=GPL-3.0-only
include $(INCLUDE_DIR)/package.mk

define Package/mihomo
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Official mihomo ARM64 1.19.33
  DEPENDS:=@aarch64 +ca-bundle +kmod-tun
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	gzip -dc $(DL_DIR)/$(PKG_SOURCE) > $(PKG_BUILD_DIR)/mihomo
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/mihomo/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/mihomo $(1)/usr/bin/mihomo
	$(INSTALL_DIR) $(1)/etc/openclash/core
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/mihomo $(1)/etc/openclash/core/clash_meta
endef

$(eval $(call BuildPackage,mihomo))
