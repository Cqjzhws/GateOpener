TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = GateOpener

GateOpener_FILES = Tweak.xm
GateOpener_FRAMEWORKS = UIKit Foundation WebKit
GateOpener_CFLAGS = -fobjc-arc -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/tweak.mk
