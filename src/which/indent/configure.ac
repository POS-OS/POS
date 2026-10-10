dnl Process this file with autoconf to produce a configure script.
AC_PREREQ([2.71])
AC_INIT([GNU Indent],[2.2.13],[bug-indent@gnu.org])
AC_CONFIG_SRCDIR(src/indent.c)
AC_CONFIG_AUX_DIR(config)
AC_CONFIG_HEADERS([config.h])
AC_USE_SYSTEM_EXTENSIONS
AC_SYS_LARGEFILE
AM_INIT_AUTOMAKE

AM_MAINTAINER_MODE

dnl Checks for programs.
AC_PROG_CC
AC_PROG_CPP
AC_PROG_INSTALL
AX_CC_FOR_BUILD

dnl Checks for UNIX variants that set DEFS,
AC_SEARCH_LIBS([strerror],[cposix])

dnl Checks for compiler output filename suffixes.
AC_EXEEXT
AC_OBJEXT

dnl Checks for typedefs, structures, and compiler characteristics.
dnl AM_C_PROTOTYPES
AC_C_CONST

dnl Check for tools needed for formatting the documentation.
ac_aux_dir_abs=`cd $ac_aux_dir && pwd`
AC_PATH_PROG(DVIPS, dvips, $ac_aux_dir_abs/missing dvips)

dnl These are the only lines required to internationalize the package.
dnl (OK, not quite, the AC_OUTPUT has also some parts.)
AM_GNU_GETTEXT([external])
AM_GNU_GETTEXT_VERSION([0.18.3])

AH_TEMPLATE(HAVE_LC_MESSAGES)
AH_TEMPLATE(ENABLE_NLS)
AH_TEMPLATE(HAVE_GETTEXT)
AH_TEMPLATE(HAVE_CATGETS)
AH_TEMPLATE(HAVE_STPCPY)

localedir=${datadir}/locale
AC_SUBST(localedir)

AC_CHECK_INCLUDES_DEFAULT
AC_PROG_EGREP

AC_CHECK_FUNCS(setlocale strchr memcpy memmove utime)
AC_CHECK_HEADERS(unistd.h string.h malloc.h utime.h sys/utime.h)

if test "$ac_cv_func_utime" = yes
then
   if test "$ac_cv_header_utime_h" = yes
   then
      indent_UTIMBUF
   fi
fi

AC_HEADER_DIRENT

AC_CONFIG_FILES([
   po/Makefile.in
   Makefile
   src/Makefile
   doc/Makefile
   man/Makefile
])
AC_CONFIG_COMMANDS([default],[touch Makefile.in],[])
AC_OUTPUT
