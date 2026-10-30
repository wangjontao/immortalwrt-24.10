# Pinned official ARM64 release, verified by SHA256; no unverified mirrors.
include $(TOPDIR)/rules.mk
PKG_NAME:=xray-core
PKG_VERSION:=26.10.21
PKG_RELEASE:=1
PKG_SOURCE:=Xray-linux-arm64-v8a.zip
PKG_SOURCE_URL:=https://github.com/XTLS/Xray-core/releases/download/v26.10.21
PKG_HASH:=d1304946c486d98e6b886e9b931eaaaebb23835b30e217638037b7f2721d4e9c
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)-prebuilt
PKG_LICENSE:=MPL-2.0
include $(INCLUDE_DIR)/package.mk

define Package/xray-core
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Official xray-core ARM64 26.10.21
  DEPENDS:=@aarch64 +ca-bundle +kmod-tun
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	unzip -j -o $(DL_DIR)/$(PKG_SOURCE) xray -d $(PKG_BUILD_DIR)
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/xray-core/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/xray $(1)/usr/bin/xray
endef

$(eval $(call BuildPackage,xray-core))
