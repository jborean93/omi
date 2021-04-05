TOP = ..
include $(TOP)/config.mak

ifeq ($(OS)-$(ARCH),HPUX-PARISC)
CXXSHLIBRARY = base
else
LIBRARY = base
endif

# JBOREAN CHANGE: We can cut down what is not needed for the WSMan client
# Removed:
#   classdecl.c
#   env.c
#   fieldprint.c
#   getopt.c
#   indent.c
#   instanceprint.c
#   interaction.c
#   messagesprint.c
#   miextras.c
#   multiplex.c
#   parameters.c
#   pidfile.c
#   process.c
#   ptrarray.c
#   random.c
#   stringarray.c
SOURCES = \
    base.c \
    batch.c \
    buf.c \
    class.c \
    instance.c \
    messages.c \
    list.c \
    result.c \
    schemadecl.c \
    types.c \
    packing.c \
    helpers.c \
    naming.c \
    field.c \
    paths.c \
    strand.c \
    strarr.c \
    user.c \
    credcache.c \
    conf.c \
    base64.c \
    timer.c \
    $(TOP)/sock/sock.c \
    $(TOP)/sock/addr.c \
    $(TOP)/sock/selector.c

ifeq ($(ENABLE_PREEXEC),1)
 SOURCES += preexec.c
endif

ifdef SUNOS_SPARC_SUNPRO
    SOURCES += sunsparc8_atomic.s
endif

INCLUDES = $(TOP) $(TOP)/common $(TOP)/base

DEFINES = MI_CONST= HOOK_BUILD

LIBRARIES = pal

include $(TOP)/mak/rules.mak
