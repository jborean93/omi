TOP = ..
include $(TOP)/config.mak

GENERATE_ORIGIN=0
ifeq ($(OS),LINUX)
  GENERATE_ORIGIN=1
endif
ifeq ($(OS),DARWIN)
  GENERATE_ORIGIN=1
endif

# JBOREAN CHANGE: We only need origin for PowerShell
# origin uses rpath = $ORIGIN allowing us to load libs in the same dir
DIRECTORIES = origin

#ifeq ($(GENERATE_ORIGIN),1)
#	DIRECTORIES = release origin
#else
#	DIRECTORIES = release
#endif

include $(ROOT)/mak/rules.mak
